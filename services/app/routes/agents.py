"""Agents Claude retirés (plan 10, D14) : un admin les retrouve et les restaure.

  GET  /api/agents/removed?workspace_id=…           → agents retirés dont le pilote est encore membre
  POST /api/agents/<agent_id>/restore {workspace_id} → {agent_id, status} : l'agent reprend son temps

Un agent retiré n'est jamais recréé par un nouveau jeton (D7.10), et les membres retirés ne descendent pas vers les
appareils (Sync Streams) : seul le serveur peut les lister. Restauré, l'agent suit le statut de son pilote.
"""

from __future__ import annotations

from flask import Blueprint, abort, g, jsonify

from ..auth import require_user, require_workspace
from ..db import connection, fetch_all

bp = Blueprint("agents", __name__)


@bp.get("/removed")
@require_user
@require_workspace("admin")
def removed_agents():
    # Pilote encore membre : un pilote retiré emporte son agent, rien à restaurer sans lui.
    rows = fetch_all(
        """
        select a.user_id, a.display_name, a.agent_owner_id, p.display_name as pilot_name, a.deleted_at
          from public.workspace_members a
          join public.workspace_members p on p.workspace_id = a.workspace_id and p.user_id = a.agent_owner_id
                                         and p.deleted_at is null
         where a.workspace_id = %(wid)s and a.kind = 'agent' and a.deleted_at is not null
         order by a.deleted_at desc
        """,
        {"wid": g.workspace_id},
    )
    return jsonify(agents=[{
        "user_id": str(r["user_id"]), "display_name": r["display_name"], "pilot_id": str(r["agent_owner_id"]),
        "pilot_name": r["pilot_name"], "removed_at": r["deleted_at"].isoformat(),
    } for r in rows])


@bp.post("/<agent_id>/restore")
@require_user
@require_workspace("admin")
def restore_agent(agent_id: str):
    with connection() as conn:
        row = conn.execute(
            """
            update public.workspace_members a set deleted_at = null, status = p.status
              from public.workspace_members p
             where p.workspace_id = a.workspace_id and p.user_id = a.agent_owner_id and p.deleted_at is null
               and a.workspace_id = %(wid)s and a.user_id = %(agent)s and a.kind = 'agent'
               and a.deleted_at is not null
            returning a.user_id, a.status
            """,
            {"wid": g.workspace_id, "agent": agent_id},
        ).fetchone()
        conn.commit()
    if row is None:
        abort(404, "removed agent not found")
    return jsonify(agent_id=str(row["user_id"]), status=row["status"])
