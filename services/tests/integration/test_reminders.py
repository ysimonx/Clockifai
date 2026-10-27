"""Relances de feuille de temps (plans/13-ux-moderne.md, lot 8) : droits par la RLS, contre la pile Docker."""

from __future__ import annotations

import uuid

import pytest

from .test_backend import ENV, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


@pytest.fixture(scope="module")
def crew():
    boss_t, boss = signup("patronne")
    _, rows = rest("GET", f"workspace_members?user_id=eq.{boss}&select=workspace_id", boss_t)
    wid = rows[0]["workspace_id"]
    people = {}
    for name in ("leo", "mia"):
        t, uid = signup(name)
        assert rest("POST", "workspace_members", boss_t,
                    {"workspace_id": wid, "user_id": uid, "role": "member", "display_name": name})[0] == 201
        people[name] = (t, uid)
    return {"wid": wid, "boss": (boss_t, boss), **people}


def remind(token: str, wid: str, uid: str, **extra):
    rid = str(uuid.uuid4())
    status, body = rest("POST", "reminders", token,
                        {"id": rid, "workspace_id": wid, "user_id": uid, "period_start": "2026-10-19", **extra})
    return status, rid, body


def test_reminder_rights(crew):
    wid = crew["wid"]
    boss_t, boss = crew["boss"]
    leo_t, leo = crew["leo"]
    mia_t, mia = crew["mia"]

    # Un manager relance ; l'auteur est posé par le serveur, quoi que dise le client.
    status, rid, body = remind(boss_t, wid, leo, created_by=mia)
    assert status == 201, body
    assert body[0]["created_by"] == boss

    # Un membre ne relance personne, ni lui-même.
    assert remind(mia_t, wid, leo)[0] in (401, 403)
    assert remind(leo_t, wid, leo)[0] in (401, 403)

    # La personne relancée la voit et la marque vue ; une autre non.
    _, rows = rest("GET", f"reminders?id=eq.{rid}&select=id", leo_t)
    assert rows == [{"id": rid}]
    _, rows = rest("GET", f"reminders?id=eq.{rid}&select=id", mia_t)
    assert rows == []
    status, rows = rest("PATCH", f"reminders?id=eq.{rid}", leo_t, {"seen_at": "2026-10-27T08:00:00Z"})
    assert status == 200 and rows[0]["seen_at"] is not None
    # Ni la semaine ni la personne ne changent.
    status, _ = rest("PATCH", f"reminders?id=eq.{rid}", leo_t, {"period_start": "2026-10-12"})
    assert status >= 400
    assert ENV  # pile configurée
