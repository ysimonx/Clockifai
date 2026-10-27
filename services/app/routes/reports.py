"""Rapports enregistrés et lien public (plans/18-rapports-presence-alertes-partage.md, lot 3).

GET    /api/reports/saved?workspace_id=      → rapports enregistrés du workspace (managers)
POST   /api/reports/saved                    → enregistre un rapport (managers)
PUT    /api/reports/saved/<id>               → le modifie ; `public` ouvre ou ferme le lien, `new_link` en change
DELETE /api/reports/saved/<id>?workspace_id= → le supprime (et son lien)
GET    /api/reports/public/<jeton>[?format=pdf] → page publique, sans compte

Un lien ne vaut que tant que son créateur est manager actif du workspace : il lit alors ce que ce manager lit.
"""

from __future__ import annotations

import json
from datetime import UTC, date, datetime

from flask import Blueprint, Response, abort, g, jsonify, request

from ..auth import MANAGER_ROLES, require_user, require_workspace
from ..db import connection
from ..services import shared_reports as sr
from ..services.profiles import zone
from ..services.report_rows import detailed_rows

bp = Blueprint("reports", __name__)

_COLUMNS = "id, name, period, date_from, date_to, filters, detailed, show_amounts, rounding, public_token, created_at"


def _item(row: dict) -> dict:
    return {
        "id": str(row["id"]), "name": row["name"], "period": row["period"],
        "date_from": row["date_from"].isoformat() if row["date_from"] else None,
        "date_to": row["date_to"].isoformat() if row["date_to"] else None,
        "filters": row["filters"], "detailed": row["detailed"], "show_amounts": row["show_amounts"],
        "rounding": row["rounding"],
        # Chemin seulement : l'app le complète avec l'adresse de l'instance qu'elle connaît.
        "public_path": f"/api/reports/public/{row['public_token']}" if row["public_token"] else None,
        "created_at": row["created_at"].isoformat(),
    }


def _fields(body: dict, current: dict | None = None) -> dict:
    """Champs modifiables validés ; ceux qui manquent gardent leur valeur ([current]) ou leur défaut."""
    cur = current or {"name": None, "period": "this_month", "date_from": None, "date_to": None, "filters": {},
                      "detailed": False, "show_amounts": True, "rounding": False}
    out = {}
    name = str(body.get("name", cur["name"]) or "").strip()
    if not 1 <= len(name) <= 120:
        abort(400, "name is required (120 characters at most)")
    out["name"] = name
    out["period"] = body.get("period", cur["period"])
    if out["period"] not in sr.PERIODS:
        abort(400, "invalid period")
    for key in ("date_from", "date_to"):
        value = body.get(key, cur[key])
        try:
            out[key] = date.fromisoformat(value) if isinstance(value, str) else value
        except ValueError:
            abort(400, f"invalid {key}")
    if out["period"] == "custom" and not (out["date_from"] and out["date_to"] and out["date_from"] <= out["date_to"]):
        abort(400, "a custom period needs date_from <= date_to")
    filters = sr.clean_filters(body.get("filters", cur["filters"]))
    if filters is None:
        abort(400, "invalid filters")
    out["filters"] = filters
    for key in ("detailed", "show_amounts", "rounding"):
        value = body.get(key, cur[key])
        if not isinstance(value, bool):
            abort(400, f"{key} must be a boolean")
        out[key] = value
    return out


@bp.get("/saved")
@require_user
@require_workspace("manager")
def list_saved():
    with connection() as conn:
        rows = conn.execute(
            f"select {_COLUMNS} from clockifai_private.saved_reports "
            "where workspace_id = %s and deleted_at is null order by name",
            (g.workspace_id,),
        ).fetchall()
    return jsonify(reports=[_item(r) for r in rows])


@bp.post("/saved")
@require_user
@require_workspace("manager")
def create_saved():
    body = request.get_json(silent=True) or {}
    f = _fields(body)
    token = sr.new_token() if body.get("public") is True else None
    with connection() as conn:
        row = conn.execute(
            f"""
            insert into clockifai_private.saved_reports
              (workspace_id, created_by, name, period, date_from, date_to, filters, detailed, show_amounts, rounding,
               public_token)
            values (%s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s, %s)
            returning {_COLUMNS}
            """,
            (g.workspace_id, g.user.id, f["name"], f["period"], f["date_from"], f["date_to"], json.dumps(f["filters"]),
             f["detailed"], f["show_amounts"], f["rounding"], token),
        ).fetchone()
        conn.commit()
    return jsonify(_item(row)), 201


@bp.put("/saved/<uuid:report_id>")
@require_user
@require_workspace("manager")
def update_saved(report_id):
    body = request.get_json(silent=True) or {}
    with connection() as conn:
        cur = conn.execute(
            f"select {_COLUMNS} from clockifai_private.saved_reports "
            "where id = %s and workspace_id = %s and deleted_at is null for update",
            (str(report_id), g.workspace_id),
        ).fetchone()
        if cur is None:
            abort(404)
        f = _fields(body, cur)
        token = cur["public_token"]
        if body.get("public") is False:
            token = None
        elif (body.get("public") is True and token is None) or body.get("new_link") is True:
            token = sr.new_token()
        row = conn.execute(
            f"""
            update clockifai_private.saved_reports
               set name = %s, period = %s, date_from = %s, date_to = %s, filters = %s::jsonb, detailed = %s,
                   show_amounts = %s, rounding = %s, public_token = %s, updated_at = now()
             where id = %s
            returning {_COLUMNS}
            """,
            (f["name"], f["period"], f["date_from"], f["date_to"], json.dumps(f["filters"]), f["detailed"],
             f["show_amounts"], f["rounding"], token, str(report_id)),
        ).fetchone()
        conn.commit()
    return jsonify(_item(row))


@bp.delete("/saved/<uuid:report_id>")
@require_user
@require_workspace("manager")
def delete_saved(report_id):
    with connection() as conn:
        done = conn.execute(
            "update clockifai_private.saved_reports set deleted_at = now(), public_token = null "
            "where id = %s and workspace_id = %s and deleted_at is null",
            (str(report_id), g.workspace_id),
        ).rowcount
        conn.commit()
    if not done:
        abort(404)
    return "", 204


@bp.get("/public/<token>")
def public_report(token: str):
    if not 20 <= len(token) <= 100:
        abort(404)
    with connection() as conn:
        rep = conn.execute(
            """
            select r.*, w.name as workspace, w.currency, w.week_start, w.rounding_minutes,
                   pr.timezone, coalesce(pr.locale, 'fr') as locale
              from clockifai_private.saved_reports r
              join public.workspaces w on w.id = r.workspace_id and w.deleted_at is null
              join public.workspace_members m on m.workspace_id = r.workspace_id and m.user_id = r.created_by
                   and m.status = 'active' and m.deleted_at is null and m.role = any(%s)
              left join public.profiles pr on pr.id = r.created_by
             where r.public_token = %s and r.deleted_at is null
            """,
            (list(MANAGER_ROLES), token),
        ).fetchone()
        if rep is None:
            abort(404)
        tz = zone(rep["timezone"])
        now = datetime.now(UTC)
        start, end = sr.period_range(rep["period"], now.astimezone(tz).date(), rep["week_start"],
                                     rep["date_from"], rep["date_to"])
        rows = detailed_rows(conn, str(rep["workspace_id"]), start, end, tz, dict(rep["filters"]))
    if rep["rounding"]:
        for r in rows:
            r["duration_seconds"] = sr.round_seconds(r["duration_seconds"] or 0, rep["rounding_minutes"])
    pdf = request.args.get("format") == "pdf"
    html = sr.render(rep, rows, start, end, workspace=rep["workspace"], currency=rep["currency"], lang=rep["locale"],
                     tz=tz, rounding_minutes=rep["rounding_minutes"], now=now, pdf=pdf)
    headers = {"X-Robots-Tag": "noindex, nofollow", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer"}
    if pdf:
        from weasyprint import HTML  # import tardif : lib lourde

        filename = f"clockifai-{start.isoformat()}_{end.isoformat()}.pdf"
        return Response(HTML(string=html).write_pdf(), mimetype="application/pdf",
                        headers={**headers, "Content-Disposition": f'inline; filename="{filename}"'})
    # Page sans script ni ressource externe.
    headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
    return Response(html, mimetype="text/html", headers=headers)
