"""Règles ajoutées par la revue d'octobre 2026 (migration 0022, plans/17-revue-du-code.md), contre la pile Docker.

Chacun est propriétaire de son « Espace de … » : il y crée politiques, factures et tâches, et ne doit pas pouvoir
s'en servir pour agir dans le workspace de son entreprise.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from .test_backend import ENV, SUPABASE, _call, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

SERVICE = ENV.get("SERVICE_ROLE_KEY", "")


def _own_workspace(token: str, uid: str) -> str:
    _, rows = rest("GET", f"workspace_members?user_id=eq.{uid}&role=eq.owner&select=workspace_id", token)
    return rows[0]["workspace_id"]


@pytest.fixture(scope="module")
def company():
    boss_t, boss = signup("direction")
    wid = _own_workspace(boss_t, boss)
    people = {"boss": (boss_t, boss)}
    for name, role in (("chef", "admin"), ("salarie", "member")):
        t, uid = signup(name)
        assert rest("POST", "workspace_members", boss_t,
                    {"workspace_id": wid, "user_id": uid, "role": role, "display_name": name})[0] == 201
        people[name] = (t, uid)
    return {"wid": wid, **people}


def test_a_time_off_policy_of_another_workspace_is_refused(company):
    t, uid = company["salarie"]
    mine = _own_workspace(t, uid)
    policy = str(uuid.uuid4())
    assert rest("POST", "time_off_policies", t, {"id": policy, "workspace_id": mine, "name": "Libre",
                                                  "requires_approval": False})[0] == 201
    start = (date.today() + timedelta(days=40)).isoformat()
    status, body = rest("POST", "time_off_requests", t, {"workspace_id": company["wid"], "user_id": uid,
                                                          "policy_id": policy, "start_date": start, "end_date": start,
                                                          "amount": 1})
    assert status == 400 and body["code"] == "23514", body


def test_only_an_owner_gives_or_takes_the_owner_role(company):
    chef_t, chef = company["chef"]
    boss_t, _ = company["boss"]
    _, salarie = company["salarie"]
    status, body = rest("PATCH", f"workspace_members?workspace_id=eq.{company['wid']}&user_id=eq.{chef}", chef_t,
                        {"role": "owner"})
    assert status == 403 and body["code"] == "42501", "un admin ne se fait pas propriétaire"
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{company['wid']}&user_id=eq.{salarie}", chef_t,
                {"role": "manager"})[0] == 200, "il gère toujours les autres rôles"
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{company['wid']}&user_id=eq.{salarie}", boss_t,
                {"role": "member"})[0] == 200


def test_a_member_does_not_change_their_capacity(company):
    t, uid = company["salarie"]
    status, body = rest("PATCH", f"workspace_members?workspace_id=eq.{company['wid']}&user_id=eq.{uid}", t,
                        {"capacity_hours_per_day": 3})
    assert status == 403 and body["code"] == "42501"
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{company['wid']}&user_id=eq.{uid}", t,
                {"display_name": "Salarié"})[0] == 200


def test_the_creator_of_a_task_does_not_move_it_under_another(company):
    boss_t, _ = company["boss"]
    t, _ = company["salarie"]
    wid = company["wid"]
    assert rest("PATCH", f"workspaces?id=eq.{wid}", boss_t, {"task_creation": "everyone"})[0] == 200
    project = str(uuid.uuid4())
    assert rest("POST", "projects", boss_t, {"id": project, "workspace_id": wid, "name": "Chantier"})[0] == 201
    first, second = str(uuid.uuid4()), str(uuid.uuid4())
    for tid, name in ((first, "Gros œuvre"), (second, "Second œuvre")):
        assert rest("POST", "tasks", t, {"id": tid, "workspace_id": wid, "project_id": project, "name": name})[0] == 201
    status, body = rest("PATCH", f"tasks?id=eq.{second}", t, {"parent_id": first})
    assert status == 403 and body["code"] == "42501"
    assert rest("PATCH", f"tasks?id=eq.{second}", boss_t, {"parent_id": first})[0] == 200

    # Sous-tâche créée hors ligne sous une tâche supprimée entre-temps : elle part avec elle.
    assert rest("PATCH", f"tasks?id=eq.{first}", boss_t, {"deleted_at": iso(datetime.now(UTC))})[0] == 200
    late = str(uuid.uuid4())
    assert rest("POST", "tasks", t, {"id": late, "workspace_id": wid, "project_id": project, "name": "Finitions",
                                     "parent_id": first})[0] == 201
    _, [row] = rest("GET", f"tasks?id=eq.{late}&select=deleted_at", SERVICE)
    assert row["deleted_at"] is not None


def test_the_reminded_person_only_marks_a_reminder_seen(company):
    boss_t, _ = company["boss"]
    t, uid = company["salarie"]
    rid = str(uuid.uuid4())
    assert rest("POST", "reminders", boss_t, {"id": rid, "workspace_id": company["wid"], "user_id": uid,
                                              "period_start": "2026-10-19"})[0] == 201
    status, body = rest("PATCH", f"reminders?id=eq.{rid}", t, {"deleted_at": iso(datetime.now(UTC))})
    assert status == 403 and body["code"] == "42501"
    assert rest("PATCH", f"reminders?id=eq.{rid}", t, {"seen_at": iso(datetime.now(UTC))})[0] == 200
    assert rest("PATCH", f"reminders?id=eq.{rid}", boss_t, {"deleted_at": iso(datetime.now(UTC))})[0] == 200


def test_a_new_timer_stops_a_locked_one(company):
    t, uid = company["salarie"]
    wid = company["wid"]
    now = datetime.now(UTC).replace(microsecond=0)
    old, new = str(uuid.uuid4()), str(uuid.uuid4())
    assert rest("POST", "time_entries", t, {"id": old, "workspace_id": wid, "user_id": uid,
                                            "start_at": iso(now - timedelta(hours=2))})[0] == 201
    assert rest("PATCH", f"time_entries?id=eq.{old}", SERVICE, {"locked": True})[0] == 200
    status, body = rest("POST", "time_entries", t, {"id": new, "workspace_id": wid, "user_id": uid,
                                                    "start_at": iso(now)})
    assert status == 201, body
    _, [row] = rest("GET", f"time_entries?id=eq.{old}&select=end_at", SERVICE)
    assert row["end_at"] is not None and datetime.fromisoformat(row["end_at"]) == now


def test_invoices_and_tags_stay_in_their_workspace(company):
    chef_t, chef = company["chef"]
    t, uid = company["salarie"]
    entry = str(uuid.uuid4())
    start = datetime.now(UTC).replace(microsecond=0) - timedelta(days=3)
    assert rest("POST", "time_entries", t, {"id": entry, "workspace_id": company["wid"], "user_id": uid,
                                            "start_at": iso(start), "end_at": iso(start + timedelta(hours=1))})[0] == 201
    mine = _own_workspace(chef_t, chef)
    invoice = str(uuid.uuid4())
    assert rest("POST", "invoices", chef_t, {"id": invoice, "workspace_id": mine})[0] == 201
    status, body = rest("POST", "invoice_entries", chef_t, {"workspace_id": mine, "invoice_id": invoice,
                                                            "time_entry_id": entry})
    assert status == 400 and body["code"] == "23514", body

    tag = str(uuid.uuid4())
    assert rest("POST", "tags", chef_t, {"id": tag, "workspace_id": mine, "name": "Perso"})[0] == 201
    status, body = rest("POST", "time_entry_tags", t, {"workspace_id": company["wid"], "user_id": uid,
                                                       "time_entry_id": entry, "tag_id": tag})
    assert status == 400 and body["code"] == "23514", body


def test_the_rate_of_an_entry_is_set_by_the_server_except_for_managers(company):
    boss_t, _ = company["boss"]
    t, uid = company["salarie"]
    wid = company["wid"]
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{wid}&user_id=eq.{uid}", boss_t,
                {"hourly_rate_cents": 5000})[0] == 200
    paid, unpaid = str(uuid.uuid4()), str(uuid.uuid4())
    assert rest("POST", "projects", boss_t, {"id": paid, "workspace_id": wid, "name": "Régie",
                                             "hourly_rate_cents": 8000})[0] == 201
    assert rest("POST", "projects", boss_t, {"id": unpaid, "workspace_id": wid, "name": "Interne"})[0] == 201
    entry = str(uuid.uuid4())
    start = datetime.now(UTC).replace(microsecond=0) - timedelta(days=2)

    def rate() -> int | None:
        _, [row] = rest("GET", f"time_entries?id=eq.{entry}&select=hourly_rate_cents", SERVICE)
        return row["hourly_rate_cents"]

    assert rest("POST", "time_entries", t, {"id": entry, "workspace_id": wid, "user_id": uid, "project_id": paid,
                                            "start_at": iso(start), "end_at": iso(start + timedelta(hours=1)),
                                            "hourly_rate_cents": 99900})[0] == 201
    assert rate() == 8000, "celui du projet"
    assert rest("PATCH", f"time_entries?id=eq.{entry}", t, {"hourly_rate_cents": 1})[0] == 200
    assert rate() == 8000, "inchangé"
    assert rest("PATCH", f"time_entries?id=eq.{entry}", t, {"project_id": unpaid, "hourly_rate_cents": 1})[0] == 200
    assert rate() == 5000, "projet sans taux : celui du membre"
    assert rest("PATCH", f"time_entries?id=eq.{entry}", boss_t, {"hourly_rate_cents": 6500})[0] == 200
    assert rate() == 6500, "un manager le fixe"


def test_internal_functions_are_not_rpc(company):
    t, _ = company["salarie"]
    status, _ = _call("POST", f"{SUPABASE}/rest/v1/rpc/team_scope_wanted", t, {"wid": company["wid"]})
    assert status in (401, 403, 404)
