"""Agents Claude membres de l'équipe : compte technique, droits du pilote, écritures du serveur.

Plan : plans/10-suivi-claude-code.md (D2, D7.8, D14, D15)
"""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from .test_backend import ENV, SERVICES, SUPABASE, _call, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

SERVICE = ENV.get("SERVICE_ROLE_KEY", "")


def _add_member(owner_t: str, wid: str, uid: str, name: str) -> str:
    status, rows = rest("POST", "workspace_members", owner_t,
                        {"workspace_id": wid, "user_id": uid, "role": "member", "display_name": name})
    assert status == 201, rows
    return rows[0]["id"]


def _create_agent(wid: str, pilot: str) -> str:
    """Ce que fera ensure_agent (Flask) : compte technique banni, puis membre agent du workspace."""
    status, user = _call("POST", f"{SUPABASE}/auth/v1/admin/users", SERVICE, {
        "email": f"agent-{uuid.uuid4().hex[:12]}@agents.test.local",
        "email_confirm": True,
        "app_metadata": {"kind": "agent", "owner_id": pilot},
        "user_metadata": {"display_name": "Claude", "kind": "agent"},
        "ban_duration": "876000h",
    })
    assert status == 200, user
    status, rows = rest("POST", "workspace_members", SERVICE, {
        "workspace_id": wid, "user_id": user["id"], "role": "member", "kind": "agent",
        "agent_owner_id": pilot, "display_name": "Claude"})
    assert status == 201, rows
    return user["id"]


def _write(squad, entry_id: str, start: datetime, end: datetime | None, agent: str | None = None, **extra):
    params = {"p_id": entry_id, "p_workspace_id": squad["wid"], "p_agent_id": agent or squad["agent"],
              "p_pilot_id": squad["people"]["pilote"][1], "p_start_at": iso(start),
              "p_end_at": iso(end) if end else None, "p_project_id": None, "p_task_id": None,
              "p_description": "travail de Claude", "p_billable": True, "p_hourly_rate_cents": None, **extra}
    status, result = _call("POST", f"{SUPABASE}/rest/v1/rpc/agent_entry_write", SERVICE, params)
    assert status == 200, result
    return result


def _now() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


@pytest.fixture(scope="module")
def squad():
    """« patron » (owner) ; « pilote » pilote l'agent ; « chef » encadre le pilote ; « autre » est un simple membre."""
    owner_t, owner = signup("patron")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    people = {"owner": (owner_t, owner)}
    member_ids = {}
    for name in ("pilote", "chef", "autre", "pilote2"):
        t, uid = signup(name)
        people[name] = (t, uid)
        member_ids[name] = _add_member(owner_t, wid, uid, name)
    assert rest("POST", "team_manager_assignments", owner_t,
                {"workspace_id": wid, "manager_id": people["chef"][1], "user_id": people["pilote"][1]})[0] == 201
    agent = _create_agent(wid, people["pilote"][1])
    return {"wid": wid, "people": people, "member_ids": member_ids, "agent": agent}


def test_agent_account_has_no_personal_workspace(squad):
    _, rows = rest("GET", f"workspaces?created_by=eq.{squad['agent']}&select=id", SERVICE)
    assert rows == []
    _, rows = rest("GET", f"profiles?id=eq.{squad['agent']}&select=display_name", SERVICE)
    assert rows == [{"display_name": "Claude"}]


def test_agents_are_created_by_the_server_only(squad):
    owner_t, _ = squad["people"]["owner"]
    _, someone = signup("intrus")
    status, err = rest("POST", "workspace_members", owner_t, {
        "workspace_id": squad["wid"], "user_id": someone, "role": "member", "kind": "agent",
        "agent_owner_id": squad["people"]["owner"][1], "display_name": "Faux agent"})
    assert status >= 400 and err["code"] == "42501"
    status, err = rest("PATCH", f"workspace_members?id=eq.{squad['member_ids']['autre']}", owner_t, {"kind": "agent"})
    assert status >= 400 and err["code"] == "42501"


def test_agent_role_stays_member(squad):
    owner_t, _ = squad["people"]["owner"]
    status, err = rest("PATCH", f"workspace_members?user_id=eq.{squad['agent']}&workspace_id=eq.{squad['wid']}",
                       owner_t, {"role": "admin"})
    assert status >= 400 and err["code"] == "23514"


def test_pilot_and_his_team_manager_see_the_agent(squad):
    for name in ("pilote", "chef"):
        token, uid = squad["people"][name]
        _, rows = rest("GET", f"team_scope?manager_id=eq.{uid}&select=user_id", token)
        assert squad["agent"] in {r["user_id"] for r in rows}, name
    autre_t, autre = squad["people"]["autre"]
    _, rows = rest("GET", f"team_scope?manager_id=eq.{autre}&select=user_id", autre_t)
    assert rows == []


def test_nobody_creates_agent_time_from_the_app(squad):
    start = _now() - timedelta(hours=3)
    body = {"id": str(uuid.uuid4()), "workspace_id": squad["wid"], "user_id": squad["agent"],
            "start_at": iso(start), "end_at": iso(start + timedelta(hours=1))}
    for name in ("pilote", "owner"):
        status, err = rest("POST", "time_entries", squad["people"][name][0], {**body, "id": str(uuid.uuid4())})
        assert status >= 400 and err["code"] == "42501", name


def test_server_writes_agent_entries(squad):
    pilote_t, pilote = squad["people"]["pilote"]
    entry = str(uuid.uuid4())
    start = _now() - timedelta(hours=2)
    assert _write(squad, entry, start, start + timedelta(minutes=40)) == "ok"
    _, rows = rest("GET", f"time_entries?id=eq.{entry}&select=user_id,source,created_by,description", SERVICE)
    assert rows == [{"user_id": squad["agent"], "source": "agent", "created_by": pilote,
                     "description": "travail de Claude"}]
    # Lecture : le pilote et son chef, pas un autre membre.
    for name, expected in (("pilote", 1), ("chef", 1), ("autre", 0)):
        _, rows = rest("GET", f"time_entries?id=eq.{entry}&select=id", squad["people"][name][0])
        assert len(rows) == expected, name
    # Correction par le pilote, même avec time_for_others = 'admins' (le défaut).
    status, rows = rest("PATCH", f"time_entries?id=eq.{entry}", pilote_t, {"description": "export des rapports"})
    assert status == 200 and rows[0]["description"] == "export des rapports"
    status, rows = rest("PATCH", f"time_entries?id=eq.{entry}", squad["people"]["autre"][0], {"description": "x"})
    assert status == 200 and rows == []


def test_export_filters_humans_and_agents(squad):
    """Filtre « Humains / Agents » des rapports (`member_kind`) et colonne « Type » de l'export (plan 10, §8)."""
    pilote_t, pilote = squad["people"]["pilote"]
    start = _now() - timedelta(hours=8)
    assert _write(squad, str(uuid.uuid4()), start, start + timedelta(minutes=30),
                  p_description="session exportée") == "ok"
    assert rest("POST", "time_entries", pilote_t, {
        "id": str(uuid.uuid4()), "workspace_id": squad["wid"], "user_id": pilote, "description": "saisie du pilote",
        "start_at": iso(start), "end_at": iso(start + timedelta(minutes=45))})[0] == 201
    day = start.date().isoformat()
    url = f"{SERVICES}/api/exports/report?workspace_id={squad['wid']}&from={day}&to={day}&format=csv"

    def lines(kind: str = "") -> str:
        status, body = _call("GET", url + (f"&member_kind={kind}" if kind else ""), pilote_t)
        assert status == 200, body
        return body.decode("utf-8-sig")

    both = lines()
    assert "session exportée" in both and "saisie du pilote" in both
    agents = lines("agent")
    assert "session exportée" in agents and "saisie du pilote" not in agents
    humans = lines("human")
    assert "saisie du pilote" in humans and "session exportée" not in humans
    assert lines("robot") == both, "valeur inconnue ignorée"

    # Colonne « Type » du détail : humain ou agent.
    rows = list(csv.reader(io.StringIO(both), delimiter=";"))
    kind = rows[0].index("Type")
    by_description = {r[rows[0].index("Description")]: r[kind] for r in rows[1:]}
    assert by_description["session exportée"] == "agent"
    assert by_description["saisie du pilote"] == "humain"


def test_entry_never_changes_person(squad):
    pilote_t, pilote = squad["people"]["pilote"]
    entry = str(uuid.uuid4())
    start = _now() - timedelta(hours=5)
    assert _write(squad, entry, start, start + timedelta(minutes=20)) == "ok"
    status, err = rest("PATCH", f"time_entries?id=eq.{entry}", pilote_t, {"user_id": pilote})
    assert status >= 400 and err["code"] == "42501"


def test_parallel_sessions_run_together(squad):
    owner_t, _ = squad["people"]["owner"]
    assert rest("PATCH", f"workspaces?id=eq.{squad['wid']}", owner_t, {"max_running_timers": 1})[0] == 200
    ids = [str(uuid.uuid4()) for _ in range(3)]
    start = _now() - timedelta(minutes=30)
    for i, entry in enumerate(ids):
        assert _write(squad, entry, start + timedelta(minutes=i), None) == "ok"
    _, rows = rest("GET", f"time_entries?id=in.({','.join(ids)})&end_at=is.null&select=id", SERVICE)
    assert len(rows) == 3


def test_server_respects_protected_entries(squad):
    owner_t, _ = squad["people"]["owner"]
    start = _now() - timedelta(hours=1)
    # Supprimée par le pilote : plus jamais réécrite.
    deleted = str(uuid.uuid4())
    assert _write(squad, deleted, start, start + timedelta(minutes=10)) == "ok"
    assert rest("PATCH", f"time_entries?id=eq.{deleted}", squad["people"]["pilote"][0],
                {"deleted_at": iso(_now())})[0] == 200
    assert _write(squad, deleted, start, start + timedelta(minutes=30)) == "deleted"
    # Verrouillée par un admin.
    locked = str(uuid.uuid4())
    assert _write(squad, locked, start, start + timedelta(minutes=10)) == "ok"
    assert rest("PATCH", f"time_entries?id=eq.{locked}", owner_t, {"locked": True})[0] == 200
    assert _write(squad, locked, start, start + timedelta(minutes=30)) == "locked"
    # Avant la date de verrouillage du workspace.
    assert rest("PATCH", f"workspaces?id=eq.{squad['wid']}", owner_t,
                {"lock_entries_before": (date.today() + timedelta(days=1)).isoformat()})[0] == 200
    try:
        assert _write(squad, str(uuid.uuid4()), start, start + timedelta(minutes=10)) == "locked_period"
    finally:
        rest("PATCH", f"workspaces?id=eq.{squad['wid']}", owner_t, {"lock_entries_before": None})
    # Dans une période approuvée de l'agent.
    old = datetime.combine(date.today() - timedelta(days=60), datetime.min.time(), UTC).replace(hour=9)
    assert rest("POST", "timesheet_submissions", SERVICE, {
        "workspace_id": squad["wid"], "user_id": squad["agent"], "status": "approved",
        "period_start": (old.date() - timedelta(days=1)).isoformat(),
        "period_end": (old.date() + timedelta(days=1)).isoformat()})[0] == 201
    assert _write(squad, str(uuid.uuid4()), old, old + timedelta(minutes=10)) == "approved_period"


def test_only_agents_are_written(squad):
    _, autre = squad["people"]["autre"]
    start = _now() - timedelta(hours=1)
    assert _write(squad, str(uuid.uuid4()), start, start + timedelta(minutes=10), agent=autre) == "not_agent"


def test_source_is_set_once_and_never_by_clients_as_agent(squad):
    autre_t, autre = squad["people"]["autre"]
    start = _now() - timedelta(hours=8)
    body = {"workspace_id": squad["wid"], "user_id": autre,
            "start_at": iso(start), "end_at": iso(start + timedelta(minutes=30))}
    status, err = rest("POST", "time_entries", autre_t, {**body, "id": str(uuid.uuid4()), "source": "agent"})
    assert status >= 400 and err["code"] == "42501"
    entry = str(uuid.uuid4())
    assert rest("POST", "time_entries", autre_t, {**body, "id": entry, "source": "activity"})[0] == 201
    status, err = rest("PATCH", f"time_entries?id=eq.{entry}", autre_t, {"source": "app"})
    assert status >= 400 and err["code"] == "42501"


def test_agent_follows_its_pilot_out_but_not_back(squad):
    owner_t, _ = squad["people"]["owner"]
    pilot2 = squad["people"]["pilote2"][1]
    agent2 = _create_agent(squad["wid"], pilot2)

    def agent_status():
        _, rows = rest("GET", f"workspace_members?user_id=eq.{agent2}&workspace_id=eq.{squad['wid']}&select=status",
                       SERVICE)
        return rows[0]["status"]

    member = squad["member_ids"]["pilote2"]
    assert rest("PATCH", f"workspace_members?id=eq.{member}", owner_t, {"status": "inactive"})[0] == 200
    assert agent_status() == "inactive"
    assert rest("PATCH", f"workspace_members?id=eq.{member}", owner_t, {"status": "active"})[0] == 200
    assert agent_status() == "inactive"


def test_admin_restores_a_removed_agent(squad):
    """Un agent retiré n'est pas recréé par un jeton : un admin le retrouve et le restaure (/api/agents)."""
    owner_t, _ = squad["people"]["owner"]
    pilot_t, pilot = signup("pilote3")
    member = _add_member(owner_t, squad["wid"], pilot, "pilote3")
    agent = _create_agent(squad["wid"], pilot)
    wid = squad["wid"]

    def removed(token: str = owner_t):
        return _call("GET", f"{SERVICES}/api/agents/removed?workspace_id={wid}", token)

    def restore(token: str = owner_t):
        return _call("POST", f"{SERVICES}/api/agents/{agent}/restore", token, {"workspace_id": wid})

    def scope() -> set[str]:
        _, rows = rest("GET", f"team_scope?manager_id=eq.{pilot}&select=user_id", pilot_t)
        return {r["user_id"] for r in rows}

    # Retiré depuis l'app (Équipe) : le pilote ne voit plus son temps, et le retrait est listé.
    assert rest("PATCH", f"workspace_members?user_id=eq.{agent}&workspace_id=eq.{wid}", owner_t,
                {"deleted_at": iso(_now())})[0] == 200
    assert agent not in scope()
    status, body = removed()
    assert status == 200 and [a["user_id"] for a in body["agents"]] == [agent]
    assert body["agents"][0]["pilot_name"] == "pilote3"
    assert removed(pilot_t)[0] == 403 and restore(pilot_t)[0] == 403, "admin seulement, pilote compris"

    status, body = restore()
    assert status == 200 and body == {"agent_id": agent, "status": "active"}
    assert agent in scope()
    assert removed()[1]["agents"] == [] and restore()[0] == 404, "déjà restauré"

    # Pilote retiré : son agent part avec lui, et n'est plus proposé à la restauration.
    assert rest("PATCH", f"workspace_members?id=eq.{member}", owner_t, {"deleted_at": iso(_now())})[0] == 200
    assert removed()[1]["agents"] == [] and restore()[0] == 404


def test_activity_rules_are_only_removed_by_their_owner(squad):
    pilote_t, pilote = squad["people"]["pilote"]
    project = str(uuid.uuid4())
    assert rest("POST", "projects", squad["people"]["owner"][0],
                {"id": project, "workspace_id": squad["wid"], "name": "Clockifai"})[0] == 201
    status, rows = rest("POST", "activity_rules", SERVICE, {
        "workspace_id": squad["wid"], "user_id": pilote, "match_kind": "repo",
        "pattern": "github.com/ysimonx/clockifai", "project_id": project})
    assert status == 201, rows
    rule = rows[0]["id"]
    _, rows = rest("GET", f"activity_rules?id=eq.{rule}&select=id", squad["people"]["autre"][0])
    assert rows == []
    status, err = rest("POST", "activity_rules", pilote_t, {
        "workspace_id": squad["wid"], "user_id": pilote, "match_kind": "repo", "pattern": "x", "project_id": project})
    assert status >= 400
    status, err = rest("PATCH", f"activity_rules?id=eq.{rule}", pilote_t, {"pattern": "github.com/autre/depot"})
    assert status >= 400 and err["code"] == "42501"
    status, rows = rest("PATCH", f"activity_rules?id=eq.{rule}", pilote_t, {"deleted_at": iso(_now())})
    assert status == 200 and len(rows) == 1


def test_code_tables_are_read_only_for_members(squad):
    pilote_t, _ = squad["people"]["pilote"]
    status, rows = rest("POST", "code_repositories", SERVICE, {
        "workspace_id": squad["wid"], "remote_key": "github.com/ysimonx/clockifai", "name": "clockifai"})
    assert status == 201, rows
    repo = rows[0]["id"]
    _, rows = rest("GET", f"code_repositories?id=eq.{repo}&select=name", pilote_t)
    assert rows == [{"name": "clockifai"}]
    status, _ = rest("POST", "code_repositories", pilote_t, {
        "workspace_id": squad["wid"], "remote_key": "local:essai", "name": "essai"})
    assert status >= 400


def test_purged_entry_keeps_its_commits(squad):
    start = _now() - timedelta(hours=10)
    entry = str(uuid.uuid4())
    assert _write(squad, entry, start, start + timedelta(minutes=10)) == "ok"
    _, rows = rest("GET", f"code_repositories?workspace_id=eq.{squad['wid']}&select=id", SERVICE)
    repo = rows[0]["id"] if rows else rest("POST", "code_repositories", SERVICE, {
        "workspace_id": squad["wid"], "remote_key": "local:purge", "name": "purge"})[1][0]["id"]
    status, rows = rest("POST", "code_commits", SERVICE, {
        "workspace_id": squad["wid"], "repository_id": repo, "sha": uuid.uuid4().hex, "time_entry_id": entry})
    assert status == 201, rows
    commit = rows[0]["id"]
    assert rest("DELETE", f"time_entries?id=eq.{entry}", SERVICE)[0] in (200, 204)
    _, rows = rest("GET", f"code_commits?id=eq.{commit}&select=time_entry_id", SERVICE)
    assert rows == [{"time_entry_id": None}]
