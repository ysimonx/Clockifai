"""Exports de rapports : CSV, XLSX, PDF.

GET /api/exports/report?workspace_id=&from=YYYY-MM-DD&to=YYYY-MM-DD&format=csv|xlsx|pdf
    [&user_id=][&project_id=][&client_id=][&billable=true|false]

Un membre n'exporte que ses propres entrées ; un chef d'équipe, les siennes et celles de son
périmètre ; manager+ peut exporter toute l'équipe.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime, timedelta

from flask import Blueprint, Response, abort, g, request

from ..auth import managed_user_ids, require_user, require_workspace
from ..db import fetch_all
from ..services.exporters import build_pdf, build_xlsx

bp = Blueprint("exports", __name__)

_MANAGER_ROLES = ("owner", "admin", "manager")


def _parse_date(value: str | None, default: date) -> date:
    if not value:
        return default
    try:
        return date.fromisoformat(value)
    except ValueError:
        abort(400, f"invalid date: {value}")


def _detailed_rows(workspace_id: str, start: date, end: date, filters: dict) -> list[dict]:
    sql = """
        select te.id, te.start_at, te.end_at, te.duration_seconds, te.description, te.billable,
               te.hourly_rate_cents, wm.display_name as user_name, wm.email as user_email,
               p.name as project_name, c.name as client_name, t.name as task_name,
               coalesce(string_agg(tg.name, ', ' order by tg.name), '') as tags
          from public.time_entries te
          left join public.workspace_members wm on wm.workspace_id = te.workspace_id and wm.user_id = te.user_id
          left join public.projects p on p.id = te.project_id
          left join public.clients c on c.id = p.client_id
          left join public.tasks t on t.id = te.task_id
          left join public.time_entry_tags tet on tet.time_entry_id = te.id
          left join public.tags tg on tg.id = tet.tag_id
         where te.workspace_id = %(wid)s and te.deleted_at is null and te.end_at is not null
           and te.start_at >= %(start)s and te.start_at < %(end)s
    """
    params: dict = {"wid": workspace_id, "start": start, "end": end + timedelta(days=1)}
    for key in ("user_id", "project_id"):
        if filters.get(key):
            sql += f" and te.{key} = %({key})s"
            params[key] = filters[key]
    if filters.get("user_ids"):
        sql += " and te.user_id = any(%(user_ids)s::uuid[])"
        params["user_ids"] = filters["user_ids"]
    if filters.get("client_id"):
        sql += " and p.client_id = %(client_id)s"
        params["client_id"] = filters["client_id"]
    if filters.get("billable") in ("true", "false"):
        sql += " and te.billable = %(billable)s"
        params["billable"] = filters["billable"] == "true"
    sql += " group by te.id, wm.display_name, wm.email, p.name, c.name, t.name order by te.start_at"
    return fetch_all(sql, params)


@bp.get("/report")
@require_user
@require_workspace("member")
def export_report():
    today = date.today()
    start = _parse_date(request.args.get("from"), today.replace(day=1))
    end = _parse_date(request.args.get("to"), today)
    fmt = request.args.get("format", "csv").lower()
    filters = {k: request.args.get(k) for k in ("user_id", "project_id", "client_id", "billable")}

    # Un membre ne voit que ses entrées ; un chef d'équipe, aussi celles de son périmètre.
    if g.workspace_role not in _MANAGER_ROLES:
        allowed = [g.user.id, *managed_user_ids(g.workspace_id, g.user.id)]
        if filters["user_id"] and filters["user_id"] not in allowed:
            abort(403, "user outside your team")
        if not filters["user_id"]:
            filters["user_ids"] = allowed

    rows = _detailed_rows(g.workspace_id, start, end, filters)
    filename = f"clockifai-{start.isoformat()}_{end.isoformat()}"

    if fmt == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf, delimiter=";")
        writer.writerow(["Utilisateur", "Email", "Client", "Projet", "Tâche", "Description", "Tags",
                         "Début", "Fin", "Durée (h)", "Facturable", "Taux horaire"])
        for r in rows:
            writer.writerow([
                r["user_name"], r["user_email"], r["client_name"] or "", r["project_name"] or "",
                r["task_name"] or "", r["description"], r["tags"],
                _fmt_dt(r["start_at"]), _fmt_dt(r["end_at"]),
                f"{(r['duration_seconds'] or 0) / 3600:.2f}".replace(".", ","),
                "oui" if r["billable"] else "non",
                f"{(r['hourly_rate_cents'] or 0) / 100:.2f}".replace(".", ",") if r["hourly_rate_cents"] else "",
            ])
        data = ("﻿" + buf.getvalue()).encode("utf-8")
        return _file_response(data, f"{filename}.csv", "text/csv; charset=utf-8")

    if fmt == "xlsx":
        data = build_xlsx(rows, start, end)
        return _file_response(data, f"{filename}.xlsx",
                              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    if fmt == "pdf":
        data = build_pdf(rows, start, end, workspace_id=g.workspace_id)
        return _file_response(data, f"{filename}.pdf", "application/pdf")

    abort(400, "format must be csv, xlsx or pdf")


def _fmt_dt(value: datetime | None) -> str:
    return value.astimezone().strftime("%Y-%m-%d %H:%M") if value else ""


def _file_response(data: bytes, filename: str, mimetype: str) -> Response:
    return Response(data, mimetype=mimetype,
                    headers={"Content-Disposition": f'attachment; filename="{filename}"'})
