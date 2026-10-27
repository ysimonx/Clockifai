"""Facture PDF : GET /api/invoices/<id>/pdf?workspace_id=…  (managers)."""

from __future__ import annotations

from datetime import date

from flask import Blueprint, Response, abort, g, render_template_string

from ..auth import require_user, require_workspace
from ..db import fetch_all, fetch_one

bp = Blueprint("invoices", __name__)

_TEMPLATE = """
<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<style>
  @page { size: A4; margin: 18mm 16mm; @bottom-center { content: "{{ inv.number or '' }} — page " counter(page) "/" counter(pages); font-size: 8px; color: #6b7280; } }
  body { font-family: "DejaVu Sans", sans-serif; font-size: 10px; color: #111827; }
  .head { display: flex; justify-content: space-between; margin-bottom: 28px; }
  .company { white-space: pre-line; }
  .company strong { font-size: 14px; }
  h1 { font-size: 22px; margin: 0; text-align: right; color: #0369a1; }
  .meta { text-align: right; margin-top: 6px; line-height: 1.6; }
  .client { margin: 0 0 24px 55%; padding: 10px 12px; border: 1px solid #e5e7eb; border-radius: 6px; white-space: pre-line; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #f3f4f6; text-align: left; padding: 7px 6px; font-size: 9px; text-transform: uppercase; color: #374151; }
  td { padding: 7px 6px; border-bottom: 1px solid #e5e7eb; }
  .num { text-align: right; white-space: nowrap; }
  .totals { width: 45%; margin: 16px 0 0 auto; }
  .totals td { border: none; padding: 4px 6px; }
  .grand td { font-size: 13px; font-weight: bold; border-top: 2px solid #111827; }
  .note { margin-top: 28px; white-space: pre-line; color: #374151; }
  a.ticket { color: #1d4ed8; font-size: 9px; word-break: break-all; }
  .status { display: inline-block; padding: 2px 8px; border-radius: 10px; background: #e0f2fe; color: #0369a1; font-size: 9px; }
</style></head><body>
<div class="head">
  <div class="company"><strong>{{ ws.company_name or ws.name }}</strong>
{{ ws.company_details or '' }}</div>
  <div>
    <h1>FACTURE</h1>
    <div class="meta">
      N° <b>{{ inv.number or 'brouillon' }}</b><br>
      Date : {{ fmt_date(inv.issue_date) }}<br>
      Échéance : {{ fmt_date(inv.due_date) }}<br>
      {% if inv.period_start %}Période : {{ fmt_date(inv.period_start) }} – {{ fmt_date(inv.period_end) }}<br>{% endif %}
      <span class="status">{{ status_label }}</span>
    </div>
  </div>
</div>
<div class="client"><b>{{ client.name if client else '' }}</b>
{{ client.address if client and client.address else '' }}{% if client and client.email %}
{{ client.email }}{% endif %}</div>
<table>
  <thead><tr><th>Désignation</th><th class="num">Quantité (h)</th><th class="num">Prix unitaire HT</th><th class="num">Montant HT</th></tr></thead>
  <tbody>
  {% for it in items %}
    <tr><td>{% for line in (it.description or '').splitlines() %}{% if not loop.first %}<br>{% endif %}{% if line.startswith(('https://', 'http://')) %}<a class="ticket" href="{{ line }}">{{ line }}</a>{% else %}{{ line }}{% endif %}{% endfor %}</td><td class="num">{{ qty(it.quantity) }}</td>
        <td class="num">{{ money(it.unit_price_cents) }}</td><td class="num">{{ money(it.amount_cents) }}</td></tr>
  {% endfor %}
  </tbody>
</table>
<table class="totals">
  <tr><td>Sous-total HT</td><td class="num">{{ money(inv.subtotal_cents) }}</td></tr>
  {% if inv.discount_cents %}<tr><td>Remise ({{ pct(inv.discount_percent) }})</td><td class="num">− {{ money(inv.discount_cents) }}</td></tr>{% endif %}
  <tr><td>TVA ({{ pct(inv.tax_percent) }})</td><td class="num">{{ money(inv.tax_cents) }}</td></tr>
  <tr class="grand"><td>Total TTC</td><td class="num">{{ money(inv.total_cents) }}</td></tr>
</table>
{% if inv.note %}<div class="note">{{ inv.note }}</div>{% endif %}
</body></html>
"""

_STATUS = {"draft": "Brouillon", "sent": "Envoyée", "paid": "Payée", "void": "Annulée"}


@bp.get("/<invoice_id>/pdf")
@require_user
@require_workspace("manager")
def invoice_pdf(invoice_id: str):
    from weasyprint import HTML

    inv = fetch_one("select * from public.invoices where id = %s and workspace_id = %s and deleted_at is null",
                    (invoice_id, g.workspace_id))
    if inv is None:
        abort(404, "invoice not found")
    ws = fetch_one("select name, company_name, company_details from public.workspaces where id = %s", (g.workspace_id,))
    client = fetch_one("select name, address, email from public.clients where id = %s", (inv["client_id"],)) if inv["client_id"] else None
    items = fetch_all("select * from public.invoice_items where invoice_id = %s and deleted_at is null order by position",
                      (invoice_id,))
    currency = inv["currency"] or "EUR"

    def money(cents) -> str:
        v = f"{(cents or 0) / 100:,.2f}".replace(",", " ").replace(".", ",")
        return f"{v} {'€' if currency == 'EUR' else currency}"

    def fmt_date(d) -> str:
        return d.strftime("%d/%m/%Y") if isinstance(d, date) else ""

    html = render_template_string(
        _TEMPLATE, inv=inv, ws=ws, client=client, items=items, money=money, fmt_date=fmt_date,
        qty=lambda q: f"{float(q):.2f}".replace(".", ","),
        pct=lambda p: f"{float(p):g} %".replace(".", ","),
        status_label=_STATUS.get(inv["status"], inv["status"]),
    )
    pdf = HTML(string=html).write_pdf()
    name = (inv["number"] or f"brouillon-{invoice_id[:8]}") + ".pdf"
    return Response(pdf, mimetype="application/pdf", headers={"Content-Disposition": f'attachment; filename="{name}"'})
