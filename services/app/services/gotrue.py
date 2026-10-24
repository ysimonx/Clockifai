"""Appels à l'API d'administration de GoTrue (Supabase Auth), avec la clé service_role."""

from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request

from flask import abort, current_app

log = logging.getLogger(__name__)


def gotrue_admin(path: str, body: dict | None = None, method: str = "POST") -> dict:
    """`path` relatif à /auth/v1/ (ex. `admin/users`). Une erreur de GoTrue devient un 502."""
    cfg = current_app.config
    key = cfg["SUPABASE_SERVICE_ROLE_KEY"]
    req = urllib.request.Request(
        f"{cfg['SUPABASE_URL']}/auth/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        log.error("GoTrue %s %s → %s %s", method, path, e.code, detail)
        abort(502, f"auth service error: {detail}")
