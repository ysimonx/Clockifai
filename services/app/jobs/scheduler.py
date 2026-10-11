"""Planification des tâches de fond (un seul worker gunicorn → un seul scheduler)."""

from __future__ import annotations

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
    sched.start()
    log.info("scheduler démarré (%s jobs)", len(sched.get_jobs()))
    _scheduler = sched
    return sched
