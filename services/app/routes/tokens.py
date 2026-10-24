"""Jetons d'API personnels (plan 10, D5) : un par poste, pour les hooks Claude Code, l'extension VSCode et le MCP.

  POST   /api/tokens          {workspace_id, name}  → {id, name, token, agent_id}  (jeton affiché une seule fois)
  GET    /api/tokens?workspace_id=…                 → ses jetons actifs (tous ceux du workspace pour un admin)
  DELETE /api/tokens/<id>?workspace_id=…            → révocation (le sien, ou n'importe lequel pour un admin)

Créer un jeton crée aussi, s'il manque, l'agent Claude du pilote dans ce workspace (D14).
"""

from __future__ import annotations

from flask import Blueprint, abort, g, jsonify, request

from ..auth import hash_token, new_api_token, require_user, require_workspace
from ..db import connection, fetch_all
from ..services.agents import ensure_agent

bp = Blueprint("tokens", __name__)

_ADMIN_ROLES = ("owner", "admin")


@bp.post("")
@require_user
@require_workspace()
def create_token():
    name = ((request.get_json(silent=True) or {}).get("name") or "Poste").strip()[:80]
    token = new_api_token()
    with connection() as conn:
        row = conn.execute(
            "insert into clockifai_private.api_tokens (workspace_id, user_id, name, token_hash) "
            "values (%s, %s, %s, %s) returning id",
            (g.workspace_id, g.user.id, name, hash_token(token)),
        ).fetchone()
        agent_id = ensure_agent(conn, g.workspace_id, g.user.id)
        conn.commit()
    return jsonify(id=str(row["id"]), name=name, token=token, agent_id=agent_id), 201


@bp.get("")
@require_user
@require_workspace()
def list_tokens():
    everyone = g.workspace_role in _ADMIN_ROLES
    rows = fetch_all(
        """
        select t.id, t.name, t.user_id, m.display_name as user_name, t.created_at, t.last_used_at
          from clockifai_private.api_tokens t
          left join public.workspace_members m on m.workspace_id = t.workspace_id and m.user_id = t.user_id
         where t.workspace_id = %(wid)s and t.revoked_at is null and (%(everyone)s or t.user_id = %(uid)s)
         order by t.created_at
        """,
        {"wid": g.workspace_id, "uid": g.user.id, "everyone": everyone},
    )
    return jsonify(tokens=[{
        **r, "id": str(r["id"]), "user_id": str(r["user_id"]),
        "created_at": r["created_at"].isoformat(),
        "last_used_at": r["last_used_at"].isoformat() if r["last_used_at"] else None,
    } for r in rows])


@bp.delete("/<token_id>")
@require_user
@require_workspace()
def revoke_token(token_id: str):
    everyone = g.workspace_role in _ADMIN_ROLES
    with connection() as conn:
        n = conn.execute(
            "update clockifai_private.api_tokens set revoked_at = now() "
            "where id = %(id)s and workspace_id = %(wid)s and revoked_at is null and (%(everyone)s or user_id = %(uid)s)",
            {"id": token_id, "wid": g.workspace_id, "uid": g.user.id, "everyone": everyone},
        ).rowcount
        conn.commit()
    if not n:
        abort(404, "token not found")
    return jsonify(revoked=True)
