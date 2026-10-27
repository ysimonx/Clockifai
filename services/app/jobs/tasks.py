"""Tâches planifiées (APScheduler) — exécutées en rôle postgres, hors RLS."""

from __future__ import annotations

import logging

from flask import current_app

from ..db import connection, execute, fetch_all
from ..services import budget_alerts as budgets
from ..services.activity import process_session
from ..services.agent_clock import IDLE_TIMEOUT
from ..services.mailer import send_mail

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
    for table in ("agent_usage", "time_entries", "tasks", "projects", "clients", "tags", "workspace_members", "workspaces"):
        total += execute(
            f"delete from public.{table} where deleted_at is not null and deleted_at < now() - make_interval(days => %(d)s)",
            {"d": older_than_days},
        )
    if total:
        log.info("purge: %s ligne(s) supprimée(s)", total)
    return total


def close_idle_agent_entries() -> int:
    """Recalcule les sessions dont une entrée d'agent tourne sans activité depuis le délai (plan 10, D7.4) :
    le chronomètre la ferme à sa dernière activité."""
    sessions = fetch_all(
        """
        select distinct ae.workspace_id::text as workspace_id, ae.session_id, m.agent_owner_id::text as pilot_id
          from clockifai_private.agent_entries ae
          join public.time_entries te on te.id = ae.time_entry_id
          join public.workspace_members m on m.workspace_id = ae.workspace_id and m.user_id = ae.agent_user_id
         where te.end_at is null and te.deleted_at is null
           and ae.last_activity_at < now() - make_interval(secs => %(idle)s)
        """,
        {"idle": IDLE_TIMEOUT.total_seconds()},
    )
    closed = 0
    for s in sessions:
        try:
            with connection() as conn:
                closed += process_session(conn, s["workspace_id"], s["pilot_id"], s["session_id"])
                conn.commit()
        except Exception:
            log.exception("session %s : fermeture impossible", s["session_id"])
    if closed:
        log.info("agents : %s entrée(s) fermée(s) après inactivité", closed)
    return closed


def purge_activity_events(older_than_days: int = 30) -> int:
    """Événements bruts des hooks et de l'extension : gardés 30 jours (plan 10, D6)."""
    count = execute(
        "delete from clockifai_private.activity_events where received_at < now() - make_interval(days => %(d)s)",
        {"d": older_than_days},
    )
    if count:
        log.info("purge des événements d'activité : %s ligne(s)", count)
    return count


def budget_alerts() -> int:
    """Alertes de budget (plan 18, lot 2) : seuils franchis notés, puis un email par manager. Le seuil est noté même
    sans SMTP ou si l'envoi échoue : jamais de rafale d'emails en retard. Dans le contexte de l'app Flask (mailer)."""
    with connection() as conn:
        alerts = budgets.new_alerts(conn)
        mails = budgets.messages(conn, alerts, current_app.config["APP_PUBLIC_URL"])
        conn.commit()
    sent = sum(send_mail(to, subject, text) for to, subject, text in mails)
    if alerts:
        log.info("budgets : %s alerte(s), %s email(s) envoyé(s)", len(alerts), sent)
    return len(alerts)
