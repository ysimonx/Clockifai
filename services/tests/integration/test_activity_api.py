"""Jetons personnels et entrées des agents Claude, de bout en bout (Flask + Postgres).

Plan : plans/10-suivi-claude-code.md (D2, D5, D7, D9, D10, D14, D16, D17)
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
    assert res == {"accepted": 0, "duplicates": 1, "rejected": [], "ask_ticket": {}}


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
    assert first["description"] == "Export PDF", "le sujet décrit l'entrée, plutôt que le dépôt ou les commits"

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


def test_steps_become_subtasks_of_the_goal(team):
    """Plan 16 : l'objectif nommé par Claude est la tâche, chaque étape une sous-tâche ; une nouvelle étape coupe
    l'entrée sans ajouter de tâche ; une étape précisée juste après renomme sa sous-tâche ; le même objectif dans une
    autre session reprend la même tâche et ses sous-tâches ; sans étape (ancien plugin), l'entrée va sur la tâche."""
    repo = {"remote_key": "github.com/ysimonx/etapes", "cwd": "/Users/y/dev/etapes"}
    assert api("POST", "/api/activity/rules", team["token"],
               {"remote_key": repo["remote_key"], "project_id": team["project"]})[0] == 201
    goal_name = "Plan 16 · Sous-tâches"

    def at(minutes: float, kind: str, session: str, name: str | None = None, step: str | None = None) -> dict:
        payload = {"task_name": name, **({"step_name": step} if step else {})}
        return _event(kind, _ago(minutes), session, **repo, **({"payload": payload} if name else {}))

    def send(*events) -> None:
        assert api("POST", "/api/activity/events", team["token"], {"events": list(events)})[0] == 202

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def named(name: str, parent: str | None = None) -> list[dict]:
        _, rows = rest("GET", f"tasks?project_id=eq.{team['project']}&deleted_at=is.null&select=id,name,parent_id",
                       SERVICE)
        return [r for r in rows if r["name"].lower() == name.lower() and r["parent_id"] == parent]

    s1 = str(uuid.uuid4())
    send(at(154, "prompt", s1), at(153.9, "session_task", s1, goal_name, "Migration"), at(153, "agent_tool", s1),
         at(151, "agent_stop", s1))
    [goal] = named(goal_name)
    [migration] = named("Migration", goal["id"])
    assert entry_at(154)["task_id"] == migration["id"]

    # Étape suivante, quatre minutes plus tard : nouvelle entrée, nouvelle sous-tâche, la même tâche.
    send(at(150, "prompt", s1), at(149.9, "session_task", s1, goal_name, "Écran des projets"), at(148, "agent_stop", s1))
    [ecran] = named("Écran des projets", goal["id"])
    assert entry_at(154)["end_at"].startswith(iso(_ago(150))[:16])
    assert entry_at(150)["task_id"] == ecran["id"] and len(named(goal_name)) == 1

    # L'étape précisée juste après : sa sous-tâche, créée pour cette entrée, est renommée.
    send(at(149.5, "session_task", s1, goal_name, "Écran des projets et sous-tâches"))
    assert named("Écran des projets", goal["id"]) == []
    assert [t["id"] for t in named("Écran des projets et sous-tâches", goal["id"])] == [ecran["id"]]

    # Le même objectif dans une autre session : la même tâche, et l'étape déjà nommée reprend sa sous-tâche.
    s2 = str(uuid.uuid4())
    send(at(145, "prompt", s2), at(144.9, "session_task", s2, "plan 16 · sous-tâches", "migration"),
         at(143, "agent_stop", s2))
    assert entry_at(145)["task_id"] == migration["id"] and len(named(goal_name)) == 1

    # Ancien plugin, sans étape : l'entrée va sur la tâche de l'objectif.
    s3 = str(uuid.uuid4())
    send(at(140, "prompt", s3), at(139.9, "session_task", s3, goal_name), at(138, "agent_stop", s3))
    assert entry_at(140)["task_id"] == goal["id"]


def test_subtask_rules(team):
    """Migration 0021 : un seul niveau, le projet du parent ; supprimer une tâche emporte ses sous-tâches, la
    restaurer les rend."""
    owner_t, _ = team["people"]["owner"]
    status, [parent] = rest("POST", "tasks", owner_t, {"workspace_id": team["wid"], "project_id": team["project"],
                                                       "name": "Chantier"}, prefer="return=representation")
    assert status == 201
    status, [child] = rest("POST", "tasks", owner_t, {"workspace_id": team["wid"], "project_id": team["project"],
                                                      "name": "Niveau 3", "parent_id": parent["id"]},
                           prefer="return=representation")
    assert status == 201
    status, _ = rest("POST", "tasks", owner_t, {"workspace_id": team["wid"], "project_id": team["project"],
                                                "name": "Trop profond", "parent_id": child["id"]})
    assert status == 400, "un seul niveau de sous-tâches"
    status, _ = rest("PATCH", f"tasks?id=eq.{parent['id']}", owner_t, {"parent_id": team["task"]})
    assert status == 400, "une tâche qui a des sous-tâches n'en devient pas une"
    stamp = iso(_ago(0))
    assert rest("PATCH", f"tasks?id=eq.{parent['id']}", owner_t, {"deleted_at": stamp})[0] == 200
    _, [row] = rest("GET", f"tasks?id=eq.{child['id']}&select=deleted_at", SERVICE)
    assert row["deleted_at"] is not None, "la sous-tâche part avec sa tâche"
    assert rest("PATCH", f"tasks?id=eq.{parent['id']}", owner_t, {"deleted_at": None})[0] == 200
    _, [row] = rest("GET", f"tasks?id=eq.{child['id']}&select=deleted_at", SERVICE)
    assert row["deleted_at"] is None, "et revient avec elle"


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


def _subject_kit(team, repo_name: str):
    """Règle de rattachement d'un dépôt au projet de l'équipe, et petits outils pour envoyer une session nommée."""
    repo = {"remote_key": f"github.com/ysimonx/{repo_name}", "cwd": f"/Users/y/dev/{repo_name}"}
    assert api("POST", "/api/activity/rules", team["token"],
               {"remote_key": repo["remote_key"], "project_id": team["project"]})[0] == 201

    def at(minutes: float, kind: str, session: str, name: str | None = None, step: str | None = None) -> dict:
        payload = {"task_name": name, **({"step_name": step} if step else {})}
        return _event(kind, _ago(minutes), session, **repo, **({"payload": payload} if name else {}))

    def send(*events, token: str = team["token"]) -> None:
        assert api("POST", "/api/activity/events", token, {"events": list(events)})[0] == 202

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def tasks() -> list[dict]:
        _, rows = rest("GET", f"tasks?project_id=eq.{team['project']}&deleted_at=is.null&select=id,name,parent_id",
                       SERVICE)
        return rows

    return at, send, entry_at, tasks


def test_a_session_of_another_pilot_is_left_alone(team):
    """L'id d'une session se lit dans code_commits : posté par un autre membre, il ne touche ni aux entrées ni aux
    tâches de la session du pilote, et ne lui donne aucune entrée."""
    at, send, entry_at, tasks = _subject_kit(team, "intrus")
    session = str(uuid.uuid4())
    send(at(260, "prompt", session), at(259.9, "session_task", session, "Audit des droits"),
         at(259, "agent_stop", session))
    before = entry_at(260)

    autre_t, _ = team["people"]["autre"]
    status, created = api("POST", "/api/tokens", autre_t, {"workspace_id": team["wid"], "name": "Intrus"})
    assert status == 201, created
    send(at(258, "prompt", session), at(257.9, "session_task", session, "Piratage"), at(257, "agent_stop", session),
         token=created["token"])
    assert entry_at(260) == before
    assert _agent_entries(created["agent_id"]) == []
    names = {t["name"] for t in tasks()}
    assert "Audit des droits" in names and "Piratage" not in names


def test_task_per_session_with_steps(team):
    """Une tâche par session et des étapes : la tâche de la session reste la tâche racine, l'étape en est la
    sous-tâche (une sous-tâche prise pour la tâche de la session faisait échouer chaque recalcul)."""
    pilote_t, pilote = team["people"]["pilote"]
    at, send, entry_at, tasks = _subject_kit(team, "bilan")
    assert rest("PATCH", f"profiles?id=eq.{pilote}", pilote_t, {"claude_tasks": "session"})[0] == 200
    try:
        session = str(uuid.uuid4())
        send(at(234, "prompt", session), at(233.9, "session_task", session, "Bilan T4"), at(233, "agent_stop", session))
        send(at(232, "prompt", session), at(231.9, "session_task", session, "Bilan T4", "Collecte"),
             at(231, "agent_stop", session))
        send(at(230, "prompt", session), at(229.9, "session_task", session, "Bilan T4", "Analyse"),
             at(229, "agent_stop", session))
        entry = entry_at(234)
        assert entry["end_at"].startswith(iso(_ago(229))[:16]), "la session est encore recalculée"
        rows = tasks()
        [root] = [t for t in rows if t["name"] == "Bilan T4" and t["parent_id"] is None]
        [step] = [t for t in rows if t["id"] == entry["task_id"]]
        assert step["parent_id"] == root["id"] and step["name"] == "Analyse"
    finally:
        rest("PATCH", f"profiles?id=eq.{pilote}", pilote_t, {"claude_tasks": "subject"})


def test_a_subtask_renamed_by_hand_stays(team):
    owner_t, _ = team["people"]["owner"]
    at, send, entry_at, tasks = _subject_kit(team, "revue")
    session = str(uuid.uuid4())
    send(at(240, "prompt", session), at(239.9, "session_task", session, "Revue d'octobre", "Migration"),
         at(239, "agent_tool", session))
    step = entry_at(240)["task_id"]
    [goal] = [t["parent_id"] for t in tasks() if t["id"] == step]
    assert rest("PATCH", f"tasks?id=eq.{step}", owner_t, {"name": "Migration de la base"})[0] == 200
    send(at(238, "agent_tool", session), at(237.9, "session_task", session, "Revue d'octobre", "Migration"),
         at(237, "agent_stop", session))
    assert entry_at(240)["task_id"] == step
    assert [t["name"] for t in tasks() if t["parent_id"] == goal] == ["Migration de la base"]


def test_a_pilot_exports_the_time_of_their_agent(team):
    pilote_t, _ = team["people"]["pilote"]
    status, body = api("GET", f"/api/exports/report?workspace_id={team['wid']}&user_id={team['agent']}&format=csv",
                       pilote_t)
    assert status == 200, body


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


def test_a_deactivated_agent_stops_at_its_last_activity(team):
    """Désactivé, l'agent n'a plus d'entrée recalculée : celle en cours s'arrête à sa dernière activité (0023)."""
    owner_t, _ = team["people"]["owner"]
    t, uid = signup("pilote2")
    _add_member(owner_t, team["wid"], uid, "pilote2")
    status, created = api("POST", "/api/tokens", t, {"workspace_id": team["wid"], "name": "MacBook"})
    assert status == 201, created
    session = str(uuid.uuid4())
    assert api("POST", "/api/activity/events", created["token"], {"events": [
        _event("prompt", _ago(6), session), _event("agent_tool", _ago(4), session)]})[0] == 202
    [running] = [e for e in _agent_entries(created["agent_id"]) if e["end_at"] is None]
    assert rest("PATCH", f"workspace_members?workspace_id=eq.{team['wid']}&user_id=eq.{created['agent_id']}", owner_t,
                {"status": "inactive"})[0] == 200
    [stopped] = [e for e in _agent_entries(created["agent_id"]) if e["id"] == running["id"]]
    assert stopped["end_at"] is not None
    assert abs((datetime.fromisoformat(stopped["end_at"]) - _ago(4)).total_seconds()) < 5, "à sa dernière activité"


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


USAGE = {"model": "claude-opus-5-5", "effort": "xhigh", "speed": "standard", "requests": 3, "input_tokens": 10,
         "output_tokens": 2_000, "cache_write_5m_tokens": 1_000, "cache_write_1h_tokens": 20_000,
         "cache_read_tokens": 300_000}


def _usage(entry_id: str, token: str = SERVICE) -> list[dict]:
    _, rows = rest("GET", f"agent_usage?time_entry_id=eq.{entry_id}&deleted_at=is.null&order=model,effort"
                          "&select=model,effort,speed,requests,input_tokens,cache_read_tokens,cost_micros,user_id", token)
    return rows


def test_usage_is_summed_per_entry_and_priced(team):
    """Usage IA (D17) : rattaché à l'entrée qui couvre son heure, cumulé par modèle et effort, coût au tarif de l'API."""
    pilote_t, _ = team["people"]["pilote"]
    autre_t, _ = team["people"]["autre"]
    session = str(uuid.uuid4())
    once = _event("agent_usage", _ago(292), session, payload=USAGE)
    events = [
        _event("prompt", _ago(300), session), _event("agent_stop", _ago(290), session), once,
        _event("agent_usage", _ago(291), session, payload=dict(USAGE, model="claude-haiku-5-5", effort="medium")),
        _event("agent_usage", _ago(291), session, payload=dict(USAGE, model="claude-futur-9")),
        # Une pause de plus de 10 minutes : nouvelle entrée de la même session.
        _event("prompt", _ago(270), session), _event("agent_stop", _ago(265), session),
        _event("agent_usage", _ago(266), session, payload=dict(USAGE, speed="fast")),
        _event("agent_usage", _ago(266), session, payload=dict(USAGE, input_tokens=-1)),
    ]
    status, res = api("POST", "/api/activity/events", team["token"], {"events": events})
    assert status == 202 and [r["index"] for r in res["rejected"]] == [8]
    first, second = [e for e in _agent_entries(team["agent"])
                     if _ago(301) <= datetime.fromisoformat(e["start_at"]) <= _ago(264)]
    rows = _usage(first["id"])
    assert [(r["model"], r["effort"], r["requests"], r["cost_micros"]) for r in rows] == [
        ("claude-futur-9", "xhigh", 3, None),           # modèle sans tarif connu : tokens comptés, coût inconnu
        ("claude-haiku-5-5", "medium", 3, 8_126),       # 10×0,10 + 2000×0,50 + 1000×0,125 + 20000×0,20 + 300000×0,01
        ("claude-opus-5-5", "xhigh", 3, 265_040),       # 10×4 + 2000×20 + 1000×5 + 20000×8 + 300000×0,20
    ]
    assert {r["user_id"] for r in rows} == {team["agent"]}
    assert [(r["speed"], r["cost_micros"]) for r in _usage(second["id"])] == [("fast", 530_080)]

    # Le même événement renvoyé (file locale du poste) ne compte pas deux fois ; un nouvel usage s'ajoute.
    again = [once, _event("agent_usage", _ago(291), session, payload=dict(USAGE, requests=1, cache_read_tokens=0))]
    assert api("POST", "/api/activity/events", team["token"], {"events": again})[0] == 202
    opus = [r for r in _usage(first["id"]) if r["model"] == "claude-opus-5-5"]
    assert [(r["requests"], r["cache_read_tokens"]) for r in opus] == [(4, 300_000)]

    # Lecture : comme l'entrée, le pilote oui, un autre membre non.
    assert len(_usage(first["id"], pilote_t)) == 3
    assert _usage(first["id"], autre_t) == []
    status, _ = rest("PATCH", f"agent_usage?time_entry_id=eq.{first['id']}", pilote_t, {"requests": 0})
    assert status in (401, 403), "seul le serveur écrit l'usage"


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
    # La transcription que Claude Code écrit sur le poste : le hook n'en envoie que l'usage (D17).
    transcript = tmp_path / f"{session}.jsonl"
    line = {"type": "assistant", "timestamp": iso(datetime.now(UTC) - timedelta(seconds=5)), "effort": "xhigh",
            "message": {"id": "msg_1", "model": "claude-opus-5-5", "content": [{"type": "text", "text": "secret"}],
                        "usage": {"input_tokens": 10, "output_tokens": 2000, "cache_creation_input_tokens": 21000,
                                  "cache_creation": {"ephemeral_5m_input_tokens": 1000,
                                                     "ephemeral_1h_input_tokens": 20000},
                                  "cache_read_input_tokens": 300000, "speed": "standard"}}}
    transcript.write_text(json.dumps(line) + "\n" + json.dumps(line) + "\n")
    hook("Stop", transcript_path=str(transcript))
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
    assert [(u["requests"], u["cost_micros"]) for u in _usage(entry["id"])] == [(1, 265_040)]


def test_a_client_ticket_is_the_task_and_claude_s_subjects_its_subtasks(team):
    """Plan 19, lot 2 : le ticket donné par Claude (set_current_task) devient la tâche, collante pour la session, et
    chaque sujet une sous-tâche ; la clé de la branche vaut ticket dans un projet facturé par ticket ; un ticket qui a
    déjà sa tâche dans un autre projet y emmène la session ; au démarrage, le serveur fait demander le ticket."""
    owner_t, _ = team["people"]["owner"]
    wid = team["wid"]

    def project(name: str, remote_key: str) -> str:
        pid = str(uuid.uuid4())
        assert rest("POST", "projects", owner_t, {"id": pid, "workspace_id": wid, "name": name})[0] == 201
        assert api("POST", "/api/activity/rules", team["token"], {"remote_key": remote_key, "project_id": pid})[0] == 201
        return pid

    site = project("Site Acme", "github.com/acme/site")
    interne = project("Interne", "github.com/acme/interne")
    appli = str(uuid.uuid4())
    assert rest("POST", "projects", owner_t, {"id": appli, "workspace_id": wid, "name": "Appli Acme"})[0] == 201
    paiement = str(uuid.uuid4())
    assert rest("POST", "tasks", owner_t, {"id": paiement, "workspace_id": wid, "project_id": appli,
                                            "name": "ENG-900 · Paiement", "ticket_key": "ENG-900"})[0] == 201

    def at(minutes: float, kind: str, session: str, repo: str = "site", branch: str = "main", **payload) -> dict:
        extra = {"payload": payload} if payload else {}
        return _event(kind, _ago(minutes), session, remote_key=f"github.com/acme/{repo}", cwd=f"/Users/y/dev/{repo}",
                      git_branch=branch, **extra)

    def send(*events) -> dict:
        status, body = api("POST", "/api/activity/events", team["token"], {"events": list(events)})
        assert status == 202, body
        return body

    def entry_at(minutes: float) -> dict:
        return next(e for e in _agent_entries(team["agent"]) if e["start_at"].startswith(iso(_ago(minutes))[:16]))

    def task(tid: str) -> dict:
        _, rows = rest("GET", f"tasks?id=eq.{tid}&select=name,project_id,parent_id,ticket_key,ticket_url", SERVICE)
        return rows[0]

    def ticket_tasks(key: str) -> list[dict]:
        _, rows = rest("GET", f"tasks?workspace_id=eq.{wid}&ticket_key=eq.{key}&deleted_at=is.null&select=id,name",
                       SERVICE)
        return rows

    # Ticket donné dans le premier message : sa tâche, et le sujet en sous-tâche ; le sujet décrit l'entrée.
    url = "https://linear.app/acme/issue/ENG-501/formulaire"
    s1 = str(uuid.uuid4())
    send(at(480, "prompt", s1), at(479.9, "session_task", s1, task_name="Validation des champs", ticket=url,
                                   ticket_title="Formulaire de commande"),
         at(479, "agent_tool", s1), at(476, "agent_stop", s1))
    [ticket] = ticket_tasks("ENG-501")
    assert task(ticket["id"]) == {"name": "ENG-501 · Formulaire de commande", "project_id": site, "parent_id": None,
                                  "ticket_key": "ENG-501", "ticket_url": url}
    first = entry_at(480)
    assert first["project_id"] == site and first["description"] == "Validation des champs"
    assert task(first["task_id"])["parent_id"] == ticket["id"] and task(first["task_id"])["name"] == "Validation des champs"

    # Nouveau sujet sans ticket : le ticket reste, nouvelle sous-tâche.
    send(at(474, "prompt", s1), at(473.9, "session_task", s1, task_name="Tests du paiement"), at(472, "agent_stop", s1))
    second = entry_at(474)
    assert task(second["task_id"]) | {"project_id": None} == {"name": "Tests du paiement", "project_id": None,
                                                             "parent_id": ticket["id"], "ticket_key": None,
                                                             "ticket_url": None}

    # Une autre session, la clé seule : la même tâche, pas de doublon.
    s2 = str(uuid.uuid4())
    send(at(468, "prompt", s2), at(467.9, "session_task", s2, task_name="Relecture", ticket="eng-501"),
         at(466, "agent_stop", s2))
    assert task(entry_at(468)["task_id"])["parent_id"] == ticket["id"] and len(ticket_tasks("ENG-501")) == 1

    # Clé dans le nom de la branche, projet facturé par ticket : la tâche « ENG-502 », complétée par un titre ensuite.
    assert rest("PATCH", f"projects?id=eq.{site}", owner_t, {"billed_by_ticket": True})[0] == 200
    s3 = str(uuid.uuid4())
    send(at(462, "prompt", s3, branch="yannick/eng-502-menu"),
         at(461.9, "session_task", s3, branch="yannick/eng-502-menu", task_name="Menu mobile"),
         at(460, "agent_stop", s3, branch="yannick/eng-502-menu"))
    [menu] = ticket_tasks("ENG-502")
    assert menu["name"] == "ENG-502" and task(entry_at(462)["task_id"])["parent_id"] == menu["id"]
    send(at(459.9, "session_task", s3, branch="yannick/eng-502-menu", task_name="Menu mobile", ticket="ENG-502",
            ticket_title="Menu sur mobile"), at(459, "agent_stop", s3, branch="yannick/eng-502-menu"))
    assert task(menu["id"])["name"] == "ENG-502 · Menu sur mobile", "un titre complète le nom posé par le serveur"

    # Projet non facturé par ticket : « plan-77-lot-1 » n'est pas un ticket.
    s4 = str(uuid.uuid4())
    send(at(456, "prompt", s4, repo="interne", branch="plan-77-lot-1"),
         at(455.9, "session_task", s4, repo="interne", branch="plan-77-lot-1", task_name="Plan 77"),
         at(454, "agent_stop", s4, repo="interne", branch="plan-77-lot-1"))
    assert not ticket_tasks("PLAN-77") and task(entry_at(456)["task_id"]) | {"project_id": None} == {
        "name": "Plan 77", "project_id": None, "parent_id": None, "ticket_key": None, "ticket_url": None}
    assert entry_at(456)["project_id"] == interne

    # Ticket qui a déjà sa tâche dans un autre projet : la session y va.
    s5 = str(uuid.uuid4())
    send(at(450, "prompt", s5), at(449.9, "session_task", s5, task_name="Acompte", ticket="ENG-900"),
         at(448, "agent_stop", s5))
    moved = entry_at(450)
    assert moved["project_id"] == appli and task(moved["task_id"])["parent_id"] == paiement

    # Démarrage d'une session : le ticket est demandé dans un projet facturé par ticket, sans clé dans la branche,
    # et pas pour une session qui en a déjà un.
    s6 = str(uuid.uuid4())
    assert send(at(1, "session_start", s6, source="startup"))["ask_ticket"] == {s6: "Site Acme"}
    assert send(at(1, "session_start", str(uuid.uuid4()), branch="yannick/eng-503-x", source="startup"))[
        "ask_ticket"] == {}
    assert send(at(1, "session_start", str(uuid.uuid4()), repo="interne", source="startup"))["ask_ticket"] == {}
    assert send(at(1, "session_start", s1, source="resume"))["ask_ticket"] == {}
    assert send(at(1, "session_start", str(uuid.uuid4()), source="compact"))["ask_ticket"] == {}
    # Export (plan 19, lot 3) : colonne « Ticket », l'adresse du ticket de la tâche, sous-tâches comprises.
    pilote_t, _ = team["people"]["pilote"]
    status, body = api("GET", f"/api/exports/report?workspace_id={wid}&user_id={team['agent']}&format=csv", pilote_t)
    lines = body.decode("utf-8-sig").splitlines()
    header = lines[0].split(";")
    assert status == 200 and header[5:8] == ["Tâche", "Sous-tâche", "Ticket"]
    row = next(line.split(";") for line in lines[1:] if "Validation des champs" in line)
    assert row[5:8] == ["ENG-501 · Formulaire de commande", "Validation des champs", url]
