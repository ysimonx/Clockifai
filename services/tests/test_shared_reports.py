"""Rapports partagés (plans/18-rapports-presence-alertes-partage.md, lot 3) : périodes, filtres, page."""

from __future__ import annotations

from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

import pytest
from flask import Flask

from app.services import shared_reports as sr


@pytest.mark.parametrize(("period", "week_start", "expected"), [
    ("this_week", 1, (date(2026, 10, 26), date(2026, 11, 1))),
    ("this_week", 7, (date(2026, 10, 25), date(2026, 10, 31))),
    ("last_week", 1, (date(2026, 10, 19), date(2026, 10, 25))),
    ("this_month", 1, (date(2026, 10, 1), date(2026, 10, 31))),
    ("last_month", 1, (date(2026, 9, 1), date(2026, 9, 30))),
    ("this_year", 1, (date(2026, 1, 1), date(2026, 12, 31))),
])
def test_periods_from_a_tuesday(period, week_start, expected):
    assert sr.period_range(period, date(2026, 10, 27), week_start) == expected


def test_january_and_december():
    assert sr.period_range("last_month", date(2027, 1, 15), 1) == (date(2026, 12, 1), date(2026, 12, 31))
    assert sr.period_range("this_month", date(2026, 12, 3), 1) == (date(2026, 12, 1), date(2026, 12, 31))
    assert sr.period_range("custom", date(2026, 12, 3), 1, date(2026, 1, 5), date(2026, 2, 1)) == (
        date(2026, 1, 5), date(2026, 2, 1))


def test_rounding_like_the_app():
    assert [sr.round_seconds(m * 60, 15) for m in (7, 8, 22, 23)] == [0, 900, 900, 1800]
    assert sr.round_seconds(1234, 0) == 1234


def test_filters_are_checked():
    pid = "8b3c3f0e-6f3a-4a63-9a63-0d6a5d6c1e11"
    assert sr.clean_filters({"project_id": pid, "billable": True, "member_kind": "human", "client_id": ""}) == {
        "project_id": pid, "billable": "true", "member_kind": "human"}
    assert sr.clean_filters(None) == {}
    for bad in ({"project_id": "x"}, {"billable": "maybe"}, {"user_ids": [pid]}, ["project_id"]):
        assert sr.clean_filters(bad) is None


def _row(project, task, seconds, description="", billable=True, rate=6000, subtask=None):
    start = datetime(2026, 10, 20, 7, tzinfo=UTC)
    return {"project_name": project, "client_name": "ACME" if project else None, "task_name": task,
            "subtask_name": subtask, "duration_seconds": seconds, "billable": billable, "hourly_rate_cents": rate,
            "description": description, "user_name": "Léa", "start_at": start, "end_at": start}


def test_summary_by_project_then_task():
    rows = [_row("Unité 4", "Montage", 3600), _row("Unité 4", "Montage", 1800, subtask="Niveau 3"),
            _row("Unité 4", None, 600), _row("Interne", None, 7200, billable=False)]
    summary = sr.summarize(rows)
    assert [(p["name"], p["seconds"], round(p["amount"], 2)) for p in summary] == [("Interne", 7200, 0.0),
                                                                                    ("Unité 4", 6000, 100.0)]
    assert summary[0]["tasks"] == [], "un projet sans tâche n'a rien à détailler"
    assert [(t["name"], t["seconds"]) for t in summary[1]["tasks"]] == [("Montage", 5400), (None, 600)]


def test_descriptions_and_amounts_only_when_asked():
    rows = [_row("Unité 4", "Montage", 3600, description="Échafaudage côté nord")]
    report = {"name": "Unité 4 — client", "detailed": False, "show_amounts": False, "rounding": False}
    kwargs = {"workspace": "Échafaudages du Nord", "currency": "EUR", "lang": "fr", "tz": ZoneInfo("Europe/Paris"),
              "rounding_minutes": 15, "now": datetime(2026, 10, 27, 9, tzinfo=UTC)}
    with Flask(__name__).app_context():
        page = sr.render(report, rows, date(2026, 10, 1), date(2026, 10, 31), **kwargs)
        detailed = sr.render({**report, "detailed": True, "show_amounts": True}, rows, date(2026, 10, 1),
                             date(2026, 10, 31), **kwargs)
    assert "Du 1 oct. 2026 au 31 oct. 2026" in page and "1:00" in page
    assert "Échafaudage côté nord" not in page and "€" not in page
    assert "Échafaudage côté nord" in detailed and "60,00 €" in detailed
    assert "?format=pdf" in page and "<script" not in page
