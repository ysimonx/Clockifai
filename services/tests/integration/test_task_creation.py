"""Création de tâches par les membres (réglage `task_creation`, migration 0010)."""

from __future__ import annotations

import uuid

import pytest

from .test_backend import rest, signup, upsert

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


def _add_member(owner_t: str, wid: str, uid: str, name: str, role: str = "member"):
    status, rows = rest("POST", "workspace_members", owner_t,
                        {"workspace_id": wid, "user_id": uid, "role": role, "display_name": name})
    assert status == 201, rows


def _project(token: str, wid: str, **extra) -> str:
    pid = str(uuid.uuid4())
    status, rows = rest("POST", "projects", token, {"id": pid, "workspace_id": wid, "name": "Chantier", **extra})
    assert status == 201, rows
    return pid


def _task(wid: str, pid: str, **extra) -> dict:
    return {"id": str(uuid.uuid4()), "workspace_id": wid, "project_id": pid, "name": "Pose", "status": "active", **extra}


@pytest.fixture(scope="module")
def ws():
    """« patronne » owner, « lea » simple membre, « max » manager ; un projet actif, un projet archivé."""
    owner_t, _ = signup("patronne")
    _, rows = rest("GET", "workspace_members?select=workspace_id", owner_t)
    wid = rows[0]["workspace_id"]
    lea_t, lea = signup("lea")
    max_t, max_id = signup("max")
    _add_member(owner_t, wid, lea, "lea")
    _add_member(owner_t, wid, max_id, "max", "manager")
    return {"wid": wid, "owner": owner_t, "lea": (lea_t, lea), "max": max_t, "max_id": max_id,
            "pid": _project(owner_t, wid), "archived": _project(owner_t, wid, archived=True)}


def test_everyone_is_the_default(ws):
    _, rows = rest("GET", f"workspaces?id=eq.{ws['wid']}&select=task_creation", ws["owner"])
    assert rows == [{"task_creation": "everyone"}]


def test_member_creates_task_like_the_connector(ws):
    lea_t, lea = ws["lea"]
    body = _task(ws["wid"], ws["pid"])
    assert upsert("tasks", lea_t, body)[0] == 201
    # Rejeu (réponse perdue côté client) : idempotent.
    assert upsert("tasks", lea_t, body)[0] == 200
    _, rows = rest("GET", f"tasks?id=eq.{body['id']}&select=created_by", ws["owner"])
    assert rows == [{"created_by": lea}]


def test_member_only_renames_own_task(ws):
    lea_t, _ = ws["lea"]
    mine = _task(ws["wid"], ws["pid"])
    assert upsert("tasks", lea_t, mine)[0] == 201
    status, rows = rest("PATCH", f"tasks?id=eq.{mine['id']}", lea_t, {"name": "Pose carrelage"})
    assert status == 200 and rows[0]["name"] == "Pose carrelage"
    for change in ({"status": "done"}, {"estimate_seconds": 3600}, {"deleted_at": "2026-01-01T00:00:00Z"}):
        status, err = rest("PATCH", f"tasks?id=eq.{mine['id']}", lea_t, change)
        assert status >= 400 and err["code"] == "42501", change

    # Tâche créée par un manager : invisible à la mise à jour pour un membre.
    theirs = _task(ws["wid"], ws["pid"])
    assert upsert("tasks", ws["max"], theirs)[0] == 201
    status, rows = rest("PATCH", f"tasks?id=eq.{theirs['id']}", lea_t, {"name": "Piratée"})
    assert status == 200 and rows == []


@pytest.mark.parametrize("case", ["estimate", "done", "archived_project", "foreign_project", "other_author"])
def test_member_creation_limits(ws, case):
    lea_t, _ = ws["lea"]
    wid, pid = ws["wid"], ws["pid"]
    if case == "estimate":
        body = _task(wid, pid, estimate_seconds=3600)
    elif case == "done":
        body = _task(wid, pid, status="done")
    elif case == "archived_project":
        body = _task(wid, ws["archived"])
    elif case == "foreign_project":
        other_t, _ = signup("voisin")
        _, rows = rest("GET", "workspace_members?select=workspace_id", other_t)
        body = _task(wid, _project(other_t, rows[0]["workspace_id"]))
    else:
        body = _task(wid, pid, created_by=ws["max_id"])
    status, err = upsert("tasks", lea_t, body)
    assert status >= 400 and err["code"] == "42501", err


def test_managers_only_setting(ws):
    lea_t, _ = ws["lea"]
    # Un membre ne change pas le réglage.
    status, rows = rest("PATCH", f"workspaces?id=eq.{ws['wid']}", lea_t, {"task_creation": "everyone"})
    assert status == 200 and rows == []
    assert rest("PATCH", f"workspaces?id=eq.{ws['wid']}", ws["owner"], {"task_creation": "managers"})[0] == 200
    try:
        status, err = upsert("tasks", lea_t, _task(ws["wid"], ws["pid"]))
        assert status >= 400 and err["code"] == "42501"
        assert upsert("tasks", ws["max"], _task(ws["wid"], ws["pid"]))[0] == 201
    finally:
        rest("PATCH", f"workspaces?id=eq.{ws['wid']}", ws["owner"], {"task_creation": "everyone"})
