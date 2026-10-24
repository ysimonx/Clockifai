"""Agent Claude d'un pilote (plan 10, D14) : un compte technique par pilote, membre de ses workspaces."""

from __future__ import annotations

import psycopg

from .gotrue import gotrue_admin

AGENT_EMAIL_DOMAIN = "agents.clockifai.invalid"  # .invalid : domaine réservé, jamais d'email reçu
AGENT_NAME = "Claude"


def agent_account(conn: psycopg.Connection, pilot_id: str) -> str | None:
    row = conn.execute(
        "select id from auth.users where raw_app_meta_data ->> 'kind' = 'agent' "
        "and raw_app_meta_data ->> 'owner_id' = %s order by created_at limit 1",
        (pilot_id,),
    ).fetchone()
    return str(row["id"]) if row else None


def ensure_agent(conn: psycopg.Connection, workspace_id: str, pilot_id: str) -> str:
    """Crée, s'ils manquent, le compte de l'agent du pilote puis son adhésion au workspace. Ne réactive ni ne
    recrée jamais un agent désactivé ou retiré par un admin. Renvoie l'id de l'agent. À appeler dans une
    transaction : un verrou consultatif par pilote évite deux comptes pour deux créations simultanées."""
    conn.execute("select pg_advisory_xact_lock(hashtextextended('agent:' || %s, 0))", (pilot_id,))
    pilot = conn.execute(
        "select p.display_name, p.timezone from public.profiles p where p.id = %s", (pilot_id,)
    ).fetchone()
    name = f"{AGENT_NAME} · {pilot['display_name']}" if pilot and pilot["display_name"] else AGENT_NAME

    agent_id = agent_account(conn, pilot_id)
    if agent_id is None:
        meta = {"kind": "agent", "owner_id": pilot_id}
        user = gotrue_admin("admin/users", {
            "email": f"agent-{pilot_id}@{AGENT_EMAIL_DOMAIN}",
            "email_confirm": True,
            "app_metadata": meta,
            # Lu par handle_new_user à l'insertion, avant que GoTrue n'écrive les app_metadata (0013).
            "user_metadata": {**meta, "display_name": name},
            "ban_duration": "876000h",
        })
        agent_id = str(user["id"])
        conn.execute(
            "update public.profiles set timezone = %s where id = %s",
            (pilot["timezone"] if pilot else "Europe/Paris", agent_id),
        )

    conn.execute(
        """
        insert into public.workspace_members (workspace_id, user_id, role, kind, agent_owner_id, display_name)
        values (%s, %s, 'member', 'agent', %s, %s)
        on conflict do nothing
        """,
        (workspace_id, agent_id, pilot_id, name),
    )
    return agent_id


def active_agent(conn: psycopg.Connection, workspace_id: str, pilot_id: str) -> str | None:
    """L'agent actif du pilote dans ce workspace, ou None (absent, désactivé ou retiré)."""
    row = conn.execute(
        "select user_id from public.workspace_members where workspace_id = %s and agent_owner_id = %s "
        "and kind = 'agent' and status = 'active' and deleted_at is null",
        (workspace_id, pilot_id),
    ).fetchone()
    return str(row["user_id"]) if row else None
