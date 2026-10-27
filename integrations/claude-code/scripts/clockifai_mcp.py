#!/usr/bin/env python3
"""Serveur MCP local du plugin Clockifai (stdio) : l'outil `set_current_task`, par lequel Claude nomme l'objectif en
cours et son étape (plans/10-suivi-claude-code.md, D18 ; plans/16-sous-taches.md : l'étape devient une sous-tâche), et
le ticket du client s'il y en a un (plans/19-tickets-clients.md : le ticket devient la tâche, l'objectif sa
sous-tâche).

N'appelle jamais le réseau et ne lit aucun réglage : il renvoie le nom reçu. Le hook (PostToolUse) le relaie à
Clockifai avec le jeton et l'identifiant de session, que lui seul connaît : un serveur MCP ne reçoit pas la session.
JSON-RPC ligne par ligne sur stdin et stdout ; Python 3.9 et bibliothèque standard seulement.
"""

from __future__ import annotations

import json
import sys

NAME_MAX = 80  # comme le serveur (TASK_NAME_MAX)
TICKET_MAX = 500  # URL d'un ticket (tasks.ticket_url)
TOOL = "set_current_task"

INSTRUCTIONS = (
    "Clockifai mesure le temps de cette session de Claude Code et le range par tâche et sous-tâche. Dès que tu sais "
    f"sur quoi porte le travail, même une vérification rapide, appelle {TOOL} avant de commencer (pas pour une "
    "simple salutation), avec deux noms courts (3 à 6 mots, dans la langue de l'utilisateur) : `name`, l'objectif "
    "d'ensemble, stable d'une session et d'un jour à l'autre (si le travail relève d'un plan numéroté du dépôt, son "
    "numéro et son titre, par exemple « Plan 14 · Coller aux maquettes ») ; `step`, l'étape en cours de cet "
    "objectif. À chaque nouvelle étape, rappelle l'outil avec le même `name` et la nouvelle `step`. Ne change de "
    "`name` que si l'utilisateur passe à un tout autre objectif, et reprends exactement le même `name` pour un "
    "objectif déjà nommé. Un nom plus précis donné juste après renomme. Si l'utilisateur donne le ticket d'un client "
    "(adresse Jira, Linear ou GitHub, ou clé comme ENG-123), passe-le dans `ticket` dès le premier appel, avec "
    "`ticket_title`, un titre court tiré de son message ou du ticket si tu peux le lire : le ticket devient la tâche "
    "et `name` sa sous-tâche, pour toute la session ; inutile de le répéter ensuite, sauf autre ticket. Pas de nom "
    "de personne ni de donnée confidentielle. Inutile de le signaler à l'utilisateur."
)

TOOLS = [{
    "name": TOOL,
    "title": "Nommer la tâche Clockifai",
    "description": (
        "Nomme l'objectif (la tâche Clockifai) et l'étape en cours (sa sous-tâche) : le temps de cette session y est "
        "rangé, dans le projet du dépôt. Même objectif, même tâche ; chaque étape a sa sous-tâche."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "Objectif d'ensemble, stable (3 à 6 mots)", "maxLength": NAME_MAX},
            "step": {"type": "string", "description": "Étape en cours de cet objectif (3 à 6 mots), facultative",
                     "maxLength": NAME_MAX},
            "ticket": {"type": "string", "description": "Ticket du client donné par l'utilisateur : son adresse "
                       "(Jira, Linear, GitHub) ou sa clé (ENG-123), facultatif", "maxLength": TICKET_MAX},
            "ticket_title": {"type": "string", "description": "Titre court du ticket (3 à 8 mots), facultatif",
                             "maxLength": NAME_MAX},
        },
        "required": ["name"],
    },
}]


def text(message: str, error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": message}], "isError": error}


def handle(msg: dict) -> dict | None:
    """Réponse à une requête JSON-RPC ; None pour une notification (sans `id`)."""
    if "id" not in msg:
        return None
    method, params = msg.get("method"), msg.get("params")
    params = params if isinstance(params, dict) else {}
    if method == "initialize":
        result = {
            # La version demandée par le client : ce serveur n'utilise que des messages communs à toutes.
            "protocolVersion": params.get("protocolVersion") or "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "clockifai", "version": "1"},
            "instructions": INSTRUCTIONS,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call" and params.get("name") == TOOL:
        args = params.get("arguments")
        args = args if isinstance(args, dict) else {}
        name = " ".join(str(args.get("name") or "").split())[:NAME_MAX]
        step = " ".join(str(args.get("step") or "").split())[:NAME_MAX]
        ticket = str(args.get("ticket") or "").strip()[:TICKET_MAX]
        noted = f"« {name} » › « {step} »" if step else f"« {name} »"
        if ticket:
            noted = f"{noted}, ticket {ticket}"
        result = text(f"Tâche {noted} notée : le temps de cette session y est rangé.") if name else text(
            "Nom de tâche vide : rien n'est changé.", error=True)
    else:
        return {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": f"unknown method {method}"}}
    return {"jsonrpc": "2.0", "id": msg["id"], "result": result}


def main() -> None:
    # Octets UTF-8 dans les deux sens, quelle que soit la locale du poste (LANG=C ne doit pas couper l'outil).
    for line in sys.stdin.buffer:
        try:
            msg = json.loads(line.decode("utf-8"))
        except ValueError:
            continue
        if not isinstance(msg, dict):
            continue
        try:
            reply = handle(msg)
        except Exception as e:  # noqa: BLE001 - une requête inattendue ne doit pas arrêter le serveur
            reply = {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32603, "message": type(e).__name__}}
        if reply is not None:
            sys.stdout.buffer.write((json.dumps(reply, ensure_ascii=False) + "\n").encode("utf-8"))
            sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
