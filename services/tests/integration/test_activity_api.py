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


def test_resumed_session_keeps_the_task_chosen_in_the_app(team):
    """Reprise après la pause de 10 minutes : la nouvelle entrée garde le projet et la tâche choisis dans l'app pour
    la précédente, tant que la branche ne change pas (D9). La tâche créée pour ce travail se prolonge."""
    pilote_t, _ = team["people"]["pilote"]
    session = str(uuid.uuid4())
    repo = {"remote_key": "github.com/ysimonx/reprise", "cwd": "/Users/y/dev/reprise"}

    def entry_at(minutes: int) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def send(*events) -> None:
        assert api("POST", "/api/activity/events", team["token"], {"events": list(events)})[0] == 202

    send(_event("prompt", _ago(76), session, **repo), _event("agent_stop", _ago(74), session, **repo))
    first = entry_at(76)
    assert first["project_id"] is None
    assert rest("PATCH", f"time_entries?id=eq.{first['id']}", pilote_t,
                {"project_id": team["project"], "task_id": team["task"]})[0] == 200

    send(_event("prompt", _ago(46), session, **repo), _event("agent_stop", _ago(44), session, **repo))
    resumed = entry_at(46)
    assert resumed["id"] != first["id"]
    assert (resumed["project_id"], resumed["task_id"]) == (team["project"], team["task"])

    other = {**repo, "git_branch": "autre-sujet"}
    send(_event("prompt", _ago(16), session, **other), _event("agent_stop", _ago(14), session, **other))
    assert entry_at(16)["task_id"] is None, "autre branche, autre sujet"


def test_claude_names_the_task_of_its_subject(team):
    """D18 : le nom donné par Claude (set_current_task, relayé par le hook) devient la tâche du projet de l'entrée,
    reprise ou créée ; un nouveau sujet ouvre une nouvelle entrée ; une tâche choisie à la main reste ; sans droit
    de création, le nom décrit l'entrée."""
    pilote_t, _ = team["people"]["pilote"]
    owner_t, _ = team["people"]["owner"]
    repo = {"remote_key": "github.com/ysimonx/taches", "cwd": "/Users/y/dev/taches"}
    assert api("POST", "/api/activity/rules", team["token"],
               {"remote_key": repo["remote_key"], "project_id": team["project"]})[0] == 201

    def at(minutes: float, kind: str, session: str, name: str | None = None) -> dict:
        extra = {"payload": {"task_name": name}} if name else {}
        return _event(kind, _ago(minutes), session, **repo, **extra)

    def send(*events) -> None:
        assert api("POST", "/api/activity/events", team["token"], {"events": list(events)})[0] == 202

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def tasks_named(name: str) -> list[dict]:
        _, rows = rest("GET", f"tasks?project_id=eq.{team['project']}&deleted_at=is.null&select=id,name", SERVICE)
        return [r for r in rows if r["name"].lower() == name.lower()]

    session = str(uuid.uuid4())
    send(at(88, "prompt", session), at(87.9, "session_task", session, "Export  PDF"), at(87, "agent_tool", session),
         at(85, "agent_stop", session))
    [export] = tasks_named("Export PDF")
    first = entry_at(88)
    assert (first["project_id"], first["task_id"]) == (team["project"], export["id"])
    assert first["description"] == "taches (main)", "la description reste celle du dépôt ou des commits"

    # Nouveau sujet, quatre minutes plus tard dans le même tour : l'entrée est coupée au prompt qui l'a amené.
    send(at(84, "prompt", session), at(83.9, "session_task", session, "Connexion mobile"),
         at(82, "agent_stop", session))
    [mobile] = tasks_named("Connexion mobile")
    assert entry_at(88)["end_at"].startswith(iso(_ago(84))[:16])
    second = entry_at(84)
    assert second["task_id"] == mobile["id"]

    # Tâche choisie à la main : le sujet nommé par Claude ne la remplace pas.
    assert rest("PATCH", f"time_entries?id=eq.{second['id']}", pilote_t, {"task_id": team["task"]})[0] == 200
    send(at(82.5, "agent_tool", session))
    assert entry_at(84)["task_id"] == team["task"]

    # Même sujet dans une autre session : la même tâche, sans doublon.
    other = str(uuid.uuid4())
    send(at(58, "prompt", other), at(57.9, "session_task", other, "export pdf"), at(56, "agent_stop", other))
    assert entry_at(58)["task_id"] == export["id"] and len(tasks_named("Export PDF")) == 1

    # Création de tâches réservée aux managers : pas de tâche, le nom décrit l'entrée.
    assert rest("PATCH", f"workspaces?id=eq.{team['wid']}", owner_t, {"task_creation": "managers"})[0] == 200
    try:
        third = str(uuid.uuid4())
        send(at(28, "prompt", third), at(27.9, "session_task", third, "Sujet réservé"), at(26, "agent_stop", third))
        entry = entry_at(28)
        assert (entry["task_id"], entry["description"]) == (None, "Sujet réservé") and not tasks_named("Sujet réservé")
    finally:
        rest("PATCH", f"workspaces?id=eq.{team['wid']}", owner_t, {"task_creation": "everyone"})


def test_a_refined_subject_renames_its_task_instead_of_adding_one(team):
    """Préciser = renommer (D18) : un nom plus précis, en début d'entrée, renomme la tâche créée pour elle ; si le
    sujet a déjà sa tâche, l'entrée y passe et la tâche vide disparaît ; une tâche renommée à la main ou utilisée
    par une autre entrée n'est jamais touchée."""
    pilote_t, _ = team["people"]["pilote"]
    owner_t, _ = team["people"]["owner"]
    repo = {"remote_key": "github.com/ysimonx/preciser", "cwd": "/Users/y/dev/preciser"}
    assert api("POST", "/api/activity/rules", team["token"],
               {"remote_key": repo["remote_key"], "project_id": team["project"]})[0] == 201

    def at(minutes: float, kind: str, session: str, name: str | None = None) -> dict:
        return _event(kind, _ago(minutes), session, **repo, **({"payload": {"task_name": name}} if name else {}))

    def send(*events) -> None:
        assert api("POST", "/api/activity/events", team["token"], {"events": list(events)})[0] == 202

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def task_ids(name: str) -> list[str]:
        _, rows = rest("GET", f"tasks?project_id=eq.{team['project']}&deleted_at=is.null&select=id,name", SERVICE)
        return [r["id"] for r in rows if r["name"].lower() == name.lower()]

    # Un premier nom vague, précisé une minute plus tard : une seule tâche, renommée.
    s1 = str(uuid.uuid4())
    send(at(110, "prompt", s1), at(109.9, "session_task", s1, "Exploration"), at(109.5, "agent_tool", s1))
    [exploration] = task_ids("Exploration")
    send(at(109, "prompt", s1), at(108.9, "session_task", s1, "Export Word"), at(108.5, "agent_stop", s1))
    assert task_ids("Exploration") == [] and task_ids("Export Word") == [exploration]
    assert entry_at(110)["task_id"] == exploration

    # Le sujet précisé a déjà sa tâche : l'entrée y passe, la tâche vide disparaît.
    s2 = str(uuid.uuid4())
    send(at(116, "prompt", s2), at(115.9, "session_task", s2, "Brouillon"), at(115.5, "agent_tool", s2))
    assert len(task_ids("Brouillon")) == 1
    send(at(115, "prompt", s2), at(114.9, "session_task", s2, "export word"), at(114.5, "agent_stop", s2))
    assert task_ids("Brouillon") == [] and entry_at(116)["task_id"] == exploration

    # Tâche renommée à la main : c'est un choix, l'entrée y reste.
    s3 = str(uuid.uuid4())
    send(at(122, "prompt", s3), at(121.9, "session_task", s3, "Maquette"), at(121.5, "agent_tool", s3))
    [maquette] = task_ids("Maquette")
    assert rest("PATCH", f"tasks?id=eq.{maquette}", owner_t, {"name": "Maquette de l'écran"})[0] == 200
    send(at(121, "prompt", s3), at(120.9, "session_task", s3, "Maquette mobile"), at(120.5, "agent_stop", s3))
    assert entry_at(122)["task_id"] == maquette and task_ids("Maquette mobile") == []

    # Tâche déjà utilisée par une autre entrée : jamais renommée, l'entrée passe à une nouvelle tâche.
    s4 = str(uuid.uuid4())
    send(at(134, "prompt", s4), at(133.9, "session_task", s4, "Partagée"), at(133.5, "agent_tool", s4))
    [partagee] = task_ids("Partagée")
    assert rest("PATCH", f"time_entries?id=eq.{entry_at(110)['id']}", pilote_t, {"task_id": partagee})[0] == 200
    send(at(133, "prompt", s4), at(132.9, "session_task", s4, "Partagée v2"), at(132.5, "agent_stop", s4))
    [v2] = task_ids("Partagée v2")
    assert task_ids("Partagée") == [partagee] and entry_at(134)["task_id"] == v2


def test_task_per_session_and_no_task_settings(team):
    """Réglage « Tâches de Claude » du pilote (profiles.claude_tasks, D18) : une tâche par session, toujours
    nouvelle (datée si le nom est pris) et renommée quand Claude précise ; « off » : aucune tâche."""
    pilote_t, pilote = team["people"]["pilote"]
    repo = {"remote_key": "github.com/ysimonx/session", "cwd": "/Users/y/dev/session"}
    assert api("POST", "/api/activity/rules", team["token"],
               {"remote_key": repo["remote_key"], "project_id": team["project"]})[0] == 201

    def at(minutes: float, kind: str, session: str, name: str | None = None) -> dict:
        return _event(kind, _ago(minutes), session, **repo, **({"payload": {"task_name": name}} if name else {}))

    def send(*events) -> None:
        assert api("POST", "/api/activity/events", team["token"], {"events": list(events)})[0] == 202

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def tasks_like(prefix: str) -> list[dict]:
        _, rows = rest("GET", f"tasks?project_id=eq.{team['project']}&deleted_at=is.null&select=id,name", SERVICE)
        return [r for r in rows if r["name"].lower().startswith(prefix.lower())]

    def mode(value: str) -> None:
        assert rest("PATCH", f"profiles?id=eq.{pilote}", pilote_t, {"claude_tasks": value})[0] == 200

    assert rest("POST", "tasks", team["people"]["owner"][0], {"workspace_id": team["wid"], "project_id": team["project"],
                                                              "name": "Rapport annuel"})[0] == 201
    mode("session")
    try:
        session = str(uuid.uuid4())
        send(at(200, "prompt", session), at(199.9, "session_task", session, "Rapport annuel"),
             at(199, "agent_tool", session), at(198, "agent_stop", session))
        dated = [t for t in tasks_like("Rapport annuel (")]
        assert len(dated) == 1, "le nom est pris : une nouvelle tâche, datée"
        task = dated[0]["id"]
        assert entry_at(200)["task_id"] == task

        # Claude précise : la tâche de la session est renommée, l'entrée n'est pas coupée.
        send(at(197, "prompt", session), at(196.9, "session_task", session, "Rapport annuel des ventes"),
             at(195, "agent_stop", session))
        assert [t["name"] for t in tasks_like("Rapport annuel des ventes")] == ["Rapport annuel des ventes"]
        first = entry_at(200)
        assert first["task_id"] == task and first["end_at"].startswith(iso(_ago(195))[:16])

        # Reprise après la pause : même tâche ; un nouveau recalcul ne crée rien.
        send(at(180, "prompt", session), at(179, "agent_stop", session))
        assert entry_at(180)["task_id"] == task
        send(at(179.5, "agent_tool", session))
        assert len(tasks_like("Rapport annuel")) == 2  # la tâche d'origine et celle de la session

        mode("off")
        off = str(uuid.uuid4())
        send(at(170, "prompt", off), at(169.9, "session_task", off, "Sans tâche voulue"), at(169, "agent_stop", off))
        entry = entry_at(170)
        assert entry["task_id"] is None and entry["description"] == "session (main)" and not tasks_like("Sans tâche")
    finally:
        mode("subject")


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


def test_agent_billable_project_overrides_workspace(team):
    """L'exception du projet (`agent_billable`) l'emporte sur le réglage du workspace, dans les deux sens (D16)."""
    owner_t, _ = team["people"]["owner"]

    def billable_of_session(at: int) -> bool:
        session = str(uuid.uuid4())
        assert api("POST", "/api/activity/events", team["token"], {"events": [
            _event("prompt", _ago(at), session, payload=None),
            _event("session_task", _ago(at - 1), session, payload={"task_id": team["task"]}),
            _event("agent_stop", _ago(at - 5), session)]})[0] == 202
        entry = next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(at))[:16]))
        assert entry["project_id"] == team["project"]
        return entry["billable"]

    def settings(agent_billing: str, agent_billable: bool | None) -> None:
        assert rest("PATCH", f"workspaces?id=eq.{team['wid']}", owner_t, {"agent_billing": agent_billing})[0] == 200
        assert rest("PATCH", f"projects?id=eq.{team['project']}", owner_t, {"agent_billable": agent_billable})[0] == 200

    try:
        settings("never", True)
        assert billable_of_session(220) is True, "le client accepte qu'on lui facture Claude"
        settings("like_humans", False)
        assert billable_of_session(250) is False, "le client refuse"
    finally:
        settings("like_humans", None)


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
