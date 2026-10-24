"""Événements d'activité (hooks Claude Code, extension VSCode) et entrées des agents Claude.

Plan : plans/10-suivi-claude-code.md (D6, D7, D9, D10, D13). Les fonctions sans `conn` sont pures (testées sans
base) ; process_session applique le chronomètre (agent_clock) à une session et écrit par agent_entry_write.
"""

from __future__ import annotations

import json
import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import psycopg

from .agent_clock import Create, Event, Existing, Update, plan_session
from .agents import active_agent
from .entry_defaults import UnknownProject, entry_defaults

log = logging.getLogger(__name__)

AGENT_KINDS = {"prompt", "agent_tool", "agent_stop", "agent_wait", "session_start", "session_end",
               "session_task", "session_description"}
HUMAN_KINDS = {"focus_start", "focus_alive", "focus_end", "edit", "terminal", "presence"}
KINDS = AGENT_KINDS | HUMAN_KINDS | {"commit"}
CLOCK_KINDS = {"prompt", "agent_tool", "agent_stop", "agent_wait", "session_start", "session_end", "session_task"}
TASK_NAME_MAX = 80

MAX_BATCH = 200
MAX_AGE = timedelta(days=7)          # événements plus anciens refusés, et fenêtre du recalcul
MAX_FUTURE = timedelta(minutes=5)
MAX_PAYLOAD = 2000                   # caractères JSON
DESCRIPTION_MAX = 500

_TEXT_LIMITS = {"session_id": 200, "window_id": 200, "remote_key": 300, "cwd": 1000, "git_branch": 200,
                "sha": 64, "subject": 200, "author_email": 320, "editor": 50, "machine": 100, "excerpt": 200}


# ---------------------------------------------------------------- fonctions pures
def _parse_time(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.fromisoformat(value)
    except ValueError:
        return None
    return dt if dt.tzinfo else None


def parse_event(raw: dict, now: datetime) -> tuple[dict | None, str | None]:
    """Événement reçu → ligne d'activity_events, ou (None, raison du refus)."""
    if not isinstance(raw, dict):
        return None, "not an object"
    try:
        event_id = str(uuid.UUID(str(raw.get("id"))))
    except ValueError:
        return None, "id must be a UUID"
    kind = raw.get("kind")
    if kind not in KINDS:
        return None, f"unknown kind {kind!r}"
    occurred = _parse_time(raw.get("occurred_at"))
    if occurred is None:
        return None, "occurred_at must be an ISO 8601 date with a time zone"
    if occurred > now + MAX_FUTURE or occurred < now - MAX_AGE:
        return None, "occurred_at out of range"
    row = {"id": event_id, "kind": kind, "occurred_at": occurred}
    for name, limit in _TEXT_LIMITS.items():
        value = raw.get(name)
        row[name] = str(value)[:limit] if value not in (None, "") else None
    if kind in AGENT_KINDS and not row["session_id"]:
        return None, "session_id is required"
    row["actor"] = "agent" if kind in AGENT_KINDS or (kind == "commit" and row["session_id"]) else "human"
    row["authored_at"] = _parse_time(raw.get("authored_at"))
    row["active"] = raw.get("active") if isinstance(raw.get("active"), bool) else None
    payload = dict(raw["payload"]) if isinstance(raw.get("payload"), dict) else {}
    if isinstance(raw.get("duration_ms"), int) and raw["duration_ms"] >= 0:
        payload["duration_ms"] = raw["duration_ms"]
    text = json.dumps(payload, ensure_ascii=False)
    if len(text) > MAX_PAYLOAD:
        return None, "payload too large"
    row["payload"] = text if payload else None
    return row, None


def repo_name(remote_key: str | None) -> str | None:
    if not remote_key:
        return None
    return remote_key.removeprefix("local:").rstrip("/").rsplit("/", 1)[-1] or None


def auto_description(subjects: list[str], remote_key: str | None, branch: str | None) -> str:
    """Messages des commits de la plage (D10.2), sinon dépôt et branche (D10.4)."""
    if subjects:
        return "; ".join(dict.fromkeys(s for s in subjects if s))[:DESCRIPTION_MAX]
    repo = repo_name(remote_key)
    if repo and branch:
        return f"{repo} ({branch})"
    return repo or branch or ""


@dataclass(frozen=True)
class Rule:
    match_kind: str
    pattern: str
    project_id: str
    task_id: str | None


def match_rule(rules: list[Rule], remote_key: str | None, cwd: str | None) -> Rule | None:
    """Règle par chemin (la plus longue qui préfixe cwd), sinon règle par dépôt (D9)."""
    best = None
    if cwd:
        for r in rules:
            prefix = r.pattern.rstrip("/")
            covers = r.match_kind == "path_prefix" and (cwd == prefix or cwd.startswith(prefix + "/"))
            if covers and (best is None or len(prefix) > len(best.pattern.rstrip("/"))):
                best = r
    if best is None and remote_key:
        best = next((r for r in rules if r.match_kind == "repo" and r.pattern == remote_key), None)
    return best


def _latest(rows: list[dict], kind: str, until: datetime) -> dict | None:
    found = [r for r in rows if r["kind"] == kind and r["occurred_at"] <= until]
    return found[-1] if found else None


def _context(rows: list[dict], until: datetime) -> dict:
    """Dépôt, branche et dossier de la session à cet instant (dernier événement qui les porte)."""
    found = [r for r in rows if r["occurred_at"] <= until and (r["remote_key"] or r["cwd"])]
    last = found[-1] if found else next((r for r in rows if r["remote_key"] or r["cwd"]), None)
    return {k: (last[k] if last else None) for k in ("remote_key", "git_branch", "cwd")}


def _payload(row: dict | None) -> dict:
    if not row or not row["payload"]:
        return {}
    return row["payload"] if isinstance(row["payload"], dict) else json.loads(row["payload"])


# ---------------------------------------------------------------- base
def store_events(conn: psycopg.Connection, workspace_id: str, user_id: str, token_id: str | None,
                 rows: list[dict]) -> int:
    inserted = 0
    for r in rows:
        cur = conn.execute(
            """
            insert into clockifai_private.activity_events
              (id, workspace_id, user_id, token_id, actor, kind, occurred_at, session_id, window_id, remote_key, cwd,
               git_branch, sha, subject, author_email, authored_at, editor, machine, active, payload, excerpt)
            values (%(id)s, %(wid)s, %(uid)s, %(token_id)s, %(actor)s, %(kind)s, %(occurred_at)s, %(session_id)s,
                    %(window_id)s, %(remote_key)s, %(cwd)s, %(git_branch)s, %(sha)s, %(subject)s, %(author_email)s,
                    %(authored_at)s, %(editor)s, %(machine)s, %(active)s, %(payload)s::jsonb, %(excerpt)s)
            on conflict (id) do nothing
            """,
            {**r, "wid": workspace_id, "uid": user_id, "token_id": token_id},
        )
        inserted += cur.rowcount
    return inserted


def _rules(conn, workspace_id: str, pilot_id: str) -> list[Rule]:
    rows = conn.execute(
        "select match_kind, pattern, project_id, task_id from public.activity_rules "
        "where workspace_id = %s and user_id = %s and deleted_at is null",
        (workspace_id, pilot_id),
    ).fetchall()
    return [Rule(r["match_kind"], r["pattern"], str(r["project_id"]), str(r["task_id"]) if r["task_id"] else None)
            for r in rows]


def project_for(conn, workspace_id: str, rules: list[Rule], ctx: dict) -> tuple[str | None, str | None]:
    """Règle personnelle (chemin, puis dépôt), sinon projet du dépôt posé par un admin (D9)."""
    rule = match_rule(rules, ctx["remote_key"], ctx["cwd"])
    if rule:
        return rule.project_id, rule.task_id
    if ctx["remote_key"]:
        row = conn.execute(
            "select project_id from public.code_repositories where workspace_id = %s and remote_key = %s "
            "and deleted_at is null and project_id is not null",
            (workspace_id, ctx["remote_key"]),
        ).fetchone()
        if row:
            return str(row["project_id"]), None
    return None, None


def task_name(payload: dict) -> str | None:
    """Nom de tâche donné par Claude (`session_task`, D18), espaces réduits et longueur bornée."""
    name = " ".join(str(payload.get("task_name") or "").split())[:TASK_NAME_MAX]
    return name or None


def named_task(conn, workspace_id: str, project_id: str | None, name: str | None) -> str | None:
    """Tâche nommée par Claude dans le projet de l'entrée (D18) : la tâche active de ce nom, sinon une nouvelle si le
    workspace laisse tout le monde créer des tâches. None sans projet, sans nom ou sans ce droit."""
    if not project_id or not name:
        return None
    # Deux sessions qui nomment le même sujet en même temps ne font qu'une tâche.
    conn.execute("select pg_advisory_xact_lock(hashtextextended('task:' || %s || ':' || lower(%s), 0))",
                 (project_id, name))
    row = conn.execute(
        "select id from public.tasks where workspace_id = %s and project_id = %s and lower(name) = lower(%s) "
        "and status = 'active' and deleted_at is null order by created_at limit 1",
        (workspace_id, project_id, name),
    ).fetchone()
    if row:
        return str(row["id"])
    ws = conn.execute("select task_creation from public.workspaces where id = %s", (workspace_id,)).fetchone()
    if not ws or (ws["task_creation"] or "everyone") != "everyone":
        return None
    row = conn.execute(
        "insert into public.tasks (workspace_id, project_id, name) select %s, id, %s from public.projects "
        "where id = %s and workspace_id = %s and deleted_at is null returning id",
        (workspace_id, name, project_id, workspace_id),
    ).fetchone()
    return str(row["id"]) if row else None


def _valid_task(conn, workspace_id: str, project_id: str | None, task_id: str | None) -> tuple[str | None, str | None]:
    """Tâche donnée par la session (set_current_task) : le projet se déduit de la tâche ; un id inconnu est ignoré."""
    if task_id:
        row = conn.execute(
            "select project_id from public.tasks where id = %s and workspace_id = %s and deleted_at is null",
            (task_id, workspace_id),
        ).fetchone()
        if row:
            return str(row["project_id"]), task_id
    if project_id and conn.execute(
        "select 1 from public.projects where id = %s and workspace_id = %s and deleted_at is null",
        (project_id, workspace_id),
    ).fetchone():
        return project_id, None
    return None, None


def write_agent_entry(conn, entry_id: str, workspace_id: str, agent_id: str, pilot_id: str, start: datetime,
                      end: datetime | None, project_id, task_id, description: str, billable: bool,
                      rate: int | None) -> str:
    return conn.execute(
        "select public.agent_entry_write(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) as status",
        (entry_id, workspace_id, agent_id, pilot_id, start, end, project_id, task_id, description, billable, rate),
    ).fetchone()["status"]


def process_session(conn: psycopg.Connection, workspace_id: str, pilot_id: str, session_id: str,
                    now: datetime | None = None) -> int:
    """Recalcule les entrées de l'agent du pilote pour une session (D7) et rattache ses commits (D13).
    Renvoie le nombre d'entrées écrites. À appeler dans une transaction."""
    now = now or datetime.now(UTC)
    agent_id = active_agent(conn, workspace_id, pilot_id)
    if agent_id is None:
        return 0  # agent absent, désactivé ou retiré : événements gardés, aucune entrée (D7.10)
    conn.execute("select pg_advisory_xact_lock(hashtextextended('session:' || %s, 0))", (session_id,))

    rows = conn.execute(
        """
        select id, kind, occurred_at, payload, remote_key, git_branch, cwd, sha, subject, author_email, authored_at
          from clockifai_private.activity_events
         where workspace_id = %s and user_id = %s and session_id = %s and occurred_at > %s
         order by occurred_at, received_at
        """,
        (workspace_id, pilot_id, session_id, now - MAX_AGE),
    ).fetchall()
    existing_rows = conn.execute(
        """
        select te.id, te.start_at, te.end_at, te.deleted_at, te.project_id, te.task_id, te.description,
               te.billable, te.hourly_rate_cents, ae.server_start_at, ae.server_end_at, ae.server_project_id,
               ae.server_task_id, ae.server_description, ae.description_source, ae.git_branch
          from clockifai_private.agent_entries ae join public.time_entries te on te.id = ae.time_entry_id
         where ae.workspace_id = %s and ae.session_id = %s and ae.last_activity_at > %s
         order by te.start_at
        """,
        (workspace_id, session_id, now - MAX_AGE),
    ).fetchall()
    by_id = {str(r["id"]): r for r in existing_rows}
    events = [Event(r["kind"], r["occurred_at"], _payload(r).get("duration_ms"), str(r["id"]),
                    task_name(_payload(r)) if r["kind"] == "session_task" else None)
              for r in rows if r["kind"] in CLOCK_KINDS]
    existing = [Existing(str(r["id"]), r["start_at"], r["end_at"], r["deleted_at"], r["server_start_at"],
                         r["server_end_at"]) for r in existing_rows]
    rules = _rules(conn, workspace_id, pilot_id)
    written = 0

    for op in plan_session(events, existing, now):
        iv = op.interval
        until = iv.end or now
        ctx = _context(rows, until)
        task_ev = _payload(_latest(rows, "session_task", until))
        desc_ev = _payload(_latest(rows, "session_description", until))

        if isinstance(op, Create):
            entry_id, start = str(uuid.uuid4()), iv.start
            project_id, task_id = _valid_task(conn, workspace_id, task_ev.get("project_id"), task_ev.get("task_id"))
            if project_id is None:
                # Une nouvelle entrée de la session reprend le projet de la précédente, sauf changement de branche.
                prev = [r for r in existing_rows if r["deleted_at"] is None and r["start_at"] <= start]
                if prev and prev[-1]["project_id"] and prev[-1]["git_branch"] == ctx["git_branch"]:
                    project_id = str(prev[-1]["project_id"])
                    task_id = str(prev[-1]["task_id"]) if prev[-1]["task_id"] else None
                else:
                    project_id, task_id = project_for(conn, workspace_id, rules, ctx)
            # Sujet nommé par Claude pendant cette entrée : il prime sur la tâche reprise de la précédente (D18).
            task_id = named_task(conn, workspace_id, project_id, iv.subject) or task_id
            cur = None
            server_project = (project_id, task_id)
        else:
            assert isinstance(op, Update)
            cur = by_id[op.entry_id]
            entry_id, start = op.entry_id, op.start or cur["start_at"]
            project_id = str(cur["project_id"]) if cur["project_id"] else None
            task_id = str(cur["task_id"]) if cur["task_id"] else None
            human_project = (cur["project_id"], cur["task_id"]) != (cur["server_project_id"], cur["server_task_id"])
            if human_project:  # un choix fait dans l'app n'est jamais écrasé (D9)
                server_project = (str(cur["server_project_id"]) if cur["server_project_id"] else None,
                                  str(cur["server_task_id"]) if cur["server_task_id"] else None)
            else:
                p, t = _valid_task(conn, workspace_id, task_ev.get("project_id"), task_ev.get("task_id"))
                if p:
                    project_id, task_id = p, t
                elif project_id is None:
                    project_id, task_id = project_for(conn, workspace_id, rules, ctx)
                server_project = (project_id, task_id)
            # Sujet nommé par Claude (D18), y compris dans un projet choisi à la main, sauf tâche choisie à la main.
            human_task = cur["task_id"] is not None and cur["task_id"] != cur["server_task_id"]
            named = None if human_task else named_task(conn, workspace_id, project_id, iv.subject)
            if named:
                task_id, server_project = named, (server_project[0], named)

        # Description (D10) : saisie humaine > Claude > commits > dépôt et branche.
        if cur is not None and cur["description"] != cur["server_description"]:
            description, desc_source = cur["description"], cur["description_source"]
            server_description = cur["server_description"]
        else:
            if desc_ev.get("description"):
                description, desc_source = str(desc_ev["description"])[:DESCRIPTION_MAX], "claude"
            elif iv.subject and task_id is None:
                # Sujet nommé sans tâche possible (pas de projet, ou création réservée) : il décrit l'entrée.
                description, desc_source = iv.subject, "claude"
            else:
                subjects = [r["subject"] for r in rows if r["kind"] == "commit" and r["subject"]
                            and iv.start <= r["occurred_at"] <= until]
                description, desc_source = auto_description(subjects, ctx["remote_key"], ctx["git_branch"]), "auto"
            server_description = description

        if cur is not None and project_id == (str(cur["project_id"]) if cur["project_id"] else None):
            billable, rate = cur["billable"], cur["hourly_rate_cents"]
        else:
            try:
                billable, rate = entry_defaults(conn, workspace_id, agent_id, project_id)
            except UnknownProject:
                project_id, task_id = None, None
                billable, rate = entry_defaults(conn, workspace_id, agent_id, None)

        end = iv.end
        if cur is not None:
            unchanged = (
                not op.times_changed and project_id == (str(cur["project_id"]) if cur["project_id"] else None)
                and task_id == (str(cur["task_id"]) if cur["task_id"] else None) and description == cur["description"]
            )
            if unchanged:
                _save_state(conn, entry_id, workspace_id, agent_id, session_id, ctx, iv, start=cur["server_start_at"],
                            end=cur["server_end_at"], project_id=cur["server_project_id"],
                            task_id=cur["server_task_id"], description=cur["server_description"],
                            description_source=cur["description_source"])
                continue
            if op.start is None:  # début corrigé à la main : on garde la valeur du serveur comme référence
                server_start = cur["server_start_at"]
            else:
                server_start = start
        else:
            server_start = start

        status = write_agent_entry(conn, entry_id, workspace_id, agent_id, pilot_id, start, end, project_id, task_id,
                                   description, billable, rate)
        if status != "ok":
            log.info("entrée d'agent %s non écrite : %s", entry_id, status)
            continue
        written += 1
        _save_state(conn, entry_id, workspace_id, agent_id, session_id, ctx, iv, start=server_start, end=end,
                    project_id=server_project[0], task_id=server_project[1], description=server_description,
                    description_source=desc_source)

    link_commits(conn, workspace_id, pilot_id, session_id, rows, now)
    return written


def _save_state(conn, entry_id, workspace_id, agent_id, session_id, ctx, iv, *, start, end, project_id, task_id,
                description, description_source) -> None:
    conn.execute(
        """
        insert into clockifai_private.agent_entries
          (time_entry_id, workspace_id, agent_user_id, session_id, remote_key, git_branch, cwd, last_activity_at,
           waiting_since, closed_by_idle, server_start_at, server_end_at, server_project_id, server_task_id,
           server_description, description_source)
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        on conflict (time_entry_id) do update set
          remote_key = excluded.remote_key, git_branch = excluded.git_branch, cwd = excluded.cwd,
          last_activity_at = excluded.last_activity_at, waiting_since = excluded.waiting_since,
          closed_by_idle = excluded.closed_by_idle, server_start_at = excluded.server_start_at,
          server_end_at = excluded.server_end_at, server_project_id = excluded.server_project_id,
          server_task_id = excluded.server_task_id, server_description = excluded.server_description,
          description_source = excluded.description_source
        """,
        (entry_id, workspace_id, agent_id, session_id, ctx["remote_key"], ctx["git_branch"], ctx["cwd"], iv.last,
         iv.waiting_since, iv.closed_by_idle, start, end, project_id, task_id, description, description_source),
    )


def link_commits(conn, workspace_id: str, pilot_id: str, session_id: str, rows: list[dict], now: datetime) -> None:
    """Commits revendiqués par la session (D13) : dépôt, commit, et entrée d'agent qui couvre son heure."""
    for r in rows:
        if r["kind"] != "commit" or not r["sha"] or not r["remote_key"]:
            continue
        repo = conn.execute(
            """
            insert into public.code_repositories (workspace_id, remote_key, name) values (%s, %s, %s)
            on conflict (workspace_id, remote_key) do update set remote_key = excluded.remote_key
            returning id
            """,
            (workspace_id, r["remote_key"], repo_name(r["remote_key"]) or r["remote_key"]),
        ).fetchone()
        entry = conn.execute(
            """
            select te.id from clockifai_private.agent_entries ae join public.time_entries te on te.id = ae.time_entry_id
             where ae.workspace_id = %s and ae.session_id = %s and te.deleted_at is null
               and te.start_at <= %s and coalesce(te.end_at, %s) >= %s
             order by te.start_at desc limit 1
            """,
            (workspace_id, session_id, r["occurred_at"], now, r["occurred_at"]),
        ).fetchone()
        author = conn.execute(
            "select id from auth.users where lower(email) = lower(%s)", (r["author_email"] or "",)
        ).fetchone()
        conn.execute(
            """
            insert into public.code_commits (workspace_id, repository_id, sha, branch, subject, author_email,
                                             author_user_id, authored_at, seen_locally_at, session_id, time_entry_id)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            on conflict (repository_id, sha) do update set
              time_entry_id = coalesce(public.code_commits.time_entry_id, excluded.time_entry_id),
              session_id = coalesce(public.code_commits.session_id, excluded.session_id),
              seen_locally_at = coalesce(public.code_commits.seen_locally_at, excluded.seen_locally_at)
            """,
            (workspace_id, repo["id"], r["sha"], r["git_branch"], r["subject"] or "", r["author_email"],
             author["id"] if author else None, r["authored_at"], r["occurred_at"], session_id,
             entry["id"] if entry else None),
        )
