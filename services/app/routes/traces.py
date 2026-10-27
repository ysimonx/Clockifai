"""Traces d'une journée pour le journal automatique (plans/13-ux-moderne.md, lots 4 et 11).

  GET    /api/traces?workspace_id=…&from=…&to=…  → {events, commits, calendar}
  GET    /api/traces/calendar                    → {configured, host}
  PUT    /api/traces/calendar     {url}           → {configured, host}  (adresse vérifiée en lisant l'agenda)
  DELETE /api/traces/calendar                    → 204

`events` : heure et titre des événements de son agenda (adresse iCal privée) ; `commits` : ses propres commits du
workspace (code_commits, auteur reconnu), avec le dépôt et son projet. Rien n'est enregistré : l'app en tire des
propositions, que la personne confirme ou non.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from flask import Blueprint, abort, g, jsonify, request

from ..auth import require_user, require_workspace
from ..db import connection, fetch_all, fetch_one
from ..services import calendar

bp = Blueprint("traces", __name__)

_MAX_RANGE = timedelta(days=8)


def _instant(name: str) -> datetime:
    raw = request.args.get(name, "")
    try:
        value = datetime.fromisoformat(raw)
    except ValueError:
        abort(400, f"{name} must be an ISO 8601 date-time")
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def _source() -> dict | None:
    return fetch_one("select url from clockifai_private.calendar_sources where user_id = %s", (g.user.id,))


@bp.get("")
@require_user
@require_workspace()
def traces():
    start, end = _instant("from"), _instant("to")
    if end <= start or end - start > _MAX_RANGE:
        abort(400, "from and to must span at most 8 days")
    commits = fetch_all(
        """
        select c.sha, c.subject, coalesce(c.authored_at, c.seen_locally_at) as at,
               r.name as repository, r.project_id
          from public.code_commits c
          join public.code_repositories r on r.id = c.repository_id
         where c.workspace_id = %(wid)s and c.author_user_id = %(uid)s and c.deleted_at is null
           and coalesce(c.authored_at, c.seen_locally_at) >= %(start)s
           and coalesce(c.authored_at, c.seen_locally_at) < %(end)s
         order by 3
        """,
        {"wid": g.workspace_id, "uid": g.user.id, "start": start, "end": end},
    )
    events, status = [], "none"
    source = _source()
    if source:
        try:
            events = [e.as_json() for e in calendar.events_between(calendar.calendar_for(g.user.id, source["url"]), start, end)]
            status = "ok"
        except calendar.CalendarError as err:
            status = err.code
    return jsonify(
        events=events,
        calendar=status,
        commits=[{
            "sha": c["sha"], "subject": c["subject"], "at": c["at"].isoformat(), "repository": c["repository"],
            "project_id": str(c["project_id"]) if c["project_id"] else None,
        } for c in commits],
    )


@bp.get("/calendar")
@require_user
def get_calendar():
    source = _source()
    return jsonify(configured=source is not None, host=calendar.host_of(source["url"]) if source else None)


@bp.put("/calendar")
@require_user
def put_calendar():
    raw = (request.get_json(silent=True) or {}).get("url") or ""
    try:
        url = calendar.normalize_url(raw)
        calendar.parse(calendar.fetch(url))
    except calendar.CalendarError as err:
        return jsonify(error=err.code), 400
    with connection() as conn:
        conn.execute(
            """
            insert into clockifai_private.calendar_sources (user_id, url) values (%s, %s)
            on conflict (user_id) do update set url = excluded.url, updated_at = now()
            """,
            (g.user.id, url),
        )
        conn.commit()
    calendar.forget(g.user.id)
    return jsonify(configured=True, host=calendar.host_of(url))


@bp.delete("/calendar")
@require_user
def delete_calendar():
    with connection() as conn:
        conn.execute("delete from clockifai_private.calendar_sources where user_id = %s", (g.user.id,))
        conn.commit()
    calendar.forget(g.user.id)
    return "", 204
