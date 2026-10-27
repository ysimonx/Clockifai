"""Vérification du JWT Supabase et contrôle d'appartenance au workspace.

Le client Flutter envoie `Authorization: Bearer <access_token Supabase>`.
On vérifie la signature (HS256 secret partagé, ou JWKS si clés asymétriques),
puis l'appartenance active au workspace visé via workspace_members.

Les hooks Claude Code, l'extension VSCode et le MCP envoient à la place un jeton personnel
`Authorization: Bearer clk_…` (plan 10, D5), lié à un utilisateur et un workspace.
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from functools import wraps

import jwt
from flask import abort, current_app, g, request

from .db import connection, fetch_one

API_TOKEN_PREFIX = "clk_"

MANAGER_ROLES = ("owner", "admin", "manager")
ADMIN_ROLES = ("owner", "admin")


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


def readable_user_ids(conn, workspace_id: str, user_id: str) -> list[str]:
    """Personnes dont un membre (hors managers) lit le temps, comme la RLS : lui-même, son équipe s'il est chef
    d'équipe (team_scope) et son agent Claude (pilots_agent)."""
    rows = conn.execute(
        """
        select user_id::text as id from public.team_scope where workspace_id = %(wid)s and manager_id = %(uid)s
        union
        select user_id::text from public.workspace_members
         where workspace_id = %(wid)s and kind = 'agent' and agent_owner_id = %(uid)s and deleted_at is null
        """,
        {"wid": workspace_id, "uid": user_id},
    ).fetchall()
    return sorted({user_id, *(r["id"] for r in rows)})


def new_api_token() -> str:
    """`clk_` + 32 caractères hexadécimaux : le préfixe permet de repérer un jeton qui fuit dans un dépôt."""
    return API_TOKEN_PREFIX + secrets.token_hex(16)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def require_user_or_token(fn):
    """JWT Supabase (l'app) ou jeton personnel `clk_…` (hooks, extension, MCP). Expose g.user et g.workspace_id.

    Avec un JWT, le workspace vient du paramètre `workspace_id` (query ou JSON), dont l'utilisateur doit être
    membre actif. Avec un jeton, c'est celui du jeton, et son propriétaire doit en être encore membre actif."""

    @wraps(fn)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            abort(401, "missing bearer token")
        token = header[7:].strip()
        g.token_id = None
        if token.startswith(API_TOKEN_PREFIX):
            with connection() as conn:
                row = conn.execute(
                    """
                    update clockifai_private.api_tokens t set last_used_at = now()
                      from public.workspace_members m
                     where t.token_hash = %s and t.revoked_at is null
                       and m.workspace_id = t.workspace_id and m.user_id = t.user_id
                       and m.status = 'active' and m.deleted_at is null and m.kind = 'human'
                    returning t.id, t.user_id, t.workspace_id, m.role
                    """,
                    (hash_token(token),),
                ).fetchone()
                conn.commit()
            if row is None:
                abort(401, "invalid or revoked token")
            g.user = CurrentUser(id=str(row["user_id"]), email=None, role="api_token")
            g.workspace_id, g.workspace_role, g.token_id = str(row["workspace_id"]), row["role"], str(row["id"])
            return fn(*args, **kwargs)
        try:
            claims = decode_token(token)
        except jwt.PyJWTError as exc:
            abort(401, f"invalid token: {exc}")
        g.user = CurrentUser(id=claims["sub"], email=claims.get("email"), role=claims.get("role", "authenticated"))
        wid = request.args.get("workspace_id") or (request.get_json(silent=True) or {}).get("workspace_id")
        if not wid:
            abort(400, "workspace_id is required")
        role = workspace_role(wid, g.user.id)
        if role is None:
            abort(403, "not a member of this workspace")
        g.workspace_id, g.workspace_role = wid, role
        return fn(*args, **kwargs)

    return wrapper


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
            if min_role == "manager" and role not in MANAGER_ROLES:
                abort(403, "manager role required")
            if min_role == "admin" and role not in ADMIN_ROLES:
                abort(403, "admin role required")
            g.workspace_id = wid
            g.workspace_role = role
            return fn(*args, **kwargs)

        return wrapper

    return decorator
