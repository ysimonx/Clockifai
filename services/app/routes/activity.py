"""Suivi de Claude Code et de mon activité (plan 10). Jeton personnel `clk_…` ou JWT de l'app.

  POST /api/activity/events  {events: [...]}        → 202 {accepted, duplicates, rejected}
  GET  /api/activity/today                          → mon temps, celui de Claude, la durée calendaire, sessions en cours
  GET  /api/activity/projects                       → projets et tâches actifs du workspace
  POST /api/activity/rules   {remote_key | path_prefix | time_entry_id, project_id, task_id?}
                                                    → règle de rattachement, et réattribution des entrées sans projet
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime, time
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import Blueprint, abort, g, jsonify, request

from ..auth import require_user_or_token
from ..db import connection
from ..services.activity import (
    MAX_BATCH,
    parse_event,
    process_session,
    repo_name,
    store_events,
    write_agent_entry,
)
from ..services.agents import active_agent
from ..services.entry_defaults import UnknownProject, entry_defaults

log = logging.getLogger(__name__)
bp = Blueprint("activity", __name__)


@bp.post("/events")
@require_user_or_token
def events():
    body = request.get_json(silent=True) or {}
    raw = body.get("events")
    if not isinstance(raw, list):
        abort(400, "events must be a list")
    if len(raw) > MAX_BATCH:
        abort(400, f"at most {MAX_BATCH} events per request")
    now = datetime.now(UTC)
    rows, rejected = [], []
    for i, item in enumerate(raw):
        row, reason = parse_event(item, now)
        if row is None:
            rejected.append({"index": i, "reason": reason})
        else:
            rows.append(row)
    sessions = sorted({r["session_id"] for r in rows if r["actor"] == "agent" and r["session_id"]})
    with connection() as conn:
        inserted = store_events(conn, g.workspace_id, g.user.id, g.token_id, rows)
        for session_id in sessions:
            try:
                with conn.transaction():  # point de sauvegarde : une session en erreur n'empêche pas les autres
                    process_session(conn, g.workspace_id, g.user.id, session_id, now)
            except Exception:
                log.exception("session %s : recalcul impossible", session_id)
        conn.commit()
    return jsonify(accepted=inserted, duplicates=len(rows) - inserted, rejected=rejected), 202


def _tz(conn, user_id: str) -> ZoneInfo:
    row = conn.execute("select timezone from public.profiles where id = %s", (user_id,)).fetchone()
    try:
        return ZoneInfo(row["timezone"] if row and row["timezone"] else "Europe/Paris")
    except ZoneInfoNotFoundError:
        return ZoneInfo("Europe/Paris")


def _union_seconds(spans: list[tuple[datetime, datetime]]) -> int:
    total, cur_start, cur_end = 0.0, None, None
    for start, end in sorted(spans):
        if cur_end is None or start > cur_end:
            if cur_end is not None:
                total += (cur_end - cur_start).total_seconds()
            cur_start, cur_end = start, end
        else:
            cur_end = max(cur_end, end)
    if cur_end is not None:
        total += (cur_end - cur_start).total_seconds()
    return int(total)


@bp.get("/today")
@require_user_or_token
def today():
    now = datetime.now(UTC)
    with connection() as conn:
        tz = _tz(conn, g.user.id)
        day_start = datetime.combine(now.astimezone(tz).date(), time.min, tz).astimezone(UTC)
        agent_id = active_agent(conn, g.workspace_id, g.user.id)
        rows = conn.execute(
            """
            select te.id, te.user_id, te.project_id, p.name as project_name, te.start_at,
                   coalesce(te.end_at, %(now)s) as end_at, te.end_at is null as running, ae.remote_key
              from public.time_entries te
              left join public.projects p on p.id = te.project_id
              left join clockifai_private.agent_entries ae on ae.time_entry_id = te.id
             where te.workspace_id = %(wid)s and te.deleted_at is null and te.user_id = any(%(users)s)
               and te.start_at < %(now)s and coalesce(te.end_at, %(now)s) > %(day)s
            """,
            {"wid": g.workspace_id, "users": [u for u in (g.user.id, agent_id) if u], "now": now, "day": day_start},
        ).fetchall()
    projects: dict = {}
    spans, mine, claude, running = [], 0, 0, []
    for r in rows:
        start, end = max(r["start_at"], day_start), min(r["end_at"], now)
        if end <= start:
            continue
        seconds = int((end - start).total_seconds())
        spans.append((start, end))
        is_agent = str(r["user_id"]) != g.user.id
        key = str(r["project_id"]) if r["project_id"] else None
        p = projects.setdefault(key, {"project_id": key, "name": r["project_name"], "my_seconds": 0,
                                      "claude_seconds": 0})
        if is_agent:
            claude += seconds
            p["claude_seconds"] += seconds
            if r["running"]:
                running.append({"entry_id": str(r["id"]), "project_id": key, "project_name": r["project_name"],
                                "repository": repo_name(r["remote_key"]), "since": r["start_at"].isoformat()})
        else:
            mine += seconds
            p["my_seconds"] += seconds
    return jsonify(day=day_start.astimezone(tz).date().isoformat(), my_seconds=mine, claude_seconds=claude,
                   calendar_seconds=_union_seconds(spans), agent_id=agent_id,
                   projects=sorted(projects.values(), key=lambda p: -(p["my_seconds"] + p["claude_seconds"])),
                   running=running)


@bp.get("/projects")
@require_user_or_token
def projects():
    with connection() as conn:
        rows = conn.execute(
            """
            select p.id, p.name, p.color, c.name as client_name,
                   coalesce(json_agg(json_build_object('id', t.id, 'name', t.name) order by lower(t.name))
                            filter (where t.id is not null), '[]') as tasks
              from public.projects p
              left join public.clients c on c.id = p.client_id
              left join public.tasks t on t.project_id = p.id and t.deleted_at is null and t.status = 'active'
             where p.workspace_id = %s and p.deleted_at is null and not p.archived
             group by p.id, c.name
             order by lower(p.name)
            """,
            (g.workspace_id,),
        ).fetchall()
    return jsonify(projects=[{**r, "id": str(r["id"])} for r in rows])


@bp.post("/rules")
@require_user_or_token
def create_rule():
    body = request.get_json(silent=True) or {}
    project_id, task_id = body.get("project_id"), body.get("task_id")
    if not project_id:
        abort(400, "project_id is required")
    with connection() as conn:
        project = conn.execute(
            "select 1 from public.projects where id = %s and workspace_id = %s and deleted_at is null",
            (project_id, g.workspace_id),
        ).fetchone()
        if project is None:
            abort(400, "unknown project")
        if task_id and not conn.execute(
            "select 1 from public.tasks where id = %s and project_id = %s and deleted_at is null", (task_id, project_id)
        ).fetchone():
            abort(400, "unknown task for this project")

        if body.get("path_prefix"):
            kind, pattern = "path_prefix", str(body["path_prefix"]).rstrip("/")[:1000]
        elif body.get("remote_key"):
            kind, pattern = "repo", str(body["remote_key"])[:300]
        elif body.get("time_entry_id"):
            row = conn.execute(
                """
                select ae.remote_key from clockifai_private.agent_entries ae
                  join public.workspace_members m on m.workspace_id = ae.workspace_id and m.user_id = ae.agent_user_id
                 where ae.time_entry_id = %s and ae.workspace_id = %s and m.agent_owner_id = %s
                """,
                (body["time_entry_id"], g.workspace_id, g.user.id),
            ).fetchone()
            if row is None or not row["remote_key"]:
                abort(404, "no repository known for this entry")
            kind, pattern = "repo", row["remote_key"]
        else:
            abort(400, "remote_key, path_prefix or time_entry_id is required")

        rule = conn.execute(
            "insert into public.activity_rules (workspace_id, user_id, match_kind, pattern, project_id, task_id) "
            "values (%s, %s, %s, %s, %s, %s) returning id",
            (g.workspace_id, g.user.id, kind, pattern, project_id, task_id),
        ).fetchone()
        reattributed = _reattribute(conn, kind, pattern, project_id, task_id)
        conn.commit()
    return jsonify(id=str(rule["id"]), match_kind=kind, pattern=pattern, reattributed=reattributed), 201


def _reattribute(conn, kind: str, pattern: str, project_id: str, task_id: str | None) -> int:
    """Entrées de mon agent sans projet, du même dépôt ou sous le même chemin, sur les 7 derniers jours (D9)."""
    agent_id = active_agent(conn, g.workspace_id, g.user.id)
    if agent_id is None:
        return 0
    match = "ae.remote_key = %(p)s" if kind == "repo" else "(ae.cwd = %(p)s or ae.cwd like %(p)s || '/%%')"
    rows = conn.execute(
        f"""
        select te.id, te.start_at, te.end_at, te.description
          from clockifai_private.agent_entries ae join public.time_entries te on te.id = ae.time_entry_id
         where ae.workspace_id = %(wid)s and ae.agent_user_id = %(agent)s and te.deleted_at is null
           and te.project_id is null and ae.server_project_id is null and {match}
           and te.start_at > now() - interval '7 days'
        """,
        {"wid": g.workspace_id, "agent": agent_id, "p": pattern},
    ).fetchall()
    try:
        billable, rate = entry_defaults(conn, g.workspace_id, agent_id, project_id)
    except UnknownProject:
        return 0
    done = 0
    for r in rows:
        status = write_agent_entry(conn, str(r["id"]), g.workspace_id, agent_id, g.user.id, r["start_at"], r["end_at"],
                                   project_id, task_id, r["description"], billable, rate)
        if status == "ok":
            conn.execute(
                "update clockifai_private.agent_entries set server_project_id = %s, server_task_id = %s "
                "where time_entry_id = %s",
                (project_id, task_id, r["id"]),
            )
            done += 1
    return done
