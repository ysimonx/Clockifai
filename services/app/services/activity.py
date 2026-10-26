"""Événements d'activité (hooks Claude Code, extension VSCode) et entrées des agents Claude.

Plan : plans/10-suivi-claude-code.md (D6, D7, D9, D10, D13, D17). Les fonctions sans `conn` sont pures (testées sans
base) ; process_session applique le chronomètre (agent_clock) à une session et écrit par agent_entry_write.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import psycopg

from .agent_clock import Create, Event, Existing, Update, plan_session
from .agents import active_agent
from .entry_defaults import UnknownProject, entry_defaults

log = logging.getLogger(__name__)

AGENT_KINDS = {"prompt", "agent_tool", "agent_stop", "agent_wait", "session_start", "session_end",
               "session_task", "session_description", "agent_usage"}
HUMAN_KINDS = {"focus_start", "focus_alive", "focus_end", "edit", "terminal", "presence"}
KINDS = AGENT_KINDS | HUMAN_KINDS | {"commit"}
CLOCK_KINDS = {"prompt", "agent_tool", "agent_stop", "agent_wait", "session_start", "session_end", "session_task"}
TASK_NAME_MAX = 80

MAX_BATCH = 200
MAX_AGE = timedelta(days=7)          # événements plus anciens refusés, et fenêtre du recalcul
MAX_FUTURE = timedelta(minutes=5)
MAX_PAYLOAD = 2000                   # caractères JSON
DESCRIPTION_MAX = 500
USAGE_COUNTERS = ("requests", "input_tokens", "output_tokens", "cache_write_5m_tokens", "cache_write_1h_tokens",
                  "cache_read_tokens")
USAGE_MAX = 10**12                   # garde-fou par compteur et par événement

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
    if kind == "agent_usage" and usage_of(payload) is None:
        return None, "agent_usage payload needs model and non-negative integer counters"
    row["payload"] = text if payload else None
    return row, None


# ---------------------------------------------------------------- usage IA (D17)
def usage_of(payload: dict) -> dict | None:
    """Totaux d'un événement `agent_usage` (modèle, effort, vitesse et compteurs), ou None s'il est illisible."""
    model = " ".join(str(payload.get("model") or "").split())[:100]
    if not model:
        return None
    usage = {"model": model, "effort": str(payload["effort"])[:20] if payload.get("effort") else None,
             "speed": str(payload.get("speed") or "standard")[:20]}
    for name in USAGE_COUNTERS:
        value = payload.get(name, 0)
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= USAGE_MAX:
            return None
        usage[name] = value
    return usage


@dataclass(frozen=True)
class Price:
    """Tarif d'un modèle, en dollars par million de tokens, soit des millionièmes de dollar par token."""

    input: Decimal
    output: Decimal
    cache_write_5m: Decimal
    cache_write_1h: Decimal
    cache_read: Decimal
    fast_multiplier: Decimal | None = None


def price_for(model: str, prices: dict[str, Price]) -> Price | None:
    """Tarif du modèle, ou de son nom sans date (claude-haiku-4-5-20251001 → claude-haiku-4-5)."""
    if model in prices:
        return prices[model]
    m = re.fullmatch(r"(.+)-\d{8}", model)
    return prices.get(m.group(1)) if m else None


def cost_micros(usage: dict, price: Price | None) -> int | None:
    """Coût estimé au tarif de l'API, en millionièmes de dollar ; None sans tarif connu."""
    if price is None:
        return None
    total = (usage["input_tokens"] * price.input + usage["output_tokens"] * price.output
             + usage["cache_write_5m_tokens"] * price.cache_write_5m
             + usage["cache_write_1h_tokens"] * price.cache_write_1h + usage["cache_read_tokens"] * price.cache_read)
    if usage["speed"] == "fast" and price.fast_multiplier:
        total *= price.fast_multiplier
    return int(Decimal(total).to_integral_value(ROUND_HALF_UP))


@dataclass(frozen=True)
class EntrySpan:
    id: str
    start: datetime
    end: datetime | None


def usage_entry(entries: list[EntrySpan], at: datetime, now: datetime) -> str | None:
    """Entrée de la session à laquelle rattacher un usage daté de [at] : celle qui couvre cet instant (la plus
    récente), sinon la dernière commencée avant (fin corrigée à la main), sinon la première."""
    covering = [e for e in entries if e.start <= at <= (e.end or now)]
    if covering:
        return max(covering, key=lambda e: e.start).id
    before = [e for e in entries if e.start <= at]
    if before:
        return max(before, key=lambda e: e.start).id
    return min(entries, key=lambda e: e.start).id if entries else None


def aggregate_usage(events: list[tuple[datetime, dict]], entries: list[EntrySpan],
                    now: datetime) -> dict[tuple[str, str, str | None, str], dict]:
    """Cumul par (entrée, modèle, effort, vitesse) des usages [(heure, usage_of(...))] de la session."""
    totals: dict[tuple[str, str, str | None, str], dict] = {}
    for at, usage in events:
        entry_id = usage_entry(entries, at, now)
        if entry_id is None:
            continue
        key = (entry_id, usage["model"], usage["effort"], usage["speed"])
        acc = totals.setdefault(key, dict.fromkeys(USAGE_COUNTERS, 0))
        for name in USAGE_COUNTERS:
            acc[name] += usage[name]
    return totals


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


_PARIS = ZoneInfo("Europe/Paris")
_MONTHS = {"fr": ("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."),
           "en": ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")}


@dataclass(frozen=True)
class TaskPrefs:
    """Réglage « Tâches de Claude » du pilote (profiles.claude_tasks : subject, session, off), avec le fuseau et la
    langue des noms datés (D18)."""

    mode: str = "subject"
    tz: ZoneInfo = _PARIS
    locale: str = "fr"


def task_prefs(conn, pilot_id: str) -> TaskPrefs:
    row = conn.execute("select claude_tasks, timezone, locale from public.profiles where id = %s", (pilot_id,)).fetchone()
    if not row:
        return TaskPrefs()
    try:
        tz = ZoneInfo(row["timezone"]) if row["timezone"] else _PARIS
    except (ZoneInfoNotFoundError, ValueError):
        tz = _PARIS
    return TaskPrefs(row["claude_tasks"] or "subject", tz, "en" if (row["locale"] or "").startswith("en") else "fr")


def _lock_name(conn, project_id: str, name: str) -> None:
    """Deux sessions qui nomment le même sujet en même temps ne font qu'une tâche."""
    conn.execute("select pg_advisory_xact_lock(hashtextextended('task:' || %s || ':' || lower(%s), 0))",
                 (project_id, name))


def _task_named(conn, workspace_id: str, project_id: str, name: str, *, active_only: bool = True,
                exclude: str | None = None) -> str | None:
    row = conn.execute(
        "select id from public.tasks where workspace_id = %s and project_id = %s and lower(name) = lower(%s) "
        "and deleted_at is null and (not %s or status = 'active') and id is distinct from %s::uuid "
        "order by created_at limit 1",
        (workspace_id, project_id, name, active_only, exclude),
    ).fetchone()
    return str(row["id"]) if row else None


def _create_task(conn, workspace_id: str, project_id: str, session_id: str, name: str) -> str | None:
    """Nouvelle tâche, si le workspace laisse tout le monde en créer ; notée dans agent_tasks pour la session."""
    ws = conn.execute("select task_creation from public.workspaces where id = %s", (workspace_id,)).fetchone()
    if not ws or (ws["task_creation"] or "everyone") != "everyone":
        return None
    row = conn.execute(
        "insert into public.tasks (workspace_id, project_id, name) select %s, id, %s from public.projects "
        "where id = %s and workspace_id = %s and deleted_at is null returning id",
        (workspace_id, name, project_id, workspace_id),
    ).fetchone()
    if row is None:
        return None
    conn.execute("insert into clockifai_private.agent_tasks (task_id, workspace_id, session_id, name) "
                 "values (%s, %s, %s, %s)", (row["id"], workspace_id, session_id, name))
    return str(row["id"])


def _own_task(conn, workspace_id: str, session_id: str, task_id: str | None, *, entry_id: str | None,
              whole_session: bool) -> dict | None:
    """La tâche [task_id] si le serveur l'a créée pour cette session, que personne ne l'a renommée, et qu'aucune autre
    entrée ne l'utilise (aucune entrée d'une autre session, en mode « une tâche par session »)."""
    if not task_id:
        return None
    row = conn.execute(
        "select t.id, t.project_id, a.name from clockifai_private.agent_tasks a join public.tasks t on t.id = a.task_id "
        "where a.task_id = %s and a.session_id = %s and a.workspace_id = %s and t.deleted_at is null and t.name = a.name",
        (task_id, session_id, workspace_id),
    ).fetchone()
    if row is None:
        return None
    if whole_session:
        used = conn.execute(
            "select 1 from public.time_entries te left join clockifai_private.agent_entries ae on ae.time_entry_id = te.id "
            "where te.task_id = %s and te.deleted_at is null and ae.session_id is distinct from %s limit 1",
            (task_id, session_id),
        ).fetchone()
    else:
        used = conn.execute(
            "select 1 from public.time_entries where task_id = %s and deleted_at is null and id is distinct from %s::uuid "
            "limit 1", (task_id, entry_id),
        ).fetchone()
    return None if used else row


def _rename(conn, task_id: str, name: str) -> None:
    conn.execute("update public.tasks set name = %s where id = %s", (name, task_id))
    conn.execute("update clockifai_private.agent_tasks set name = %s where task_id = %s", (name, task_id))


def _dated(conn, workspace_id: str, project_id: str, name: str, started_at: datetime, prefs: TaskPrefs,
           exclude: str | None = None) -> str:
    """Nom libre dans le projet : « Export PDF », sinon « Export PDF (25 oct.) », puis « Export PDF (25 oct., 2) »…"""
    if not _task_named(conn, workspace_id, project_id, name, active_only=False, exclude=exclude):
        return name
    day = started_at.astimezone(prefs.tz)
    month = _MONTHS[prefs.locale][day.month - 1]
    label = f"{month} {day.day}" if prefs.locale == "en" else f"{day.day} {month}"
    candidate, n = f"{name} ({label})", 2
    while _task_named(conn, workspace_id, project_id, candidate, active_only=False, exclude=exclude):
        candidate, n = f"{name} ({label}, {n})", n + 1
    return candidate


def subject_task(conn, workspace_id: str, session_id: str, project_id: str | None, name: str | None,
                 current_task_id: str | None, prefs: TaskPrefs, started_at: datetime, *,
                 entry_id: str | None = None) -> tuple[str | None, str | None]:
    """Tâche de l'entrée pour le sujet [name] nommé par Claude (D18), et tâche devenue vide à supprimer une fois
    l'entrée écrite. (None, None) sans projet, sans nom, en mode « off » ou sans droit de création : le nom décrit
    alors l'entrée. [entry_id] : entrée existante, dont la tâche peut être renommée (« préciser = renommer »)."""
    if not project_id or not name or prefs.mode == "off":
        return None, None
    _lock_name(conn, project_id, name)
    if prefs.mode == "session":
        # Une tâche par session, toujours nouvelle ; un nom plus précis la renomme.
        row = conn.execute(
            "select a.task_id from clockifai_private.agent_tasks a join public.tasks t on t.id = a.task_id "
            "where a.session_id = %s and a.workspace_id = %s and t.project_id = %s and t.deleted_at is null "
            "order by a.created_at desc limit 1",
            (session_id, workspace_id, project_id),
        ).fetchone()
        if row:
            own = _own_task(conn, workspace_id, session_id, str(row["task_id"]), entry_id=entry_id, whole_session=True)
            if own and own["name"].casefold() != name.casefold():
                _rename(conn, str(own["id"]), _dated(conn, workspace_id, project_id, name, started_at, prefs,
                                                     exclude=str(own["id"])))
            return str(row["task_id"]), None
        return _create_task(conn, workspace_id, project_id, session_id,
                            _dated(conn, workspace_id, project_id, name, started_at, prefs)), None

    # Une tâche par sujet : préciser le nom renomme la tâche créée pour cette entrée plutôt que d'en ajouter une.
    if entry_id and current_task_id and conn.execute(
        "select 1 from clockifai_private.agent_tasks a join public.tasks t on t.id = a.task_id "
        "where a.task_id = %s and a.session_id = %s and t.name <> a.name", (current_task_id, session_id),
    ).fetchone():
        return current_task_id, None  # tâche de l'entrée renommée à la main : c'est un choix humain, elle reste
    own = _own_task(conn, workspace_id, session_id, current_task_id, entry_id=entry_id,
                    whole_session=False) if entry_id else None
    existing = _task_named(conn, workspace_id, project_id, name)
    if own and own["name"].casefold() != name.casefold():
        if existing:
            return existing, str(own["id"])  # le sujet a déjà sa tâche : celle de l'entrée, vide, disparaît
        _rename(conn, str(own["id"]), name)
        return str(own["id"]), None
    if existing:
        return existing, None
    return _create_task(conn, workspace_id, project_id, session_id, name), None


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
    prefs = task_prefs(conn, pilot_id)
    events = [Event(r["kind"], r["occurred_at"], _payload(r).get("duration_ms"), str(r["id"]),
                    task_name(_payload(r)) if r["kind"] == "session_task" and prefs.mode != "off" else None)
              for r in rows if r["kind"] in CLOCK_KINDS]
    existing = [Existing(str(r["id"]), r["start_at"], r["end_at"], r["deleted_at"], r["server_start_at"],
                         r["server_end_at"]) for r in existing_rows]
    rules = _rules(conn, workspace_id, pilot_id)
    written = 0

    for op in plan_session(events, existing, now, split_subjects=prefs.mode != "session"):
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
            named, emptied = subject_task(conn, workspace_id, session_id, project_id, iv.subject, task_id, prefs,
                                          iv.start)
            task_id = named or task_id
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
            named, emptied = (None, None) if human_task else subject_task(
                conn, workspace_id, session_id, project_id, iv.subject, task_id, prefs, start, entry_id=entry_id)
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
        if emptied:  # tâche créée pour l'entrée puis remplacée par celle du sujet : vide, elle disparaît
            conn.execute(
                "update public.tasks set deleted_at = now() where id = %s and deleted_at is null and not exists "
                "(select 1 from public.time_entries where task_id = %s and deleted_at is null)", (emptied, emptied))
        _save_state(conn, entry_id, workspace_id, agent_id, session_id, ctx, iv, start=server_start, end=end,
                    project_id=server_project[0], task_id=server_project[1], description=server_description,
                    description_source=desc_source)

    link_commits(conn, workspace_id, pilot_id, session_id, rows, now)
    link_usage(conn, workspace_id, agent_id, session_id, rows, now)
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


def _prices(conn) -> dict[str, Price]:
    return {r["model"]: Price(r["input_per_mtok"], r["output_per_mtok"], r["cache_write_5m_per_mtok"],
                              r["cache_write_1h_per_mtok"], r["cache_read_per_mtok"], r["fast_multiplier"])
            for r in conn.execute("select * from public.ai_model_prices").fetchall()}


def link_usage(conn, workspace_id: str, agent_id: str, session_id: str, rows: list[dict], now: datetime) -> None:
    """Usage IA de la session (D17) : cumul par entrée d'agent, recalculé depuis les événements de la fenêtre,
    puisque les entrées peuvent avoir été recoupées ou corrigées depuis. Coût au tarif du moment (instantané)."""
    events = [(r["occurred_at"], usage_of(_payload(r))) for r in rows if r["kind"] == "agent_usage"]
    events = [(at, u) for at, u in events if u is not None]
    spans = conn.execute(
        """
        select te.id, te.start_at, te.end_at
          from clockifai_private.agent_entries ae join public.time_entries te on te.id = ae.time_entry_id
         where ae.workspace_id = %s and ae.session_id = %s and ae.last_activity_at > %s
        """,
        (workspace_id, session_id, now - MAX_AGE),
    ).fetchall()
    if not spans:
        return
    entries = [EntrySpan(str(r["id"]), r["start_at"], r["end_at"]) for r in spans]
    # Seules les entrées commencées dans la fenêtre ont tous leurs événements : les autres gardent leur cumul.
    fresh = {e.id for e in entries if e.start > now - MAX_AGE}
    wanted = {k: v for k, v in aggregate_usage(events, entries, now).items() if k[0] in fresh}
    prices = _prices(conn) if wanted else {}
    for (entry_id, model, effort, speed), counts in wanted.items():
        usage = {"model": model, "effort": effort, "speed": speed, **counts}
        conn.execute(
            """
            insert into public.agent_usage (workspace_id, time_entry_id, user_id, model, effort, speed, requests,
                                            input_tokens, output_tokens, cache_write_5m_tokens, cache_write_1h_tokens,
                                            cache_read_tokens, cost_micros)
            values (%(wid)s, %(entry)s, %(agent)s, %(model)s, %(effort)s, %(speed)s, %(requests)s, %(input_tokens)s,
                    %(output_tokens)s, %(cache_write_5m_tokens)s, %(cache_write_1h_tokens)s, %(cache_read_tokens)s,
                    %(cost)s)
            on conflict on constraint agent_usage_entry_key do update set
              requests = excluded.requests, input_tokens = excluded.input_tokens,
              output_tokens = excluded.output_tokens, cache_write_5m_tokens = excluded.cache_write_5m_tokens,
              cache_write_1h_tokens = excluded.cache_write_1h_tokens, cache_read_tokens = excluded.cache_read_tokens,
              cost_micros = excluded.cost_micros, deleted_at = null
            where (public.agent_usage.requests, public.agent_usage.input_tokens, public.agent_usage.output_tokens,
                   public.agent_usage.cache_write_5m_tokens, public.agent_usage.cache_write_1h_tokens,
                   public.agent_usage.cache_read_tokens, public.agent_usage.cost_micros, public.agent_usage.deleted_at)
                  is distinct from
                  (excluded.requests, excluded.input_tokens, excluded.output_tokens, excluded.cache_write_5m_tokens,
                   excluded.cache_write_1h_tokens, excluded.cache_read_tokens, excluded.cost_micros, null::timestamptz)
            """,
            {**usage, "wid": workspace_id, "entry": entry_id, "agent": agent_id,
             "cost": cost_micros(usage, price_for(model, prices))},
        )
    # Un usage passé à une autre entrée (entrée recoupée, horaires corrigés) quitte l'ancienne.
    keep = [[e, m, f, s] for (e, m, f, s) in wanted]
    conn.execute(
        """
        update public.agent_usage au set deleted_at = now()
         where au.time_entry_id = any(%s::uuid[]) and au.deleted_at is null
           and not exists (select 1 from jsonb_array_elements(%s::jsonb) k
                            where k->>0 = au.time_entry_id::text and k->>1 = au.model
                              and k->>2 is not distinct from au.effort and k->>3 = au.speed)
        """,
        (sorted(fresh), json.dumps(keep)),
    )
