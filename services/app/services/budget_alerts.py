"""Alertes de budget (plans/18-rapports-presence-alertes-partage.md, lot 2).

Projets et tâches qui franchissent 80 % puis 100 % de leur budget en heures, de leur budget en montant ou de leur
estimation. Chaque seuil n'est noté qu'une fois (`clockifai_private.budget_alerts`, la valeur du budget comprise :
un budget relevé réarme) ; les managers actifs du workspace reçoivent un email par passage du job. Mêmes règles
que la liste « À surveiller » de l'app (`app/lib/features/projects/budget_watch.dart`).
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, replace

import psycopg

from ..auth import MANAGER_ROLES

THRESHOLDS = (80, 100)

# Entrées terminées depuis le début ; montant des entrées facturables au taux de l'entrée, sinon du projet, sinon
# du membre (comme les exports), durées brutes.
_PROJECTS = """
    select p.id::text as target_id, p.workspace_id::text as workspace_id, p.name, null as project_name,
           p.budget_hours, p.budget_amount_cents,
           coalesce(sum(extract(epoch from te.end_at - te.start_at)), 0)::bigint as seconds,
           coalesce(sum(case when te.billable then extract(epoch from te.end_at - te.start_at) / 3600.0
                        * coalesce(te.hourly_rate_cents, p.hourly_rate_cents, wm.hourly_rate_cents, 0) end), 0)::bigint
             as amount_cents
      from public.projects p
      left join public.time_entries te on te.project_id = p.id and te.deleted_at is null and te.end_at is not null
      left join public.workspace_members wm on wm.workspace_id = te.workspace_id and wm.user_id = te.user_id
     where p.deleted_at is null and not p.archived and (p.budget_hours > 0 or p.budget_amount_cents > 0)
     group by p.id
"""

# Une tâche compte ses sous-tâches (plan 16) ; une tâche finie ne déclenche plus rien.
_TASKS = """
    select t.id::text as target_id, t.workspace_id::text as workspace_id, t.name, p.name as project_name,
           t.estimate_seconds,
           (select coalesce(sum(extract(epoch from te.end_at - te.start_at)), 0)::bigint
              from public.time_entries te
             where te.deleted_at is null and te.end_at is not null
               and te.task_id in (select c.id from public.tasks c
                                   where (c.id = t.id or c.parent_id = t.id) and c.deleted_at is null)) as seconds
      from public.tasks t
      join public.projects p on p.id = t.project_id
     where t.estimate_seconds > 0 and t.status = 'active' and t.deleted_at is null
       and p.deleted_at is null and not p.archived
"""


@dataclass(frozen=True)
class Alert:
    workspace_id: str
    target_id: str
    metric: str  # hours | amount | estimate
    name: str
    project_name: str | None
    used: int  # secondes, ou centimes pour un montant
    budget: int
    threshold: int

    @property
    def percent(self) -> int:
        return self.used * 100 // self.budget


def measures(conn: psycopg.Connection) -> list[Alert]:
    """Chaque budget suivi, avec sa consommation (seuil à 0 : pas encore évalué)."""
    out = []
    for r in conn.execute(_PROJECTS).fetchall():
        common = {"workspace_id": r["workspace_id"], "target_id": r["target_id"], "name": r["name"],
                  "project_name": None, "threshold": 0}
        if (r["budget_hours"] or 0) > 0:
            out.append(Alert(metric="hours", used=r["seconds"], budget=r["budget_hours"] * 3600, **common))
        if (r["budget_amount_cents"] or 0) > 0:
            out.append(Alert(metric="amount", used=r["amount_cents"], budget=r["budget_amount_cents"], **common))
    for r in conn.execute(_TASKS).fetchall():
        out.append(Alert(workspace_id=r["workspace_id"], target_id=r["target_id"], metric="estimate", name=r["name"],
                         project_name=r["project_name"], used=r["seconds"], budget=r["estimate_seconds"], threshold=0))
    return out


def new_alerts(conn: psycopg.Connection) -> list[Alert]:
    """Note les seuils nouvellement franchis et renvoie, par budget, le plus haut d'entre eux. Dans une transaction."""
    out = []
    for m in measures(conn):
        fresh = []
        for t in THRESHOLDS:
            if m.used * 100 < m.budget * t:
                break
            if conn.execute(
                "insert into clockifai_private.budget_alerts (workspace_id, target_id, metric, threshold, budget) "
                "values (%s, %s, %s, %s, %s) on conflict do nothing returning threshold",
                (m.workspace_id, m.target_id, m.metric, t, m.budget),
            ).fetchone():
                fresh.append(t)
        if fresh:
            out.append(replace(m, threshold=max(fresh)))
    return out


_TEXTS = {
    "fr": {
        "hours": "{percent} % du budget en heures ({used} sur {budget})",
        "amount": "{percent} % du budget en montant ({used} sur {budget})",
        "estimate": "{percent} % de l'estimation ({used} sur {budget})",
        "subject_one": "Clockifai · {name} : {what}",
        "subject_many": "Clockifai · {n} alertes de budget",
        "intro": "Bonjour,\n\nDans « {workspace} » :\n\n",
        "outro": "\nÀ voir dans Clockifai, Projets › À surveiller : {url}\n",
    },
    "en": {
        "hours": "{percent}% of the hours budget ({used} of {budget})",
        "amount": "{percent}% of the amount budget ({used} of {budget})",
        "estimate": "{percent}% of the estimate ({used} of {budget})",
        "subject_one": "Clockifai · {name}: {what}",
        "subject_many": "Clockifai · {n} budget alerts",
        "intro": "Hello,\n\nIn “{workspace}”:\n\n",
        "outro": "\nSee Clockifai, Projects › To watch: {url}\n",
    },
}
_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}


def _hours(seconds: int, locale: str) -> str:
    text = f"{seconds / 3600:.1f}".removesuffix(".0")
    return (text.replace(".", ",") if locale == "fr" else text) + " h"


def _money(cents: int, currency: str, locale: str) -> str:
    symbol = _SYMBOLS.get(currency, currency)
    if locale == "fr":
        return f"{cents / 100:,.0f}".replace(",", " ") + f" {symbol}"
    return f"{symbol}{cents / 100:,.0f}" if symbol in _SYMBOLS.values() else f"{cents / 100:,.0f} {symbol}"


def describe(a: Alert, currency: str, locale: str) -> str:
    """« 102 % du budget en heures (204 h sur 200 h) »."""
    texts = _TEXTS.get(locale, _TEXTS["fr"])
    fmt = (lambda v: _money(v, currency, locale)) if a.metric == "amount" else (lambda v: _hours(v, locale))
    return texts[a.metric].format(percent=a.percent, used=fmt(a.used), budget=fmt(a.budget))


def compose(alerts: list[Alert], workspace: str, currency: str, locale: str, app_url: str) -> tuple[str, str]:
    """Sujet et texte de l'email d'un manager pour les alertes d'un workspace."""
    texts = _TEXTS.get(locale, _TEXTS["fr"])
    alerts = sorted(alerts, key=lambda a: -a.percent)

    def label(a: Alert) -> str:
        return f"{a.project_name} › {a.name}" if a.project_name else a.name

    if len(alerts) == 1:
        subject = texts["subject_one"].format(name=label(alerts[0]), what=describe(alerts[0], currency, locale))
    else:
        subject = texts["subject_many"].format(n=len(alerts))
    lines = "".join(f"- {label(a)} : {describe(a, currency, locale)}\n" if locale == "fr"
                    else f"- {label(a)}: {describe(a, currency, locale)}\n" for a in alerts)
    text = (texts["intro"].format(workspace=workspace) + lines
            + texts["outro"].format(url=f"{app_url.rstrip('/')}/projects"))
    return subject, text


def messages(conn: psycopg.Connection, alerts: list[Alert], app_url: str) -> list[tuple[str, str, str]]:
    """(destinataire, sujet, texte) : un email par manager actif (humain) de chaque workspace concerné, dans sa
    langue."""
    by_ws: dict[str, list[Alert]] = defaultdict(list)
    for a in alerts:
        by_ws[a.workspace_id].append(a)
    if not by_ws:
        return []
    rows = conn.execute(
        """
        select w.id::text as workspace_id, w.name as workspace, w.currency,
               coalesce(nullif(m.email, ''), u.email) as email, coalesce(pr.locale, 'fr') as locale
          from public.workspaces w
          join public.workspace_members m on m.workspace_id = w.id
          join auth.users u on u.id = m.user_id
          left join public.profiles pr on pr.id = m.user_id
         where w.id = any(%s::uuid[]) and m.role = any(%s) and m.status = 'active' and m.deleted_at is null
           and m.kind = 'human'
        """,
        (list(by_ws), list(MANAGER_ROLES)),
    ).fetchall()
    out = []
    for r in rows:
        if not r["email"]:
            continue
        subject, text = compose(by_ws[r["workspace_id"]], r["workspace"], r["currency"], r["locale"], app_url)
        out.append((r["email"], subject, text))
    return out
