"""Traces de la journée (plans/13-ux-moderne.md, lots 4 et 11) : ses commits, son agenda, contre la pile Docker."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from urllib.parse import quote

import pytest

from .test_backend import ENV, SERVICES, _call, iso, rest, signup

pytestmark = pytest.mark.skipif(__import__("os").environ.get("INTEGRATION") != "1", reason="INTEGRATION=1 requis")

SERVICE = ENV.get("SERVICE_ROLE_KEY", "")


def _workspace(token: str, uid: str) -> str:
    wid = str(uuid.uuid4())
    status, _ = _call("POST", f"{ENV.get('SUPABASE_URL', 'http://localhost:8000')}/rest/v1/workspaces", token,
                      {"id": wid, "name": "Atelier", "created_by": uid}, {"Prefer": "return=minimal"})
    assert status == 201
    return wid


def test_own_commits_only_and_calendar_settings():
    token, uid = signup("tracey")
    other_t, other = signup("autre")
    wid = _workspace(token, uid)
    status, rows = rest("POST", "code_repositories", SERVICE, {"workspace_id": wid, "remote_key": "local:site", "name": "site"})
    assert status == 201, rows
    repo = rows[0]["id"]
    at = datetime.now(UTC).replace(microsecond=0) - timedelta(hours=1)
    for author, subject in ((uid, "Formulaire de contact"), (other, "Pas le mien"), (None, "Auteur inconnu")):
        status, rows = rest("POST", "code_commits", SERVICE, {
            "workspace_id": wid, "repository_id": repo, "sha": uuid.uuid4().hex, "subject": subject,
            "author_user_id": author, "authored_at": iso(at)})
        assert status == 201, rows

    period = f"workspace_id={wid}&from={quote(iso(at - timedelta(hours=2)))}&to={quote(iso(at + timedelta(hours=2)))}"
    status, body = _call("GET", f"{SERVICES}/api/traces?{period}", token)
    assert status == 200, body
    assert body["calendar"] == "none" and body["events"] == []
    assert [(c["subject"], c["repository"]) for c in body["commits"]] == [("Formulaire de contact", "site")]

    # Un non-membre du workspace ne lit rien.
    assert _call("GET", f"{SERVICES}/api/traces?{period}", other_t)[0] == 403
    # Plus de huit jours : refusé.
    wide = f"workspace_id={wid}&from={quote(iso(at - timedelta(days=9)))}&to={quote(iso(at))}"
    assert _call("GET", f"{SERVICES}/api/traces?{wide}", token)[0] == 400

    # Agenda : https public seulement, l'adresse n'est jamais renvoyée.
    for url, error in (("http://calendar.example.com/x.ics", "https_required"),
                       ("https://localhost/x.ics", "host_not_allowed"),
                       ("https://192.168.0.84/x.ics", "host_not_allowed")):
        status, body = _call("PUT", f"{SERVICES}/api/traces/calendar", token, {"url": url})
        assert (status, body["error"]) == (400, error)
    status, body = _call("GET", f"{SERVICES}/api/traces/calendar", token)
    assert (status, body) == (200, {"configured": False, "host": None})
    assert _call("DELETE", f"{SERVICES}/api/traces/calendar", token)[0] == 204
