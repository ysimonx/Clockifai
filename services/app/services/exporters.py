"""Génération XLSX (openpyxl) et PDF (WeasyPrint + Jinja2) des rapports détaillés."""

from __future__ import annotations

import io
from collections import defaultdict
from datetime import UTC, date, tzinfo

from flask import render_template_string
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

_HEADERS = ["Utilisateur", "Type", "Client", "Projet", "Tâche", "Sous-tâche", "Ticket", "Description", "Tags",
            "Début", "Fin", "Durée (h)", "Facturable", "Montant", "Tokens IA", "Coût IA estimé (USD)"]
_TICKET_COL = _HEADERS.index("Ticket") + 1


def member_kind_label(row: dict) -> str:
    """Colonne « Type » : temps d'un agent Claude ou d'une personne (plans/10-suivi-claude-code.md)."""
    return "agent" if row.get("user_kind") == "agent" else "humain"


def ticket_of(row: dict) -> str:
    """Colonne « Ticket » : l'adresse du ticket du client de la tâche, sinon sa clé (plans/19-tickets-clients.md)."""
    return row.get("ticket_url") or row.get("ticket_key") or ""


def ai_cost(row: dict) -> float:
    """Coût IA estimé d'une entrée d'agent, en dollars au tarif de l'API (plans/10-suivi-claude-code.md, D17)."""
    return (row.get("ai_cost_micros") or 0) / 1e6


def entry_amount(row: dict) -> float:
    """Montant facturable d'une ligne, en unités : durée × taux, 0 si non facturable ou sans taux."""
    if not row["billable"] or not row["hourly_rate_cents"]:
        return 0.0
    return round((row["duration_seconds"] or 0) / 3600 * row["hourly_rate_cents"] / 100, 2)


def build_xlsx(rows: list[dict], start: date, end: date, *, tz: tzinfo = UTC) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Détail"
    ws.append([f"Clockifai — rapport du {start:%d/%m/%Y} au {end:%d/%m/%Y}"])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(_HEADERS)
    for cell in ws[3]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1F2937")
        cell.alignment = Alignment(horizontal="center")

    for r in rows:
        ws.append([
            r["user_name"], member_kind_label(r), r["client_name"] or "", r["project_name"] or "", r["task_name"] or "",
            r.get("subtask_name") or "", ticket_of(r), r["description"], r["tags"],
            r["start_at"].astimezone(tz).replace(tzinfo=None) if r["start_at"] else None,
            r["end_at"].astimezone(tz).replace(tzinfo=None) if r["end_at"] else None,
            round((r["duration_seconds"] or 0) / 3600, 2),
            "oui" if r["billable"] else "non",
            entry_amount(r),
            r.get("ai_tokens") or None,
            round(ai_cost(r), 4) if r.get("ai_cost_micros") is not None else None,
        ])
    start_col = _HEADERS.index("Début") + 1
    for row in ws.iter_rows(min_row=4, min_col=start_col, max_col=start_col + 1):
        for cell in row:
            cell.number_format = "yyyy-mm-dd hh:mm"
    # Adresse du ticket cliquable.
    for (cell,) in ws.iter_rows(min_row=4, min_col=_TICKET_COL, max_col=_TICKET_COL):
        if isinstance(cell.value, str) and cell.value.startswith(("https://", "http://")):
            cell.hyperlink = cell.value
            cell.font = Font(color="1D4ED8", underline="single")
    for col, width in enumerate([22, 9, 18, 22, 18, 18, 24, 40, 18, 17, 17, 10, 10, 12, 12, 14], start=1):
        ws.column_dimensions[get_column_letter(col)].width = width
    ws.freeze_panes = "A4"

    # Feuille résumé par projet
    summary = wb.create_sheet("Résumé")
    summary.append(["Projet", "Client", "Heures", "Montant", "Coût IA estimé (USD)"])
    for cell in summary[1]:
        cell.font = Font(bold=True)
    agg = _by_project(rows)
    for (project, client), (hours, amount, cost) in sorted(agg.items()):
        summary.append([project, client, round(hours, 2), round(amount, 2), round(cost, 2)])
    summary.append(["Total", "", round(sum(v[0] for v in agg.values()), 2), round(sum(v[1] for v in agg.values()), 2),
                    round(sum(v[2] for v in agg.values()), 2)])
    summary[summary.max_row][0].font = Font(bold=True)
    for col, width in enumerate([28, 22, 10, 12, 14], start=1):
        summary.column_dimensions[get_column_letter(col)].width = width

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _by_project(rows: list[dict]) -> dict[tuple, list[float]]:
    """Heures, montant et coût IA estimé par (projet, client)."""
    agg: dict[tuple, list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])
    for r in rows:
        key = (r["project_name"] or "(sans projet)", r["client_name"] or "")
        agg[key][0] += (r["duration_seconds"] or 0) / 3600
        agg[key][1] += entry_amount(r)
        agg[key][2] += ai_cost(r)
    return agg


_PDF_TEMPLATE = """
<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 14mm; @bottom-right { content: "Page " counter(page) " / " counter(pages); font-size: 9px; color: #6b7280; } }
  body { font-family: "DejaVu Sans", sans-serif; font-size: 9.5px; color: #111827; }
  h1 { font-size: 16px; margin: 0 0 2px; }
  .sub { color: #6b7280; margin-bottom: 10px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #1f2937; color: white; text-align: left; padding: 4px 5px; font-size: 9px; }
  td { padding: 3px 5px; border-bottom: 1px solid #e5e7eb; vertical-align: top; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  .totals { margin-top: 10px; font-weight: bold; }
  .summary { margin-bottom: 12px; width: 60%; }
</style></head><body>
<h1>Rapport de temps</h1>
<div class="sub">Du {{ start.strftime('%d/%m/%Y') }} au {{ end.strftime('%d/%m/%Y') }} — {{ rows|length }} entrée(s)</div>

<table class="summary">
  <tr><th>Projet</th><th>Client</th><th class="num">Heures</th><th class="num">Montant</th>
    {% if has_ai %}<th class="num">Coût IA estimé (USD)</th>{% endif %}</tr>
  {% for s in summary %}
  <tr><td>{{ s.project }}</td><td>{{ s.client }}</td><td class="num">{{ '%.2f' % s.hours }}</td><td class="num">{{ '%.2f' % s.amount }}</td>
    {% if has_ai %}<td class="num">{{ '%.2f' % s.ai_cost }}</td>{% endif %}</tr>
  {% endfor %}
  <tr class="totals"><td>Total</td><td></td><td class="num">{{ '%.2f' % total_hours }}</td><td class="num">{{ '%.2f' % total_amount }}</td>
    {% if has_ai %}<td class="num">{{ '%.2f' % total_ai_cost }}</td>{% endif %}</tr>
</table>
{% if has_ai %}<div class="sub">Coût IA : tokens des entrées d'agent Claude au tarif de l'API d'Anthropic, en dollars US (estimation).</div>{% endif %}

<table>
  <thead><tr>
    <th>Utilisateur</th><th>Type</th><th>Client</th><th>Projet</th><th>Tâche</th><th>Sous-tâche</th><th>Ticket</th><th>Description</th><th>Tags</th>
    <th>Début</th><th>Fin</th><th class="num">Durée (h)</th><th>Fact.</th><th class="num">Montant</th>
  </tr></thead>
  <tbody>
  {% for r in rows %}
  <tr>
    <td>{{ r.user_name }}</td><td>{{ kind(r) }}</td><td>{{ r.client_name or '' }}</td><td>{{ r.project_name or '' }}</td><td>{{ r.task_name or '' }}</td>
    <td>{{ r.subtask_name or '' }}</td>
    <td>{% if r.ticket_url %}<a href="{{ r.ticket_url }}">{{ r.ticket_key or 'lien' }}</a>{% else %}{{ r.ticket_key or '' }}{% endif %}</td>
    <td>{{ r.description }}</td><td>{{ r.tags }}</td>
    <td>{{ r.start_at.astimezone(tz).strftime('%d/%m %H:%M') }}</td><td>{{ r.end_at.astimezone(tz).strftime('%d/%m %H:%M') if r.end_at else '' }}</td>
    <td class="num">{{ '%.2f' % ((r.duration_seconds or 0) / 3600) }}</td>
    <td>{{ 'oui' if r.billable else 'non' }}</td>
    <td class="num">{{ '%.2f' % r.amount }}</td>
  </tr>
  {% endfor %}
  </tbody>
</table>
</body></html>
"""


def build_pdf(rows: list[dict], start: date, end: date, *, tz: tzinfo = UTC) -> bytes:
    from weasyprint import HTML  # import tardif : lib lourde

    for r in rows:
        r["amount"] = entry_amount(r)
    agg = _by_project(rows)
    summary = [{"project": k[0], "client": k[1], "hours": v[0], "amount": v[1], "ai_cost": v[2]}
               for k, v in sorted(agg.items())]
    html = render_template_string(
        _PDF_TEMPLATE, rows=rows, start=start, end=end, summary=summary, kind=member_kind_label, tz=tz,
        total_hours=sum(v[0] for v in agg.values()), total_amount=sum(v[1] for v in agg.values()),
        total_ai_cost=sum(v[2] for v in agg.values()), has_ai=any(r.get("ai_tokens") for r in rows),
    )
    return HTML(string=html).write_pdf()
