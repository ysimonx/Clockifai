"""Assistant « Demander à Clockifai » (plans/13-ux-moderne.md, lot 12) contre la pile Docker : les outils lisent ce
que la personne peut voir, sans les descriptions ; l'assistant est désactivé sans clé d'API."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

import psycopg
import pytest
from psycopg.rows import dict_row

from app.services import assistant

from .test_backend import ENV, SERVICES, _call, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

SERVICE = ENV.get("SERVICE_ROLE_KEY", "")
DSN = (f"postgresql://postgres.{ENV.get('POOLER_TENANT_ID', '')}:{ENV.get('POSTGRES_PASSWORD', '')}"
       f"@localhost:{ENV.get('POSTGRES_PORT', '5432')}/postgres")


@pytest.fixture(scope="module")
def studio():
    owner_t, owner = signup("chef")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    member_t, member = signup("membre")
    assert rest("POST", "workspace_members", owner_t,
                {"workspace_id": wid, "user_id": member, "role": "member", "display_name": "Membre"})[0] == 201
    client = str(uuid.uuid4())
    project = str(uuid.uuid4())
    assert rest("POST", "clients", owner_t, {"id": client, "workspace_id": wid, "name": "Boulangerie"})[0] == 201
    assert rest("POST", "projects", owner_t, {"id": project, "workspace_id": wid, "name": "Site",
                                              "client_id": client})[0] == 201
    entries = {}
    for who, token, uid, day, hours, proj in (
        ("chef", owner_t, owner, 19, 3, project),
        ("membre", member_t, member, 19, 2, project),
        ("membre-sans-projet", member_t, member, 20, 1, None),
    ):
        eid = str(uuid.uuid4())
        status, _ = rest("POST", "time_entries", token, {
            "id": eid, "workspace_id": wid, "user_id": uid, "project_id": proj, "description": f"secret {who}",
            "start_at": iso(datetime(2026, 10, day, 8, tzinfo=UTC)),
            "end_at": iso(datetime(2026, 10, day, 8 + hours, tzinfo=UTC)), "billable": True,
            "hourly_rate_cents": 5000}, prefer="return=minimal")
        assert status == 201
        entries[who] = eid
    return {"wid": wid, "owner": owner, "member": member, "member_t": member_t, "project": project,
            "client": client, "entries": entries}


def test_scope_and_tools(studio):
    week = {"date_from": "2026-10-19", "date_to": "2026-10-25"}
    with psycopg.connect(DSN, row_factory=dict_row) as conn:
        everyone = assistant.scope_for(conn, studio["wid"], studio["owner"], "owner")
        mine = assistant.scope_for(conn, studio["wid"], studio["member"], "member")
        assert everyone.user_ids is None and mine.user_ids == [studio["member"]]

        by_person = assistant.time_summary(conn, everyone, {**week, "group_by": "person"}, "Europe/Paris")
        assert sorted(r["duration"] for r in by_person) == ["3:00", "3:00"]
        by_client = assistant.time_summary(conn, mine, {**week, "group_by": "client"}, "Europe/Paris")
        assert {r["label"]: (r["duration"], r["amount"]) for r in by_client} == {
            "Boulangerie": ("2:00", 100.0), "(sans client)": ("1:00", 50.0)}

        found = assistant.find_entries(conn, mine, {**week, "without_project": True}, "Europe/Paris")
        assert [e["id"] for e in found["entries"]] == [studio["entries"]["membre-sans-projet"]]
        assert "secret" not in str(found), "jamais les descriptions"

        people = assistant.list_catalog(conn, mine, {"kind": "people"})
        assert [p["id"] for p in people] == [studio["member"]]

        # Une proposition ne garde que les entrées que la personne peut lire.
        proposals: list[dict] = []
        assistant.run_tool(conn, mine, "Europe/Paris", "propose_update",
                           {"entry_ids": [studio["entries"]["membre"], studio["entries"]["chef"]], "billable": False,
                            "summary": "Non facturable"}, proposals)
        assert proposals == [{"billable": False, "summary": "Non facturable", "entry_ids": [studio["entries"]["membre"]]}]
        with pytest.raises(ValueError):
            assistant.run_tool(conn, mine, "Europe/Paris", "find_entries",
                               {"date_from": "2026-10-25", "date_to": "2026-10-19"}, [])
    assert date(2026, 10, 19).weekday() == 0


def test_disabled_without_api_key(studio):
    status, body = _call("GET", f"{SERVICES}/api/assistant/status", studio["member_t"])
    assert (status, body) == (200, {"enabled": False})
    status, body = _call("POST", f"{SERVICES}/api/assistant/ask", studio["member_t"],
                         {"workspace_id": studio["wid"], "question": "Combien cette semaine ?"})
    assert (status, body) == (503, {"error": "assistant_disabled"})
