"""Exports Excel : colonne « Type » (humain ou agent, plans/10-suivi-claude-code.md)."""

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
        "duration_seconds": 3600, "billable": True, "hourly_rate_cents": 5000,
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
