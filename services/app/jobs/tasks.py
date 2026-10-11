"""Tâches planifiées (APScheduler) — exécutées en rôle postgres, hors RLS."""

from __future__ import annotations

import logging

from ..db import execute, fetch_all

log = logging.getLogger(__name__)


def auto_stop_long_timers(workspace_id: str | None = None) -> int:
    """Arrête les chronomètres qui dépassent workspaces.auto_stop_after_hours (0 = désactivé).

    L'entrée est clôturée à start_at + limite, pas à maintenant : l'utilisateur
    corrige ensuite s'il a réellement travaillé plus longtemps.
    """
    sql = """
        update public.time_entries te
           set end_at = te.start_at + make_interval(hours => w.auto_stop_after_hours)
          from public.workspaces w
         where w.id = te.workspace_id
           and w.auto_stop_after_hours > 0
           and te.end_at is null and te.deleted_at is null
           and now() > te.start_at + make_interval(hours => w.auto_stop_after_hours)
    """
    params: dict = {}
    if workspace_id:
        sql += " and te.workspace_id = %(wid)s"
        params["wid"] = workspace_id
    count = execute(sql, params)
    if count:
        log.info("auto-stop: %s chronomètre(s) arrêté(s)", count)
    return count


def purge_soft_deleted(older_than_days: int = 30) -> int:
    """Supprime physiquement les lignes soft-deleted depuis plus de N jours (déjà retirées des clients par PowerSync)."""
    total = 0
    for table in ("time_entries", "tasks", "projects", "clients", "tags", "workspace_members", "workspaces"):
        total += execute(
            f"delete from public.{table} where deleted_at is not null and deleted_at < now() - make_interval(days => %(d)s)",
            {"d": older_than_days},
        )
    if total:
        log.info("purge: %s ligne(s) supprimée(s)", total)
    return total


def running_timers_summary() -> list[dict]:
    """Diagnostic : chronomètres en cours (utilisé par les logs et les tests)."""
    return fetch_all(
        """
        select te.workspace_id, te.user_id, te.start_at, now() - te.start_at as running_for
          from public.time_entries te
         where te.end_at is null and te.deleted_at is null
         order by te.start_at
        """
    )
