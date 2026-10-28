from flask import Blueprint, current_app, jsonify

from ..db import fetch_one

bp = Blueprint("health", __name__)


@bp.get("/health")
def health():
    db_ok = True
    if current_app.config["DATABASE_URL"]:
        try:
            fetch_one("select 1 as ok")
        except Exception:  # noqa: BLE001
            db_ok = False
    status = 200 if db_ok else 503
    return jsonify(status="ok" if db_ok else "degraded", database=db_ok,
                   version=current_app.config["VERSION"] or None), status
