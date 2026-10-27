# Assistant « Demander à Clockifai »

L'assistant répond aux questions sur le temps passé (plan 13, lot 12). Flask appelle Claude (API Anthropic) avec des
outils en lecture seule ; Claude ne reçoit que des totaux et le référentiel, jamais les descriptions des entrées. Une
modification demandée revient comme **proposition** : rien n'est écrit côté serveur, l'app l'applique sur sa base
locale si la personne le décide.

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant A as App (panneau ⌘J)
    participant F as Flask /api/assistant
    participant C as API Anthropic (Claude)
    participant PG as Postgres
    participant DB as Base locale

    A->>F: GET /status (une fois) : clé d'API configurée ?
    U->>A: « Mes entrées sans projet d'hier ? »
    A->>F: POST /ask (question, historique)
    F->>PG: périmètre : soi et ses agents, son équipe (chef d'équipe), tout (manager+)
    loop Jusqu'à 8 tours
        F->>C: messages, outils (list_catalog, time_summary, find_entries, propose_update)
        C-->>F: tool_use
        F->>PG: requête en lecture (sans description)
        F-->>C: tool_result
    end
    C-->>F: réponse
    F-->>A: answer, proposals (entrées du périmètre, non verrouillées)
    U->>A: Voir l'aperçu, puis Appliquer
    A->>DB: updateEach (Annuler : restore)
    Note over DB: envoi au serveur par le chemin habituel (ecriture-hors-ligne.md)
```

- Modèle `ASSISTANT_MODEL` (`claude-opus-5-5`), effort `ASSISTANT_EFFORT` (`low`), repli serveur en cas de refus
  (`fallbacks: "default"`) ; 40 questions par heure et par personne.
- Sans `ANTHROPIC_API_KEY`, `/status` répond `enabled: false` et l'app cache l'assistant.

Sources : `services/app/routes/assistant.py`, `services/app/services/assistant.py`, `app/lib/features/assistant/`.
