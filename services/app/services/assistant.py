"""« Demander à Clockifai » (plans/13-ux-moderne.md, lot 12, question 6) : un assistant qui répond aux questions sur le
temps passé, et peut proposer une modification groupée que l'app montre en aperçu avant de l'appliquer.

Claude (API Anthropic) ne voit que des agrégats et le référentiel : durées par projet, client, tâche, jour, personne,
montants, noms des projets, clients, tâches et personnes, identifiants et horaires des entrées. Jamais la description
d'une entrée. Les outils lisent seulement ; une proposition (`propose_update`) n'écrit rien : l'app la montre, la
personne l'applique (base locale, droits et triggers habituels) ou non.

Périmètre de lecture : son temps et celui de ses agents ; un chef d'équipe, en plus, ses collaborateurs ; un
manager, un admin ou le propriétaire, tout le workspace.
"""

from __future__ import annotations

import json
import time
from collections import defaultdict, deque
from datetime import date, timedelta
from typing import Any

import anthropic

MAX_TURNS = 8
MAX_QUESTIONS_PER_HOUR = 40
MAX_ENTRIES = 200

SYSTEM = """Tu es l'assistant de Clockifai, une application de suivi du temps. Tu réponds aux questions de la personne
sur le temps passé (le sien, et celui des personnes qu'elle a le droit de voir), en français sauf si elle écrit dans
une autre langue.

Pour répondre, appelle les outils : ils renvoient des totaux par projet, client, tâche, jour ou personne, et des
listes d'entrées (date, horaires, durée, projet, tâche, facturable, personne). Les descriptions des entrées ne te
sont jamais transmises : ne les invente pas. Vérifie les identifiants avec list_catalog avant de filtrer sur un
projet, un client ou une personne. Les dates sont au format AAAA-MM-JJ ; « cette semaine » commence le lundi.

Réponds court et concret : les chiffres d'abord (durées en h:mm, montants avec leur devise), une phrase d'explication
si utile, pas de tableau de plus de dix lignes. Si la question dépasse ce que les outils permettent, dis-le.

Si la personne demande une modification groupée (changer le projet ou la facturation d'entrées), trouve les entrées
avec find_entries puis appelle propose_update : l'application lui montrera un aperçu et elle l'appliquera elle-même.
N'affirme jamais qu'une modification est faite."""


def _tools() -> list[dict]:
    period = {
        "date_from": {"type": "string", "description": "Premier jour inclus, AAAA-MM-JJ."},
        "date_to": {"type": "string", "description": "Dernier jour inclus, AAAA-MM-JJ."},
    }
    filters = {
        "project_id": {"type": "string", "description": "Seulement ce projet (id de list_catalog)."},
        "client_id": {"type": "string", "description": "Seulement les projets de ce client."},
        "person_id": {"type": "string", "description": "Seulement cette personne (id de list_catalog)."},
        "billable": {"type": "boolean", "description": "Seulement le temps facturable (true) ou non facturable (false)."},
    }
    return [
        {
            "name": "list_catalog",
            "description": "Projets, clients, tâches ou personnes visibles, avec leurs identifiants.",
            "input_schema": {
                "type": "object",
                "properties": {"kind": {"type": "string", "enum": ["projects", "clients", "tasks", "people"]}},
                "required": ["kind"],
                "additionalProperties": False,
            },
            "strict": True,
        },
        {
            "name": "time_summary",
            "description": "Temps total sur une période, regroupé par projet, client, tâche, jour ou personne : durée, "
                           "durée facturable et montant facturable.",
            "input_schema": {
                "type": "object",
                "properties": {
                    **period,
                    "group_by": {"type": "string", "enum": ["project", "client", "task", "day", "person"]},
                    **filters,
                },
                "required": ["date_from", "date_to", "group_by"],
                "additionalProperties": False,
            },
        },
        {
            "name": "find_entries",
            "description": f"Entrées terminées d'une période (au plus {MAX_ENTRIES}), sans leur description : id, date, "
                           "début, durée, projet, tâche, facturable, personne.",
            "input_schema": {
                "type": "object",
                "properties": {
                    **period,
                    **filters,
                    "without_project": {"type": "boolean", "description": "Seulement les entrées sans projet."},
                },
                "required": ["date_from", "date_to"],
                "additionalProperties": False,
            },
        },
        {
            "name": "propose_update",
            "description": "Propose une modification groupée d'entrées (projet, tâche, facturation). N'écrit rien : "
                           "l'application montre l'aperçu et la personne l'applique.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "entry_ids": {"type": "array", "items": {"type": "string"}, "description": "Ids de find_entries."},
                    "project_id": {"type": "string"},
                    "task_id": {"type": "string"},
                    "billable": {"type": "boolean"},
                    "summary": {"type": "string", "description": "Une phrase : ce que fait la modification."},
                },
                "required": ["entry_ids", "summary"],
                "additionalProperties": False,
            },
        },
    ]


class Scope:
    """Ce que la personne peut lire : tout le workspace, ou une liste de personnes."""

    def __init__(self, workspace_id: str, user_ids: list[str] | None):
        self.workspace_id = workspace_id
        self.user_ids = user_ids  # None : tout le workspace


def scope_for(conn, workspace_id: str, user_id: str, role: str) -> Scope:
    if role in ("owner", "admin", "manager"):
        return Scope(workspace_id, None)
    rows = conn.execute(
        """
        select user_id::text as id from public.team_scope where workspace_id = %(wid)s and manager_id = %(uid)s
        union
        select user_id::text from public.workspace_members
         where workspace_id = %(wid)s and kind = 'agent' and agent_owner_id = %(uid)s and deleted_at is null
        """,
        {"wid": workspace_id, "uid": user_id},
    ).fetchall()
    return Scope(workspace_id, sorted({user_id, *(r["id"] for r in rows)}))


def _day(value: str) -> date:
    return date.fromisoformat(value)


def _where(scope: Scope, args: dict, tz: str) -> tuple[str, dict]:
    start, end = _day(args["date_from"]), _day(args["date_to"])
    if end < start or end - start > timedelta(days=400):
        raise ValueError("période invalide (400 jours au plus)")
    sql = ["e.workspace_id = %(wid)s", "e.deleted_at is null", "e.end_at is not null",
           "(e.start_at at time zone %(tz)s)::date between %(start)s and %(end)s"]
    params: dict[str, Any] = {"wid": scope.workspace_id, "tz": tz, "start": start, "end": end}
    if scope.user_ids is not None:
        sql.append("e.user_id = any(%(users)s::uuid[])")
        params["users"] = scope.user_ids
    for key, column in (("project_id", "e.project_id"), ("person_id", "e.user_id"), ("client_id", "p.client_id")):
        if args.get(key):
            sql.append(f"{column} = %({key})s::uuid")
            params[key] = args[key]
    if args.get("billable") is not None:
        sql.append("e.billable = %(billable)s")
        params["billable"] = bool(args["billable"])
    if args.get("without_project"):
        sql.append("e.project_id is null")
    return " and ".join(sql), params


def _hm(seconds: int) -> str:
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d}"


def list_catalog(conn, scope: Scope, args: dict) -> list[dict]:
    kind = args["kind"]
    if kind == "projects":
        rows = conn.execute(
            "select p.id::text as id, p.name, c.name as client, p.archived from public.projects p "
            "left join public.clients c on c.id = p.client_id where p.workspace_id = %s and p.deleted_at is null "
            "order by p.name", (scope.workspace_id,)).fetchall()
    elif kind == "clients":
        rows = conn.execute("select id::text as id, name from public.clients where workspace_id = %s "
                            "and deleted_at is null order by name", (scope.workspace_id,)).fetchall()
    elif kind == "tasks":
        rows = conn.execute("select t.id::text as id, t.name, p.name as project from public.tasks t "
                            "join public.projects p on p.id = t.project_id where t.workspace_id = %s "
                            "and t.deleted_at is null order by p.name, t.name", (scope.workspace_id,)).fetchall()
    else:
        sql = ("select user_id::text as id, display_name as name, kind from public.workspace_members "
               "where workspace_id = %(wid)s and deleted_at is null")
        params: dict[str, Any] = {"wid": scope.workspace_id}
        if scope.user_ids is not None:
            sql += " and user_id = any(%(users)s::uuid[])"
            params["users"] = scope.user_ids
        rows = conn.execute(sql + " order by display_name", params).fetchall()
    return [dict(r) for r in rows]


def time_summary(conn, scope: Scope, args: dict, tz: str) -> list[dict]:
    where, params = _where(scope, args, tz)
    key, label = {
        "project": ("e.project_id::text", "coalesce(p.name, '(sans projet)')"),
        "client": ("p.client_id::text", "coalesce(c.name, '(sans client)')"),
        "task": ("e.task_id::text", "coalesce(t.name, '(sans tâche)')"),
        "day": ("((e.start_at at time zone %(tz)s)::date)::text", "((e.start_at at time zone %(tz)s)::date)::text"),
        "person": ("e.user_id::text", "coalesce(m.display_name, '?')"),
    }[args["group_by"]]
    rows = conn.execute(
        f"""
        select {key} as id, {label} as label,
               sum(extract(epoch from e.end_at - e.start_at))::bigint as seconds,
               sum(case when e.billable then extract(epoch from e.end_at - e.start_at) else 0 end)::bigint as billable,
               sum(case when e.billable and e.hourly_rate_cents is not null
                        then extract(epoch from e.end_at - e.start_at) / 3600.0 * e.hourly_rate_cents else 0 end
                  )::bigint as amount_cents
          from public.time_entries e
          left join public.projects p on p.id = e.project_id
          left join public.clients c on c.id = p.client_id
          left join public.tasks t on t.id = e.task_id
          left join public.workspace_members m on m.workspace_id = e.workspace_id and m.user_id = e.user_id
         where {where}
         group by 1, 2 order by 3 desc limit 100
        """,
        params,
    ).fetchall()
    return [{"id": r["id"], "label": r["label"], "duration": _hm(r["seconds"]), "billable": _hm(r["billable"]),
             "amount": round(r["amount_cents"] / 100, 2)} for r in rows]


def find_entries(conn, scope: Scope, args: dict, tz: str) -> dict:
    where, params = _where(scope, args, tz)
    rows = conn.execute(
        f"""
        select e.id::text as id, ((e.start_at at time zone %(tz)s)::date)::text as date,
               to_char(e.start_at at time zone %(tz)s, 'HH24:MI') as start,
               (extract(epoch from e.end_at - e.start_at) / 60)::int as minutes,
               p.name as project, t.name as task, e.billable, m.display_name as person, e.locked
          from public.time_entries e
          left join public.projects p on p.id = e.project_id
          left join public.tasks t on t.id = e.task_id
          left join public.workspace_members m on m.workspace_id = e.workspace_id and m.user_id = e.user_id
         where {where}
         order by e.start_at limit {MAX_ENTRIES + 1}
        """,
        params,
    ).fetchall()
    return {"entries": [dict(r) for r in rows[:MAX_ENTRIES]], "truncated": len(rows) > MAX_ENTRIES}


def run_tool(conn, scope: Scope, tz: str, name: str, args: dict, proposals: list[dict]) -> Any:
    if name == "list_catalog":
        return list_catalog(conn, scope, args)
    if name == "time_summary":
        return time_summary(conn, scope, args, tz)
    if name == "find_entries":
        return find_entries(conn, scope, args, tz)
    if name == "propose_update":
        # Seules les entrées que la personne peut lire, non verrouillées, entrent dans la proposition.
        sql = ("select id::text as id from public.time_entries where workspace_id = %(wid)s and deleted_at is null "
               "and not locked and id = any(%(ids)s::uuid[])")
        params: dict[str, Any] = {"wid": scope.workspace_id, "ids": [str(i) for i in args.get("entry_ids", [])][:MAX_ENTRIES]}
        if scope.user_ids is not None:
            sql += " and user_id = any(%(users)s::uuid[])"
            params["users"] = scope.user_ids
        ids = [r["id"] for r in conn.execute(sql, params).fetchall()]
        if not ids:
            raise ValueError("aucune entrée modifiable parmi celles indiquées")
        proposal = {k: args[k] for k in ("project_id", "task_id", "billable", "summary") if k in args}
        proposals.append({**proposal, "entry_ids": ids})
        return {"status": "proposée à la personne, qui l'appliquera ou non", "entries": len(ids)}
    raise ValueError(f"outil inconnu : {name}")


# Questions récentes, par personne (un seul worker gunicorn : la mémoire du process suffit).
_recent: dict[str, deque] = defaultdict(deque)


def allow(user_id: str) -> bool:
    now = time.monotonic()
    q = _recent[user_id]
    while q and now - q[0] > 3600:
        q.popleft()
    if len(q) >= MAX_QUESTIONS_PER_HOUR:
        return False
    q.append(now)
    return True


def ask(client: anthropic.Anthropic, conn, scope: Scope, *, question: str, history: list[dict], tz: str,
        today: date, model: str, effort: str) -> dict:
    """Une question, avec l'historique de la conversation (textes seulement) ; renvoie la réponse et les propositions."""
    messages: list[dict] = []
    for h in history[-10:]:
        if h.get("role") in ("user", "assistant") and isinstance(h.get("text"), str) and h["text"].strip():
            messages.append({"role": h["role"], "content": h["text"][:4000]})
    if messages and messages[0]["role"] != "user":
        messages.pop(0)
    weekday = ("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")[today.weekday()]
    messages.append({"role": "user", "content": f"(Aujourd'hui : {weekday} {today.isoformat()})\n{question}"})
    proposals: list[dict] = []
    for _ in range(MAX_TURNS):
        response = client.beta.messages.create(
            model=model,
            max_tokens=8000,
            system=SYSTEM,
            tools=_tools(),
            messages=messages,
            output_config={"effort": effort},
            cache_control={"type": "ephemeral"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
        if response.stop_reason == "refusal":
            return {"answer": None, "refused": True, "proposals": []}
        messages.append({"role": "assistant", "content": response.content})
        uses = [b for b in response.content if b.type == "tool_use"]
        if response.stop_reason != "tool_use" or not uses:
            text = "\n\n".join(b.text for b in response.content if b.type == "text").strip()
            return {"answer": text, "refused": False, "proposals": proposals}
        results = []
        for use in uses:
            try:
                result = run_tool(conn, scope, tz, use.name, dict(use.input), proposals)
                results.append({"type": "tool_result", "tool_use_id": use.id,
                                "content": json.dumps(result, ensure_ascii=False, default=str)})
            except (ValueError, KeyError) as err:
                results.append({"type": "tool_result", "tool_use_id": use.id, "content": f"Erreur : {err}",
                                "is_error": True})
        messages.append({"role": "user", "content": results})
    return {"answer": None, "refused": False, "proposals": proposals, "too_long": True}
