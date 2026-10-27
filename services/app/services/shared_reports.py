"""Rapports enregistrés et lien public (plans/18-rapports-presence-alertes-partage.md, lot 3).

Un rapport enregistré garde une période (relative ou fixe), des filtres et des options ; sa page publique est
calculée à l'ouverture, dans le fuseau et la langue de son créateur. La même page HTML sert au navigateur et, par
WeasyPrint, au PDF. Les descriptions n'y paraissent qu'avec l'option « détail des entrées ».
"""

from __future__ import annotations

import secrets
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, tzinfo

from flask import render_template_string

from .exporters import entry_amount

PERIODS = ("this_week", "last_week", "this_month", "last_month", "this_year", "custom")
FILTER_KEYS = ("client_id", "project_id", "user_id", "billable", "member_kind")


def new_token() -> str:
    return secrets.token_urlsafe(32)


def clean_filters(raw) -> dict | None:
    """Filtres admis (identifiants au format UUID, facturable, humains ou agents), ou None si l'un est invalide."""
    if raw is None:
        return {}
    if not isinstance(raw, dict) or set(raw) - set(FILTER_KEYS):
        return None
    out = {}
    for key, value in raw.items():
        if value in (None, ""):
            continue
        if key in ("client_id", "project_id", "user_id"):
            try:
                out[key] = str(uuid.UUID(str(value)))
            except ValueError:
                return None
        elif key == "billable" and value in ("true", "false", True, False):
            out[key] = str(value).lower()
        elif key == "member_kind" and value in ("human", "agent"):
            out[key] = value
        else:
            return None
    return out


def period_range(period: str, today: date, week_start: int, date_from: date | None = None,
                 date_to: date | None = None) -> tuple[date, date]:
    """Premier et dernier jour (inclus) de la période ; [week_start] ISO, 1 = lundi."""
    monday = today - timedelta(days=(today.isoweekday() - week_start) % 7)
    month = today.replace(day=1)
    match period:
        case "this_week":
            return monday, monday + timedelta(days=6)
        case "last_week":
            return monday - timedelta(days=7), monday - timedelta(days=1)
        case "this_month":
            return month, (month + timedelta(days=32)).replace(day=1) - timedelta(days=1)
        case "last_month":
            return (month - timedelta(days=1)).replace(day=1), month - timedelta(days=1)
        case "this_year":
            return today.replace(month=1, day=1), today.replace(month=12, day=31)
        case _:
            return date_from or today, date_to or today


def round_seconds(seconds: int, minutes: int) -> int:
    """Arrondi au pas du workspace, à la demi-valeur supérieure (comme `roundSeconds` de l'app)."""
    if minutes <= 0:
        return seconds
    step = minutes * 60
    return (seconds + step // 2) // step * step


_MONTHS = {
    "fr": ("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."),
    "en": ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"),
}
_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}

_TEXTS = {
    "fr": {
        "period": "Du {start} au {end}", "total": "Temps total", "billable": "Temps facturable", "amount": "Montant",
        "by_project": "Par projet et tâche", "project": "Projet", "duration": "Durée", "no_project": "(sans projet)",
        "no_task": "(sans tâche)", "detail": "Détail des entrées", "date": "Date", "person": "Personne",
        "description": "Description", "pdf": "Télécharger le PDF", "empty": "Aucune entrée sur cette période.",
        "footer": "Rapport Clockifai en lecture seule, calculé le {at}.",
        "rounding": "Durées arrondies à {minutes} min.",
    },
    "en": {
        "period": "From {start} to {end}", "total": "Total time", "billable": "Billable time", "amount": "Amount",
        "by_project": "By project and task", "project": "Project", "duration": "Duration", "no_project": "(no project)",
        "no_task": "(no task)", "detail": "Entries", "date": "Date", "person": "Person",
        "description": "Description", "pdf": "Download PDF", "empty": "No entries in this period.",
        "footer": "Read-only Clockifai report, computed on {at}.",
        "rounding": "Durations rounded to {minutes} min.",
    },
}


def _day(d: date, lang: str) -> str:
    month = _MONTHS[lang][d.month - 1]
    return f"{d.day} {month} {d.year}" if lang == "fr" else f"{month} {d.day}, {d.year}"


def _hm(seconds: int) -> str:
    minutes = round(seconds / 60)
    return f"{minutes // 60}:{minutes % 60:02d}"


def _money(value: float, currency: str, lang: str) -> str:
    symbol = _SYMBOLS.get(currency, currency)
    if lang == "fr":
        return f"{value:,.2f}".replace(",", " ").replace(".", ",") + f" {symbol}"
    return f"{symbol}{value:,.2f}" if symbol in _SYMBOLS.values() else f"{value:,.2f} {symbol}"


def summarize(rows: list[dict]) -> list[dict]:
    """Projets (les plus longs d'abord), chacun avec ses tâches ; une sous-tâche compte dans sa tâche."""
    projects: dict = defaultdict(lambda: {"seconds": 0, "amount": 0.0, "tasks": defaultdict(lambda: [0, 0.0])})
    for r in rows:
        p = projects[(r["project_name"], r["client_name"])]
        seconds, amount = r["duration_seconds"] or 0, entry_amount(r)
        p["seconds"] += seconds
        p["amount"] += amount
        t = p["tasks"][r["task_name"]]
        t[0] += seconds
        t[1] += amount
    out = []
    for (name, client), p in sorted(projects.items(), key=lambda kv: -kv[1]["seconds"]):
        tasks = [{"name": t, "seconds": v[0], "amount": v[1]} for t, v in sorted(p["tasks"].items(), key=lambda kv: -kv[1][0])]
        if len(tasks) == 1 and tasks[0]["name"] is None:
            tasks = []  # projet sans tâches : rien à détailler
        out.append({"name": name, "client": client, "seconds": p["seconds"], "amount": p["amount"], "tasks": tasks})
    return out


def render(report: dict, rows: list[dict], start: date, end: date, *, workspace: str, currency: str, lang: str,
           tz: tzinfo, rounding_minutes: int, now: datetime, pdf: bool = False) -> str:
    """La page du rapport (ou le HTML de son PDF). [rows] : `report_rows.detailed_rows`, durées déjà arrondies."""
    lang = lang if lang in _TEXTS else "fr"
    t = _TEXTS[lang]
    total = sum(r["duration_seconds"] or 0 for r in rows)
    billable = sum(r["duration_seconds"] or 0 for r in rows if r["billable"])
    amount = sum(entry_amount(r) for r in rows)
    local_now = now.astimezone(tz)
    return render_template_string(
        _TEMPLATE, t=t, lang=lang, pdf=pdf, name=report["name"], workspace=workspace,
        period=t["period"].format(start=_day(start, lang), end=_day(end, lang)),
        rounding=t["rounding"].format(minutes=rounding_minutes) if report["rounding"] and rounding_minutes > 0 else None,
        amounts=report["show_amounts"], detailed=report["detailed"], rows=rows, projects=summarize(rows),
        total=_hm(total), billable=_hm(billable), amount=_money(amount, currency, lang),
        hm=_hm, money=lambda v: _money(v, currency, lang), day=lambda d: _day(d.astimezone(tz).date(), lang),
        clock=lambda d: d.astimezone(tz).strftime("%H:%M"), amount_of=entry_amount,
        footer=t["footer"].format(at=f"{_day(local_now.date(), lang)} {local_now:%H:%M}"),
    )


_TEMPLATE = """<!doctype html>
<html lang="{{ lang }}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{ name }} · {{ workspace }}</title>
<style>
  @page { size: A4; margin: 14mm; }
  body { margin: 0; background: {{ '#ffffff' if pdf else '#f6f7f9' }}; color: #111827;
         font-family: -apple-system, "Segoe UI", Roboto, "DejaVu Sans", sans-serif; font-size: 14px; line-height: 1.4; }
  main { max-width: 960px; margin: 0 auto; padding: {{ '0' if pdf else '28px 16px 48px' }}; }
  .ws { color: #6b7280; font-size: 13px; }
  h1 { font-size: 24px; margin: 2px 0 4px; }
  h2 { font-size: 15px; margin: 24px 0 8px; }
  .period, .note { color: #4b5563; }
  .note { font-size: 12px; }
  .pdf { display: inline-block; margin-top: 12px; padding: 7px 14px; border-radius: 8px; background: #111827;
         color: #ffffff; text-decoration: none; font-size: 13px; font-weight: 600; }
  .cards { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 20px; }
  .card { background: #ffffff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 10px 16px; min-width: 140px; }
  .card .label { color: #6b7280; font-size: 12px; }
  .card .value { font-size: 20px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .scroll { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; background: #ffffff; border: 1px solid #e5e7eb; }
  th { text-align: left; font-size: 12px; color: #6b7280; font-weight: 600; padding: 8px 12px; background: #f3f4f6; }
  td { padding: 7px 12px; border-top: 1px solid #f0f1f3; vertical-align: top; }
  .num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  tr.project td { font-weight: 600; }
  tr.task td:first-child { padding-left: 28px; color: #374151; }
  .client { color: #6b7280; font-weight: 400; }
  footer { color: #9ca3af; font-size: 12px; margin-top: 28px; }
</style></head>
<body><main>
  <div class="ws">{{ workspace }}</div>
  <h1>{{ name }}</h1>
  <div class="period">{{ period }}</div>
  {% if rounding %}<div class="note">{{ rounding }}</div>{% endif %}
  {% if not pdf %}<a class="pdf" href="?format=pdf">{{ t.pdf }}</a>{% endif %}

  <div class="cards">
    <div class="card"><div class="label">{{ t.total }}</div><div class="value">{{ total }}</div></div>
    <div class="card"><div class="label">{{ t.billable }}</div><div class="value">{{ billable }}</div></div>
    {% if amounts %}<div class="card"><div class="label">{{ t.amount }}</div><div class="value">{{ amount }}</div></div>{% endif %}
  </div>

  {% if not rows %}
  <p class="period">{{ t.empty }}</p>
  {% else %}
  <h2>{{ t.by_project }}</h2>
  <div class="scroll"><table>
    <tr><th>{{ t.project }}</th><th class="num">{{ t.duration }}</th>{% if amounts %}<th class="num">{{ t.amount }}</th>{% endif %}</tr>
    {% for p in projects %}
    <tr class="project"><td>{{ p.name or t.no_project }}{% if p.client %} <span class="client">· {{ p.client }}</span>{% endif %}</td>
      <td class="num">{{ hm(p.seconds) }}</td>{% if amounts %}<td class="num">{{ money(p.amount) }}</td>{% endif %}</tr>
    {% for task in p.tasks %}
    <tr class="task"><td>{{ task.name or t.no_task }}</td><td class="num">{{ hm(task.seconds) }}</td>
      {% if amounts %}<td class="num">{{ money(task.amount) }}</td>{% endif %}</tr>
    {% endfor %}
    {% endfor %}
  </table></div>

  {% if detailed %}
  <h2>{{ t.detail }}</h2>
  <div class="scroll"><table>
    <tr><th>{{ t.date }}</th><th>{{ t.person }}</th><th>{{ t.project }}</th><th>{{ t.description }}</th>
      <th class="num">{{ t.duration }}</th>{% if amounts %}<th class="num">{{ t.amount }}</th>{% endif %}</tr>
    {% for r in rows %}
    <tr><td style="white-space: nowrap">{{ day(r.start_at) }}<br><span class="note">{{ clock(r.start_at) }}–{{ clock(r.end_at) }}</span></td>
      <td>{{ r.user_name or '' }}</td>
      <td>{{ r.project_name or t.no_project }}{% if r.task_name %} › {{ r.task_name }}{% endif %}{% if r.subtask_name %} › {{ r.subtask_name }}{% endif %}</td>
      <td>{{ r.description }}</td><td class="num">{{ hm(r.duration_seconds or 0) }}</td>
      {% if amounts %}<td class="num">{{ money(amount_of(r)) }}</td>{% endif %}</tr>
    {% endfor %}
  </table></div>
  {% endif %}
  {% endif %}

  <footer>{{ footer }}</footer>
</main></body></html>
"""
