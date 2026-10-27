"""Tâches des agents Claude (plan 10, D18 ; plan 16) : le sujet que Claude nomme devient une tâche du projet de
l'entrée, son étape une sous-tâche ; « préciser = renommer » plutôt qu'ajouter une tâche. Réglage « Tâches de
Claude » du pilote (`profiles.claude_tasks`). Appelé par process_session (activity.py), dans sa transaction.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from zoneinfo import ZoneInfo

from .profiles import DEFAULT_TZ, zone

TASK_NAME_MAX = 80


def task_name(payload: dict) -> str | None:
    """Nom de tâche donné par Claude (`session_task`, D18), espaces réduits et longueur bornée."""
    name = " ".join(str(payload.get("task_name") or "").split())[:TASK_NAME_MAX]
    return name or None


# Sujet d'une entrée : l'objectif, et l'étape s'il y en a une (plans/16-sous-taches.md). Le chronomètre (agent_clock)
# compare des sujets entiers : une nouvelle étape commence une nouvelle entrée, sur la sous-tâche de l'étape.
_STEP_SEP = "\u241f"


def session_subject(payload: dict) -> str | None:
    """Objectif et étape donnés par Claude (`session_task` `{task_name, step_name}`), en un seul sujet."""
    name = task_name(payload)
    step = " ".join(str(payload.get("step_name") or "").split())[:TASK_NAME_MAX]
    return f"{name}{_STEP_SEP}{step}" if name and step else name


def split_subject(subject: str | None) -> tuple[str | None, str | None]:
    """(objectif, étape) d'un sujet ; l'étape vaut None quand Claude n'en a pas donné."""
    if not subject:
        return None, None
    name, _, step = subject.partition(_STEP_SEP)
    return name, step or None


def subject_label(subject: str | None) -> str | None:
    """« Objectif · étape », pour décrire une entrée sans tâche possible."""
    name, step = split_subject(subject)
    return f"{name} · {step}" if step else name


_MONTHS = {"fr": ("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."),
           "en": ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")}


@dataclass(frozen=True)
class TaskPrefs:
    """Réglage « Tâches de Claude » du pilote (profiles.claude_tasks : subject, session, off), avec le fuseau et la
    langue des noms datés (D18)."""

    mode: str = "subject"
    tz: ZoneInfo = DEFAULT_TZ
    locale: str = "fr"


def task_prefs(conn, pilot_id: str) -> TaskPrefs:
    row = conn.execute("select claude_tasks, timezone, locale from public.profiles where id = %s", (pilot_id,)).fetchone()
    if not row:
        return TaskPrefs()
    return TaskPrefs(row["claude_tasks"] or "subject", zone(row["timezone"]),
                     "en" if (row["locale"] or "").startswith("en") else "fr")


def _lock_name(conn, project_id: str, name: str) -> None:
    """Deux sessions qui nomment le même sujet en même temps ne font qu'une tâche."""
    conn.execute("select pg_advisory_xact_lock(hashtextextended('task:' || %s || ':' || lower(%s), 0))",
                 (project_id, name))


def _task_named(conn, workspace_id: str, project_id: str, name: str, *, active_only: bool = True,
                exclude: str | None = None, parent_id: str | None = None) -> str | None:
    """Tâche de ce nom au premier niveau du projet, ou sous-tâche de ce nom sous [parent_id]."""
    row = conn.execute(
        "select id from public.tasks where workspace_id = %s and project_id = %s and lower(name) = lower(%s) "
        "and deleted_at is null and (not %s or status = 'active') and id is distinct from %s::uuid "
        "and parent_id is not distinct from %s::uuid order by created_at limit 1",
        (workspace_id, project_id, name, active_only, exclude, parent_id),
    ).fetchone()
    return str(row["id"]) if row else None


def _create_task(conn, workspace_id: str, project_id: str, session_id: str, name: str,
                 parent_id: str | None = None) -> str | None:
    """Nouvelle tâche (ou sous-tâche de [parent_id]), si le workspace laisse tout le monde en créer ; notée dans
    agent_tasks pour la session."""
    ws = conn.execute("select task_creation from public.workspaces where id = %s", (workspace_id,)).fetchone()
    if not ws or (ws["task_creation"] or "everyone") != "everyone":
        return None
    row = conn.execute(
        "insert into public.tasks (workspace_id, project_id, name, parent_id) select %s, id, %s, %s from public.projects "
        "where id = %s and workspace_id = %s and deleted_at is null returning id",
        (workspace_id, name, parent_id, project_id, workspace_id),
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
            "where te.task_id in (select id from public.tasks where id = %s or parent_id = %s) and te.deleted_at is null "
            "and ae.session_id is distinct from %s limit 1",
            (task_id, task_id, session_id),
        ).fetchone()
    else:
        used = conn.execute(
            "select 1 from public.time_entries where task_id in (select id from public.tasks where id = %s or parent_id = %s) "
            "and deleted_at is null and id is distinct from %s::uuid limit 1", (task_id, task_id, entry_id),
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
            "and t.parent_id is null order by a.created_at desc, t.created_at desc limit 1",
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


def step_task(conn, workspace_id: str, session_id: str, project_id: str | None, parent_id: str | None,
              step: str | None, current_task_id: str | None, *, entry_id: str | None = None) -> tuple[str | None, str | None]:
    """Sous-tâche de l'étape [step] sous l'objectif [parent_id] (plans/16-sous-taches.md), reprise par son nom ou créée,
    et sous-tâche devenue vide à supprimer. Comme pour l'objectif, préciser l'étape renomme la sous-tâche créée pour
    cette entrée. (None, None) sans étape ou sans droit de création : l'entrée reste sur l'objectif."""
    if not project_id or not parent_id or not step:
        return None, None
    _lock_name(conn, parent_id, step)
    own = None
    if entry_id and current_task_id and current_task_id != parent_id:
        row = conn.execute(
            "select t.parent_id, t.name <> a.name as renamed from public.tasks t left join clockifai_private.agent_tasks a "
            "on a.task_id = t.id and a.session_id = %s where t.id = %s", (session_id, current_task_id),
        ).fetchone()
        if row and row["parent_id"] and str(row["parent_id"]) == parent_id:
            if row["renamed"]:
                return current_task_id, None  # sous-tâche renommée à la main : un choix humain, elle reste
            own = _own_task(conn, workspace_id, session_id, current_task_id, entry_id=entry_id, whole_session=False)
    existing = _task_named(conn, workspace_id, project_id, step, parent_id=parent_id)
    if own and own["name"].casefold() != step.casefold():
        if existing:
            return existing, str(own["id"])
        _rename(conn, str(own["id"]), step)
        return str(own["id"]), None
    if existing:
        return existing, None
    return _create_task(conn, workspace_id, project_id, session_id, step, parent_id=parent_id), None


def root_task(conn, task_id: str | None) -> str | None:
    """La tâche de premier niveau : la tâche elle-même, ou le parent d'une sous-tâche."""
    if not task_id:
        return None
    row = conn.execute("select parent_id from public.tasks where id = %s", (task_id,)).fetchone()
    return str(row["parent_id"]) if row and row["parent_id"] else task_id


def valid_task(conn, workspace_id: str, project_id: str | None, task_id: str | None) -> tuple[str | None, str | None]:
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
