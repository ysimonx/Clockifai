#!/usr/bin/env python3
"""Serveur MCP local du plugin Clockifai (stdio) : l'outil `set_current_task`, par lequel Claude nomme la tâche du
sujet en cours (plans/10-suivi-claude-code.md, D18).

N'appelle jamais le réseau et ne lit aucun réglage : il renvoie le nom reçu. Le hook (PostToolUse) le relaie à
Clockifai avec le jeton et l'identifiant de session, que lui seul connaît : un serveur MCP ne reçoit pas la session.
JSON-RPC ligne par ligne sur stdin et stdout ; Python 3.9 et bibliothèque standard seulement.
"""

from __future__ import annotations

import json
import sys

NAME_MAX = 80  # comme le serveur (TASK_NAME_MAX)
TOOL = "set_current_task"

INSTRUCTIONS = (
    "Clockifai mesure le temps de cette session de Claude Code et le range par tâche. Dès que tu sais sur quoi "
    f"porte le travail, même une vérification rapide, appelle {TOOL} avec un nom de tâche court (3 à 6 mots, dans "
    "la langue de l'utilisateur), avant de commencer ; pas pour une simple salutation. Garde ce nom tant que "
    "l'utilisateur précise ou poursuit le même sujet : un nom plus précis donné juste après renomme la tâche. Ne "
    "donne un nouveau nom que s'il passe à un autre sujet, et reprends exactement le même nom pour un sujet déjà "
    "nommé. Pas de nom de personne ni de donnée confidentielle. Inutile de le signaler à l'utilisateur."
)

TOOLS = [{
    "name": TOOL,
    "title": "Nommer la tâche Clockifai",
    "description": (
        "Nomme la tâche Clockifai du sujet en cours, au début de chaque nouveau sujet : le temps de cette session "
        "y est rangé, dans le projet du dépôt. Même nom, même tâche."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {"name": {"type": "string", "description": "Nom court de la tâche (3 à 6 mots)",
                                "maxLength": NAME_MAX}},
        "required": ["name"],
    },
}]


def text(message: str, error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": message}], "isError": error}


def handle(msg: dict) -> dict | None:
    """Réponse à une requête JSON-RPC ; None pour une notification (sans `id`)."""
    if "id" not in msg:
        return None
    method, params = msg.get("method"), msg.get("params") or {}
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
        name = " ".join(str((params.get("arguments") or {}).get("name") or "").split())[:NAME_MAX]
        result = text(f"Tâche « {name} » notée : le temps de cette session y est rangé.") if name else text(
            "Nom de tâche vide : rien n'est changé.", error=True)
    else:
        return {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": f"unknown method {method}"}}
    return {"jsonrpc": "2.0", "id": msg["id"], "result": result}


def main() -> None:
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        reply = handle(msg) if isinstance(msg, dict) else None
        if reply is not None:
            sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
