"""Exports de rapports : CSV, XLSX, PDF.

GET /api/exports/report?workspace_id=&from=YYYY-MM-DD&to=YYYY-MM-DD&format=csv|xlsx|pdf
    [&user_id=][&project_id=][&client_id=][&billable=true|false][&member_kind=human|agent]

Un membre n'exporte que ses propres entrées et celles de son agent Claude ; un chef d'équipe, aussi celles de son
périmètre ; manager+ peut exporter toute l'équipe. Jours et heures dans le fuseau de son profil.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime, time, timedelta, tzinfo

from flask import Blueprint, Response, abort, g, request

from ..auth import MANAGER_ROLES, readable_user_ids, require_user, require_workspace
from ..db import connection
from ..services.exporters import ai_cost, build_pdf, build_xlsx, member_kind_label
from ..services.profiles import user_tz

bp = Blueprint("exports", __name__)


def _parse_date(value: str | None, default: date) -> date:
    if not value:
        return default
    try:
        return date.fromisoformat(value)
    except ValueError:
        abort(400, f"invalid date: {value}")


def _detailed_rows(conn, workspace_id: str, start: date, end: date, tz: tzinfo, filters: dict) -> list[dict]:
    sql = """
        select te.id, te.start_at, te.end_at, te.duration_seconds, te.description, te.billable,
               -- Entrée saisie avant que son projet ou son membre ait un taux : le taux actuel (catalog.entryRate).
               coalesce(te.hourly_rate_cents, p.hourly_rate_cents, wm.hourly_rate_cents) as hourly_rate_cents,
               wm.display_name as user_name, wm.email as user_email,
               wm.kind as user_kind,
               -- Tâche de premier niveau, et sous-tâche s'il y a lieu (plans/16-sous-taches.md).
               p.name as project_name, c.name as client_name, coalesce(pt.name, t.name) as task_name,
               case when pt.id is not null then t.name end as subtask_name,
               coalesce(string_agg(tg.name, ', ' order by tg.name), '') as tags,
               -- Usage IA des entrées d'agent (plan 10, D17) : tokens et coût estimé, en millionièmes de dollar.
               (select sum(au.input_tokens + au.output_tokens + au.cache_write_5m_tokens + au.cache_write_1h_tokens
                           + au.cache_read_tokens)
                  from public.agent_usage au where au.time_entry_id = te.id and au.deleted_at is null) as ai_tokens,
               (select sum(au.cost_micros)
                  from public.agent_usage au where au.time_entry_id = te.id and au.deleted_at is null) as ai_cost_micros
          from public.time_entries te
          left join public.workspace_members wm on wm.workspace_id = te.workspace_id and wm.user_id = te.user_id
          left join public.projects p on p.id = te.project_id
          left join public.clients c on c.id = p.client_id
          left join public.tasks t on t.id = te.task_id
          left join public.tasks pt on pt.id = t.parent_id
          left join public.time_entry_tags tet on tet.time_entry_id = te.id
          left join public.tags tg on tg.id = tet.tag_id
         where te.workspace_id = %(wid)s and te.deleted_at is null and te.end_at is not null
           and te.start_at >= %(start)s and te.start_at < %(end)s
    """
    # Bornes au minuit du fuseau de la personne, pas à celui de la session Postgres.
    params: dict = {"wid": workspace_id, "start": datetime.combine(start, time.min, tz),
                    "end": datetime.combine(end + timedelta(days=1), time.min, tz)}
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
    if filters.get("member_kind") in ("human", "agent"):
        sql += " and wm.kind = %(member_kind)s"
        params["member_kind"] = filters["member_kind"]
    sql += (" group by te.id, wm.display_name, wm.email, wm.kind, wm.hourly_rate_cents, p.name, p.hourly_rate_cents,"
            " c.name, t.name, pt.id, pt.name order by te.start_at")
    return conn.execute(sql, params).fetchall()


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
        rows = _detailed_rows(conn, g.workspace_id, start, end, tz, filters)
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
