"""Connexion d'un poste par lien (plans/21-installation-simple-du-plugin.md), de bout en bout."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import psycopg
import pytest

from .test_backend import ENV, SERVICES, _call, rest, signup

DSN = (f"postgresql://postgres.{ENV.get('POOLER_TENANT_ID', '')}:{ENV.get('POSTGRES_PASSWORD', '')}"
       f"@localhost:{ENV.get('POSTGRES_PORT', '5432')}/postgres")

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")


def api(method: str, path: str, token: str | None, body=None):
    return _call(method, f"{SERVICES}{path}", token, body)


def new_link(machine="MacBook Air"):
    status, link = api("POST", "/api/claude/link", None, {"machine": machine})
    assert status == 201 and link["expires_in"] == 600
    return link["url"].rsplit("/connect/", 1)[1], link["poll"]


def workspace_of(token, user):
    _, rows = rest("GET", f"workspace_members?user_id=eq.{user}&select=workspace_id", token)
    return rows[0]["workspace_id"]


def computers(token, wid):
    return api("GET", f"/api/tokens?workspace_id={wid}", token)[1]["tokens"]


def event(kind="prompt"):
    return {"event_id": str(uuid.uuid4()), "kind": kind, "occurred_at": datetime.now(UTC).isoformat(),
            "session_id": f"s-{uuid.uuid4()}"}


def test_link_from_session_to_token():
    token, user = signup("poste")
    wid = workspace_of(token, user)
    code, poll = new_link()

    assert api("POST", "/api/claude/link/poll", None, {"poll": poll}) == (200, {"status": "pending"})
    assert api("GET", f"/api/claude/link/{code}", None)[0] == 401, "valider demande un compte"
    assert api("GET", f"/api/claude/link/{code}", token) == (200, {"machine": "MacBook Air"})

    status, body = api("POST", f"/api/claude/link/{code}/approve", token, {"workspace_id": wid, "name": "  Mon\nMac "})
    assert (status, body) == (200, {"approved": True, "name": "Mon Mac"})
    assert api("GET", f"/api/claude/link/{code}", token)[0] == 404, "un lien ne sert qu'une fois"
    assert api("POST", f"/api/claude/link/{code}/approve", token, {"workspace_id": wid})[0] == 404
    assert not computers(token, wid), "le jeton naît au retrait"

    status, body = api("POST", "/api/claude/link/poll", None, {"poll": poll})
    assert status == 200 and body["status"] == "approved" and body["token"].startswith("clk_")
    assert api("POST", "/api/claude/link/poll", None, {"poll": poll})[0] == 404, "remis une seule fois"

    assert [c["name"] for c in computers(token, wid)] == ["Mon Mac"]
    assert api("POST", "/api/activity/events", body["token"], {"events": [event()]})[0] in (200, 202)
    agent = api("GET", f"/api/activity/today?workspace_id={wid}", token)[1]["agent_id"]
    assert agent, "le premier poste crée l'agent du pilote"


def test_name_defaults_to_the_machine_and_replaces_the_same_computer():
    token, user = signup("reinstalle")
    wid = workspace_of(token, user)
    tokens = []
    for _ in range(2):
        code, poll = new_link("Mac mini")
        assert api("POST", f"/api/claude/link/{code}/approve", token, {"workspace_id": wid})[1]["name"] == "Mac mini"
        tokens.append(api("POST", "/api/claude/link/poll", None, {"poll": poll})[1]["token"])
    assert [c["name"] for c in computers(token, wid)] == ["Mac mini"], "pas de doublon"
    assert api("POST", "/api/activity/events", tokens[0], {"events": [event()]})[0] == 401, "l'ancien jeton est révoqué"
    assert api("POST", "/api/activity/events", tokens[1], {"events": [event()]})[0] in (200, 202)


def test_approving_needs_a_member_of_the_workspace():
    owner, owner_id = signup("patron")
    stranger, _ = signup("inconnu")
    code, _ = new_link()
    wid = workspace_of(owner, owner_id)
    assert api("POST", f"/api/claude/link/{code}/approve", None, {"workspace_id": wid})[0] == 401
    assert api("POST", f"/api/claude/link/{code}/approve", stranger, {"workspace_id": wid})[0] == 403
    assert api("GET", f"/api/claude/link/{code}", owner)[0] == 200, "toujours en attente"


def test_expired_and_unknown_links():
    token, user = signup("retard")
    wid = workspace_of(token, user)
    code, poll = new_link()
    with psycopg.connect(DSN) as conn:
        conn.execute("update clockifai_private.device_links set expires_at = now() - interval '1 second' "
                     "where expires_at > now() - interval '1 day'")
    assert api("GET", f"/api/claude/link/{code}", token)[0] == 404
    assert api("POST", f"/api/claude/link/{code}/approve", token, {"workspace_id": wid})[0] == 404
    assert api("POST", "/api/claude/link/poll", None, {"poll": poll})[0] == 404
    assert api("POST", "/api/claude/link/poll", None, {"poll": "inconnu"})[0] == 404
    assert api("POST", "/api/claude/link/poll", None, {})[0] == 400


def test_public_creation_is_bounded():
    with psycopg.connect(DSN) as conn:
        conn.execute("delete from clockifai_private.device_links")
        conn.execute("insert into clockifai_private.device_links (code_hash, poll_hash, expires_at) "
                     "select 'c' || i, 'p' || i, now() + interval '1 minute' from generate_series(1, 500) i")
    try:
        assert api("POST", "/api/claude/link", None, {})[0] == 429
    finally:
        with psycopg.connect(DSN) as conn:
            conn.execute("delete from clockifai_private.device_links")
    assert api("POST", "/api/claude/link", None, {})[0] == 201
