"""Exports Excel : colonne « Type » (humain ou agent) et usage IA des agents (plans/10-suivi-claude-code.md, D17)."""

from __future__ import annotations

import io
from datetime import UTC, date, datetime

from openpyxl import load_workbook

from app.services.exporters import build_xlsx, member_kind_label


def _row(name: str, kind: str | None) -> dict:
    start = datetime(2026, 10, 24, 8, tzinfo=UTC)
    return {
        "user_name": name, "user_kind": kind, "client_name": None, "project_name": "Chantier", "task_name": None,
        "description": "", "tags": "", "start_at": start, "end_at": start.replace(hour=9),
        "duration_seconds": 3600, "billable": True, "hourly_rate_cents": 5000, "ai_tokens": None,
        "ai_cost_micros": None,
    }


def test_member_kind_label():
    assert member_kind_label({"user_kind": "agent"}) == "agent"
    assert member_kind_label({"user_kind": "human"}) == "humain"
    assert member_kind_label({"user_kind": None}) == "humain", "membre introuvable : une personne"


def test_xlsx_type_column():
    data = build_xlsx([_row("Yannick", "human"), _row("Claude · Yannick", "agent")], date(2026, 10, 1), date(2026, 10, 31))
    ws = load_workbook(io.BytesIO(data))["Détail"]
    header = [c.value for c in ws[3]]
    assert header[:2] == ["Utilisateur", "Type"]
    assert [(ws.cell(r, 1).value, ws.cell(r, 2).value) for r in (4, 5)] == [
        ("Yannick", "humain"), ("Claude · Yannick", "agent")]
    assert ws.cell(4, header.index("Début") + 1).is_date, "dates toujours au format date après le décalage"
    assert ws.cell(4, header.index("Montant") + 1).value == 50.0


def test_xlsx_subtask_column():
    """Plan 16 : la tâche de premier niveau, puis la sous-tâche."""
    row = dict(_row("Claude · Yannick", "agent"), task_name="Plan 16 · Sous-tâches", subtask_name="Migration")
    ws = load_workbook(io.BytesIO(build_xlsx([row], date(2026, 10, 1), date(2026, 10, 31))))["Détail"]
    header = [c.value for c in ws[3]]
    assert header[4:6] == ["Tâche", "Sous-tâche"]
    assert (ws.cell(4, 5).value, ws.cell(4, 6).value) == ("Plan 16 · Sous-tâches", "Migration")


def test_xlsx_ai_usage_columns():
    claude = dict(_row("Claude · Yannick", "agent"), ai_tokens=1_234_567, ai_cost_micros=4_560_000)
    data = build_xlsx([_row("Yannick", "human"), claude], date(2026, 10, 1), date(2026, 10, 31))
    book = load_workbook(io.BytesIO(data))
    ws = book["Détail"]
    header = [c.value for c in ws[3]]
    tokens, cost = header.index("Tokens IA") + 1, header.index("Coût IA estimé (USD)") + 1
    assert [ws.cell(r, tokens).value for r in (4, 5)] == [None, 1_234_567]
    assert [ws.cell(r, cost).value for r in (4, 5)] == [None, 4.56]
    summary = book["Résumé"]
    assert [c.value for c in summary[1]][-1] == "Coût IA estimé (USD)"
    assert summary.cell(summary.max_row, 5).value == 4.56
