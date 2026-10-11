"""Déclenchement manuel des tâches planifiées (admin du workspace, ou service_role)."""

from flask import Blueprint, abort, g, jsonify

from ..auth import require_user, require_workspace
from ..jobs import tasks

bp = Blueprint("jobs", __name__)


@bp.post("/auto-stop")
@require_user
@require_workspace("admin")
def auto_stop():
    stopped = tasks.auto_stop_long_timers(workspace_id=g.workspace_id)
    return jsonify(stopped=stopped)


@bp.post("/purge-deleted")
@require_user
def purge_deleted():
    if g.user.role != "service_role":
        abort(403, "service role required")
    purged = tasks.purge_soft_deleted()
    return jsonify(purged=purged)
