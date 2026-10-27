"""Facturable et taux d'une nouvelle entrée, comme les pose l'app (catalog.rateFor) : partagé par le kiosque et
les agents. Pour un agent s'ajoute le réglage de facturation du temps des agents (plan 10, D16)."""

from __future__ import annotations

import psycopg


class UnknownProject(LookupError):
    pass


def entry_defaults(conn: psycopg.Connection, workspace_id: str, user_id: str,
                   project_id: str | None) -> tuple[bool, int | None]:
    """(facturable, taux horaire en centimes) : taux du projet, sinon du membre ; facturable selon le projet.

    Agent : le réglage du projet (`agent_billable`), sinon celui du workspace (`agent_billing = 'never'`)."""
    member = conn.execute(
        "select kind, hourly_rate_cents from public.workspace_members where workspace_id = %s and user_id = %s",
        (workspace_id, user_id),
    ).fetchone()
    project = None
    if project_id:
        project = conn.execute(
            "select billable_default, hourly_rate_cents, agent_billable from public.projects "
            "where id = %s and workspace_id = %s and deleted_at is null",
            (project_id, workspace_id),
        ).fetchone()
        if project is None:
            raise UnknownProject(project_id)

    rate = project["hourly_rate_cents"] if project else None
    if rate is None and member:
        rate = member["hourly_rate_cents"]
    billable = project["billable_default"] if project else True

    if member and member["kind"] == "agent":
        if project and project["agent_billable"] is not None:
            billable = project["agent_billable"]
        else:
            ws = conn.execute("select agent_billing from public.workspaces where id = %s", (workspace_id,)).fetchone()
            if ws and ws["agent_billing"] == "never":
                billable = False
    return billable, rate
