"""Planification des tâches de fond (un seul worker gunicorn → un seul scheduler)."""

from __future__ import annotations

import functools
import logging

from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask

from . import tasks

log = logging.getLogger(__name__)
_scheduler: BackgroundScheduler | None = None


def start_scheduler(app: Flask) -> BackgroundScheduler:
    global _scheduler
    if _scheduler is not None:
        return _scheduler

    sched = BackgroundScheduler(timezone="UTC")
    sched.add_job(
        tasks.auto_stop_long_timers,
        "interval",
        minutes=app.config["JOB_AUTOSTOP_INTERVAL_MIN"],
        id="auto_stop_long_timers",
        max_instances=1,
        coalesce=True,
    )
    sched.add_job(
        tasks.purge_soft_deleted,
        "cron",
        hour=4,
        minute=15,
        id="purge_soft_deleted",
        kwargs={"older_than_days": app.config["JOB_PURGE_DELETED_AFTER_DAYS"]},
        max_instances=1,
    )
    sched.add_job(
        tasks.close_idle_agent_entries,
        "interval",
        minutes=1,
        id="close_idle_agent_entries",
        max_instances=1,
        coalesce=True,
    )
    sched.add_job(tasks.purge_activity_events, "cron", hour=4, minute=30, id="purge_activity_events", max_instances=1)
    sched.add_job(tasks.close_idle_agent_tasks, "cron", hour=4, minute=0, id="close_idle_agent_tasks", max_instances=1,
                  kwargs={"after_days": app.config["JOB_CLOSE_IDLE_TASKS_AFTER_DAYS"]})

    def in_app(job):
        @functools.wraps(job)  # garde le nom du job dans les journaux
        def run():
            with app.app_context():
                return job()
        return run

    sched.add_job(in_app(tasks.budget_alerts), "cron", minute=7, id="budget_alerts", max_instances=1, coalesce=True)
    sched.add_job(in_app(tasks.send_scheduled_reports), "cron", minute="2,17,32,47", id="send_scheduled_reports",
                  max_instances=1, coalesce=True)
    sched.start()
    log.info("scheduler démarré (%s jobs)", len(sched.get_jobs()))
    _scheduler = sched
    return sched
