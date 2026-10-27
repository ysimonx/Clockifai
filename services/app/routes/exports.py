"""Exports de rapports : CSV, XLSX, PDF.

GET /api/exports/report?workspace_id=&from=YYYY-MM-DD&to=YYYY-MM-DD&format=csv|xlsx|pdf
    [&user_id=][&project_id=][&client_id=][&billable=true|false][&member_kind=human|agent]

Un membre n'exporte que ses propres entrées et celles de son agent Claude ; un chef d'équipe, aussi celles de son
périmètre ; manager+ peut exporter toute l'équipe. Jours et heures dans le fuseau de son profil.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime, tzinfo

from flask import Blueprint, Response, abort, g, request

from ..auth import MANAGER_ROLES, readable_user_ids, require_user, require_workspace
from ..db import connection
from ..services.exporters import ai_cost, build_pdf, build_xlsx, member_kind_label
from ..services.profiles import user_tz
from ..services.report_rows import detailed_rows

bp = Blueprint("exports", __name__)


def _parse_date(value: str | None, default: date) -> date:
    if not value:
        return default
    try:
        return date.fromisoformat(value)
    except ValueError:
        abort(400, f"invalid date: {value}")


@bp.get("/report")
@require_user
@require_workspace("member")
def export_report():
    fmt = request.args.get("format", "csv").lower()
    filters = {k: request.args.get(k) for k in ("user_id", "project_id", "client_id", "billable", "member_kind")}
    with connection() as conn:
        tz = user_tz(conn, g.user.id)
        today = datetime.now(tz).date()
        start = _parse_date(request.args.get("from"), today.replace(day=1))
        end = _parse_date(request.args.get("to"), today)
        # Un membre ne voit que ses entrées et celles de son agent ; un chef d'équipe, aussi celles de son périmètre.
        if g.workspace_role not in MANAGER_ROLES:
            allowed = readable_user_ids(conn, g.workspace_id, g.user.id)
            if filters["user_id"] and filters["user_id"] not in allowed:
                abort(403, "user outside your team")
            if not filters["user_id"]:
                filters["user_ids"] = allowed
        rows = detailed_rows(conn, g.workspace_id, start, end, tz, filters)
    filename = f"clockifai-{start.isoformat()}_{end.isoformat()}"

    if fmt == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf, delimiter=";")
        writer.writerow(["Utilisateur", "Email", "Type", "Client", "Projet", "Tâche", "Sous-tâche", "Description", "Tags",
                         "Début", "Fin", "Durée (h)", "Facturable", "Taux horaire", "Tokens IA",
                         "Coût IA estimé (USD)"])
        for r in rows:
            writer.writerow([
                r["user_name"], r["user_email"], member_kind_label(r), r["client_name"] or "", r["project_name"] or "",
                r["task_name"] or "", r.get("subtask_name") or "", r["description"], r["tags"],
                _fmt_dt(r["start_at"], tz), _fmt_dt(r["end_at"], tz),
                f"{(r['duration_seconds'] or 0) / 3600:.2f}".replace(".", ","),
                "oui" if r["billable"] else "non",
                f"{(r['hourly_rate_cents'] or 0) / 100:.2f}".replace(".", ",") if r["hourly_rate_cents"] else "",
                r["ai_tokens"] or "",
                f"{ai_cost(r):.4f}".replace(".", ",") if r["ai_cost_micros"] is not None else "",
            ])
        data = ("﻿" + buf.getvalue()).encode("utf-8")
        return _file_response(data, f"{filename}.csv", "text/csv; charset=utf-8")

    if fmt == "xlsx":
        data = build_xlsx(rows, start, end, tz=tz)
        return _file_response(data, f"{filename}.xlsx",
                              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    if fmt == "pdf":
        data = build_pdf(rows, start, end, tz=tz)
        return _file_response(data, f"{filename}.pdf", "application/pdf")

    abort(400, "format must be csv, xlsx or pdf")


def _fmt_dt(value: datetime | None, tz: tzinfo) -> str:
    return value.astimezone(tz).strftime("%Y-%m-%d %H:%M") if value else ""


def _file_response(data: bytes, filename: str, mimetype: str) -> Response:
    return Response(data, mimetype=mimetype,
                    headers={"Content-Disposition": f'attachment; filename="{filename}"'})
