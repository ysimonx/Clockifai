"""Vérification du JWT Supabase et contrôle d'appartenance au workspace.

Le client Flutter envoie `Authorization: Bearer <access_token Supabase>`.
On vérifie la signature (HS256 secret partagé, ou JWKS si clés asymétriques),
puis l'appartenance active au workspace visé via workspace_members.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import wraps

import jwt
from flask import abort, current_app, g, request

from .db import fetch_all, fetch_one

_MANAGER_ROLES = ("owner", "admin", "manager")
_ADMIN_ROLES = ("owner", "admin")


@dataclass(frozen=True)
class CurrentUser:
    id: str
    email: str | None
    role: str  # rôle Supabase (authenticated / service_role)


def decode_token(token: str) -> dict:
    secret = current_app.config["SUPABASE_JWT_SECRET"]
    options = {"require": ["exp", "sub"]}
    if secret:
        return jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated", options=options)
    jwks_client = jwt.PyJWKClient(current_app.config["SUPABASE_JWKS_URL"])
    key = jwks_client.get_signing_key_from_jwt(token).key
    return jwt.decode(token, key, algorithms=["ES256", "RS256", "EdDSA"], audience="authenticated", options=options)


def require_user(fn):
    """Décorateur : exige un JWT Supabase valide ; expose g.user."""

    @wraps(fn)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            abort(401, "missing bearer token")
        try:
            claims = decode_token(header[7:].strip())
        except jwt.PyJWTError as exc:
            abort(401, f"invalid token: {exc}")
        g.user = CurrentUser(id=claims["sub"], email=claims.get("email"), role=claims.get("role", "authenticated"))
        return fn(*args, **kwargs)

    return wrapper


def workspace_role(workspace_id: str, user_id: str) -> str | None:
    row = fetch_one(
        """
        select role from public.workspace_members
         where workspace_id = %(wid)s and user_id = %(uid)s and status = 'active' and deleted_at is null
        """,
        {"wid": workspace_id, "uid": user_id},
    )
    return row["role"] if row else None


def managed_user_ids(workspace_id: str, user_id: str) -> list[str]:
    """Collaborateurs encadrés par un chef d'équipe (périmètre calculé par la base, cf. team_scope)."""
    rows = fetch_all(
        "select user_id::text as user_id from public.team_scope where workspace_id = %(wid)s and manager_id = %(uid)s",
        {"wid": workspace_id, "uid": user_id},
    )
    return [r["user_id"] for r in rows]


def require_workspace(min_role: str = "member"):
    """Vérifie que g.user appartient au workspace passé en paramètre `workspace_id` (query ou JSON)."""

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            wid = request.args.get("workspace_id") or (request.get_json(silent=True) or {}).get("workspace_id")
            if not wid:
                abort(400, "workspace_id is required")
            role = workspace_role(wid, g.user.id)
            if role is None:
                abort(403, "not a member of this workspace")
            if min_role == "manager" and role not in _MANAGER_ROLES:
                abort(403, "manager role required")
            if min_role == "admin" and role not in _ADMIN_ROLES:
                abort(403, "admin role required")
            g.workspace_id = wid
            g.workspace_role = role
            return fn(*args, **kwargs)

        return wrapper

    return decorator
