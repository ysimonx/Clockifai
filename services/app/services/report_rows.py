"""Lignes des rapports détaillés : exports (`routes/exports.py`) et rapports partagés (`services/shared_reports.py`)."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta, tzinfo


def detailed_rows(conn, workspace_id: str, start: date, end: date, tz: tzinfo, filters: dict) -> list[dict]:
    """Une ligne par entrée terminée du workspace, du jour [start] au jour [end] inclus (minuits du fuseau [tz]),
    avec personne, client, projet, tâche et sous-tâche, tags et usage IA. [filters] : user_id, user_ids, project_id,
    client_id, billable (« true » / « false »), member_kind (« human » / « agent »)."""
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
