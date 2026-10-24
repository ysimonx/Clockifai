"""Jetons personnels et entrées des agents Claude, de bout en bout (Flask + Postgres).

Plan : plans/10-suivi-claude-code.md (D2, D5, D7, D9, D10, D14, D16)
"""

from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import pytest

from .test_backend import ENV, SERVICES, _call, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

SERVICE = ENV.get("SERVICE_ROLE_KEY", "")


def api(method: str, path: str, token: str, body=None):
    return _call(method, f"{SERVICES}{path}", token, body)


def _add_member(owner_t: str, wid: str, uid: str, name: str) -> str:
    status, rows = rest("POST", "workspace_members", owner_t,
                        {"workspace_id": wid, "user_id": uid, "role": "member", "display_name": name})
    assert status == 201, rows
    return rows[0]["id"]


def _event(kind: str, at: datetime, session: str, **extra) -> dict:
    return {"id": str(uuid.uuid4()), "kind": kind, "occurred_at": iso(at), "session_id": session,
            "remote_key": "github.com/ysimonx/clockifai", "git_branch": "main", "cwd": "/Users/y/dev/clockifai",
            **extra}


def _agent_entries(agent: str) -> list[dict]:
    _, rows = rest("GET", f"time_entries?user_id=eq.{agent}&order=start_at"
                          "&select=id,start_at,end_at,source,project_id,task_id,description,billable,deleted_at", SERVICE)
    return rows


def _ago(minutes: float) -> datetime:
    return datetime.now(UTC).replace(microsecond=0) - timedelta(minutes=minutes)


@pytest.fixture(scope="module")
def team():
    owner_t, owner = signup("patron")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{owner}&select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    people = {"owner": (owner_t, owner)}
    members = {}
    for name in ("pilote", "autre"):
        t, uid = signup(name)
        people[name] = (t, uid)
        members[name] = _add_member(owner_t, wid, uid, name)
    pilote_t, _ = people["pilote"]
    status, created = api("POST", "/api/tokens", pilote_t, {"workspace_id": wid, "name": "MacBook"})
    assert status == 201, created
    project = str(uuid.uuid4())
    assert rest("POST", "projects", owner_t, {"id": project, "workspace_id": wid, "name": "Clockifai",
                                               "hourly_rate_cents": 9000})[0] == 201
    task = str(uuid.uuid4())
    assert rest("POST", "tasks", owner_t, {"id": task, "workspace_id": wid, "project_id": project,
                                            "name": "Plan 10"})[0] == 201
    return {"wid": wid, "people": people, "members": members, "token": created["token"],
            "agent": created["agent_id"], "project": project, "task": task}


def test_token_is_shown_once_and_creates_the_agent_once(team):
    pilote_t, pilote = team["people"]["pilote"]
    assert team["token"].startswith("clk_")
    status, again = api("POST", "/api/tokens", pilote_t, {"workspace_id": team["wid"], "name": "iMac"})
    assert status == 201 and again["agent_id"] == team["agent"]
    _, rows = rest("GET", f"workspace_members?workspace_id=eq.{team['wid']}&kind=eq.agent"
                          "&select=user_id,agent_owner_id,display_name,role", SERVICE)
    assert rows == [{"user_id": team["agent"], "agent_owner_id": pilote, "display_name": "Claude · pilote",
                     "role": "member"}]


def test_two_tokens_at_once_make_a_single_agent(team):
    t, uid = signup("presse")
    _add_member(team["people"]["owner"][0], team["wid"], uid, "presse")
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(lambda i: api("POST", "/api/tokens", t, {"workspace_id": team["wid"], "name": f"P{i}"}),
                                range(2)))
    assert [s for s, _ in results] == [201, 201]
    assert results[0][1]["agent_id"] == results[1][1]["agent_id"]


def test_each_member_sees_and_revokes_only_their_tokens(team):
    pilote_t, _ = team["people"]["pilote"]
    autre_t, _ = team["people"]["autre"]
    owner_t, _ = team["people"]["owner"]
    _, mine = api("GET", f"/api/tokens?workspace_id={team['wid']}", pilote_t)
    _, others = api("GET", f"/api/tokens?workspace_id={team['wid']}", autre_t)
    _, everyone = api("GET", f"/api/tokens?workspace_id={team['wid']}", owner_t)
    assert len(mine["tokens"]) >= 2 and others["tokens"] == []
    assert {t["id"] for t in mine["tokens"]} <= {t["id"] for t in everyone["tokens"]}
    victim = mine["tokens"][-1]["id"]
    assert api("DELETE", f"/api/tokens/{victim}?workspace_id={team['wid']}", autre_t)[0] == 404
    assert api("DELETE", f"/api/tokens/{victim}?workspace_id={team['wid']}", pilote_t)[0] == 200


def test_revoked_token_and_former_member_are_refused(team):
    pilote_t, _ = team["people"]["pilote"]
    _, created = api("POST", "/api/tokens", pilote_t, {"workspace_id": team["wid"], "name": "jetable"})
    assert api("GET", "/api/activity/projects", created["token"])[0] == 200
    api("DELETE", f"/api/tokens/{created['id']}?workspace_id={team['wid']}", pilote_t)
    assert api("GET", "/api/activity/projects", created["token"])[0] == 401

    t, uid = signup("partant")
    member = _add_member(team["people"]["owner"][0], team["wid"], uid, "partant")
    _, created = api("POST", "/api/tokens", t, {"workspace_id": team["wid"]})
    assert rest("PATCH", f"workspace_members?id=eq.{member}", team["people"]["owner"][0],
                {"deleted_at": iso(datetime.now(UTC))})[0] == 200
    assert api("GET", "/api/activity/projects", created["token"])[0] == 401


def test_events_are_validated_and_idempotent(team):
    session = str(uuid.uuid4())
    ok = _event("session_start", _ago(1), session)
    bad = {**_event("prompt", _ago(1), session), "kind": "clic"}
    status, res = api("POST", "/api/activity/events", team["token"], {"events": [ok, bad]})
    assert status == 202 and res["accepted"] == 1 and res["rejected"][0]["index"] == 1
    status, res = api("POST", "/api/activity/events", team["token"], {"events": [ok]})
    assert res == {"accepted": 0, "duplicates": 1, "rejected": []}


def test_a_session_becomes_an_entry_closed_at_its_last_activity(team):
    session = str(uuid.uuid4())
    events = [_event("session_start", _ago(40), session), _event("prompt", _ago(40), session),
              _event("agent_tool", _ago(37), session, duration_ms=60_000), _event("agent_stop", _ago(35), session)]
    assert api("POST", "/api/activity/events", team["token"], {"events": events})[0] == 202
    entries = [e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(40))[:16])]
    assert len(entries) == 1
    e = entries[0]
    assert e["source"] == "agent" and e["end_at"] is not None
    assert datetime.fromisoformat(e["end_at"]) == _ago(35) or abs(
        (datetime.fromisoformat(e["end_at"]) - _ago(35)).total_seconds()) < 5
    assert e["description"] == "clockifai (main)"


def test_session_task_rules_and_human_edits(team):
    pilote_t, _ = team["people"]["pilote"]
    session = str(uuid.uuid4())
    start = _ago(3)
    events = [_event("prompt", start, session), _event("agent_tool", _ago(2), session)]
    assert api("POST", "/api/activity/events", team["token"], {"events": events})[0] == 202
    entry = [e for e in _agent_entries(team["agent"]) if e["end_at"] is None and e["deleted_at"] is None][-1]
    assert entry["project_id"] is None

    # La session donne sa tâche (set_current_task, relayé par le hook) : projet et tâche posés.
    task_ev = _event("session_task", _ago(1), session, payload={"task_id": team["task"]})
    assert api("POST", "/api/activity/events", team["token"], {"events": [task_ev]})[0] == 202
    _, rows = rest("GET", f"time_entries?id=eq.{entry['id']}&select=project_id,task_id,billable", SERVICE)
    assert rows == [{"project_id": team["project"], "task_id": team["task"], "billable": True}]

    # Description corrigée par le pilote : plus jamais réécrite.
    assert rest("PATCH", f"time_entries?id=eq.{entry['id']}", pilote_t, {"description": "plan 10, étape 3"})[0] == 200
    more = [_event("agent_tool", _ago(0.5), session),
            _event("session_description", _ago(0.4), session, payload={"description": "Claude décrit"})]
    assert api("POST", "/api/activity/events", team["token"], {"events": more})[0] == 202
    _, rows = rest("GET", f"time_entries?id=eq.{entry['id']}&select=description,end_at", SERVICE)
    assert rows == [{"description": "plan 10, étape 3", "end_at": None}]


def test_rule_from_an_entry_reattributes_entries_without_project(team):
    session = str(uuid.uuid4())
    events = [_event("prompt", _ago(70), session, remote_key="github.com/ysimonx/fidwork"),
              _event("agent_stop", _ago(65), session, remote_key="github.com/ysimonx/fidwork")]
    assert api("POST", "/api/activity/events", team["token"], {"events": events})[0] == 202
    entry = next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(70))[:16]))
    assert entry["project_id"] is None
    status, rule = api("POST", "/api/activity/rules", team["token"],
                       {"time_entry_id": entry["id"], "project_id": team["project"]})
    assert status == 201 and rule["pattern"] == "github.com/ysimonx/fidwork" and rule["reattributed"] >= 1
    _, rows = rest("GET", f"time_entries?id=eq.{entry['id']}&select=project_id,hourly_rate_cents", SERVICE)
    assert rows == [{"project_id": team["project"], "hourly_rate_cents": 9000}]
    # La session suivante du même dépôt reçoit le projet d'elle-même.
    later = str(uuid.uuid4())
    assert api("POST", "/api/activity/events", team["token"], {"events": [
        _event("prompt", _ago(50), later, remote_key="github.com/ysimonx/fidwork"),
        _event("agent_stop", _ago(48), later, remote_key="github.com/ysimonx/fidwork")]})[0] == 202
    nxt = next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(50))[:16]))
    assert nxt["project_id"] == team["project"]


def test_deleted_entry_is_not_recreated(team):
    pilote_t, _ = team["people"]["pilote"]
    session = str(uuid.uuid4())
    assert api("POST", "/api/activity/events", team["token"], {"events": [
        _event("prompt", _ago(100), session), _event("agent_stop", _ago(95), session)]})[0] == 202
    entry = next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(100))[:16]))
    assert rest("PATCH", f"time_entries?id=eq.{entry['id']}", pilote_t, {"deleted_at": iso(datetime.now(UTC))})[0] == 200
    assert api("POST", "/api/activity/events", team["token"], {"events": [_event("agent_tool", _ago(97), session)]})[0] == 202
    same_span = [e for e in _agent_entries(team["agent"]) if e["deleted_at"] is None
                 and _ago(101) <= datetime.fromisoformat(e["start_at"]) <= _ago(94)]
    assert same_span == []


def test_agent_billing_never(team):
    owner_t, _ = team["people"]["owner"]
    assert rest("PATCH", f"workspaces?id=eq.{team['wid']}", owner_t, {"agent_billing": "never"})[0] == 200
    try:
        session = str(uuid.uuid4())
        assert api("POST", "/api/activity/events", team["token"], {"events": [
            _event("prompt", _ago(130), session, payload=None),
            _event("session_task", _ago(129), session, payload={"task_id": team["task"]}),
            _event("agent_stop", _ago(125), session)]})[0] == 202
        entry = next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(130))[:16]))
        assert entry["project_id"] == team["project"] and entry["billable"] is False
    finally:
        rest("PATCH", f"workspaces?id=eq.{team['wid']}", owner_t, {"agent_billing": "like_humans"})


def test_today_summary(team):
    status, today = api("GET", "/api/activity/today", team["token"])
    assert status == 200 and today["agent_id"] == team["agent"]
    assert today["claude_seconds"] > 0 and today["calendar_seconds"] >= today["claude_seconds"]
    assert any(r["repository"] == "clockifai" for r in today["running"])


def test_inactive_agent_records_nothing(team):
    owner_t, _ = team["people"]["owner"]
    agent_member = f"workspace_members?workspace_id=eq.{team['wid']}&user_id=eq.{team['agent']}"
    assert rest("PATCH", agent_member, owner_t, {"status": "inactive"})[0] == 200
    try:
        before = len(_agent_entries(team["agent"]))
        session = str(uuid.uuid4())
        status, res = api("POST", "/api/activity/events", team["token"], {"events": [
            _event("prompt", _ago(160), session), _event("agent_stop", _ago(155), session)]})
        assert status == 202 and res["accepted"] == 2
        assert len(_agent_entries(team["agent"])) == before
    finally:
        rest("PATCH", agent_member, owner_t, {"status": "active"})


def test_kiosk_lists_humans_only(team):
    owner_t, _ = team["people"]["owner"]
    status, device = _call("POST", f"{SERVICES}/api/kiosk/devices", owner_t, {"workspace_id": team["wid"]})
    assert status == 201
    status, state = _call("GET", f"{SERVICES}/api/kiosk/state", None, headers={"X-Kiosk-Token": device["token"]})
    assert status == 200
    assert team["agent"] not in {m["user_id"] for m in state["members"]}


def test_hook_script_end_to_end(team, tmp_path):
    """Le script du plugin, lancé comme Claude Code le lance, jusqu'à l'entrée de l'agent et son commit (§6.1)."""
    import json
    import os
    import subprocess
    from pathlib import Path

    script = Path(__file__).resolve().parents[3] / "integrations" / "claude-code" / "scripts" / "clockifai_hook.py"
    python = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else "python3"
    env = dict(os.environ, CLAUDE_PLUGIN_OPTION_URL=SERVICES, CLAUDE_PLUGIN_OPTION_TOKEN=team["token"],
               CLOCKIFAI_CACHE_DIR=str(tmp_path / "cache"), GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    repo = tmp_path / "plugin-e2e"
    repo.mkdir()
    for args in (["init", "-q", "-b", "main"], ["config", "user.email", "pilote@example.com"],
                 ["config", "user.name", "Pilote"], ["remote", "add", "origin", "git@github.com:acme/plugin-e2e.git"],
                 ["commit", "-q", "--allow-empty", "-m", "Départ"]):
        subprocess.run(["git", *args], cwd=repo, env=env, check=True, capture_output=True)
    session = str(uuid.uuid4())

    def hook(name, **extra):
        data = {"hook_event_name": name, "session_id": session, "cwd": str(repo), **extra}
        out = subprocess.run([python, str(script)], input=json.dumps(data), env=env, check=False, capture_output=True,
                             text=True, timeout=30)
        assert out.returncode == 0 and out.stdout == "", out.stderr

    hook("SessionStart", source="startup")
    hook("UserPromptSubmit", prompt="ajoute le plugin")
    subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "Ajout du plugin"], cwd=repo, env=env, check=True)
    hook("PostToolUse", tool_name="Bash", tool_input={"command": "git commit -m 'Ajout du plugin'"}, duration_ms=800)
    hook("Stop")
    assert not (tmp_path / "cache" / "hook.log").exists()

    [entry] = [e for e in _agent_entries(team["agent"]) if e["description"] == "Ajout du plugin"]
    assert entry["source"] == "agent" and entry["end_at"] is None and entry["deleted_at"] is None
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, env=env, check=True, capture_output=True,
                         text=True).stdout.strip()
    _, commits = rest("GET", f"code_commits?sha=eq.{sha}&select=session_id,time_entry_id,branch,subject", SERVICE)
    assert commits == [{"session_id": session, "time_entry_id": entry["id"], "branch": "main",
                        "subject": "Ajout du plugin"}]
    _, repos = rest("GET", f"code_repositories?workspace_id=eq.{team['wid']}&remote_key=eq.github.com/acme/plugin-e2e"
                           "&select=name", SERVICE)
    assert repos == [{"name": "plugin-e2e"}]
