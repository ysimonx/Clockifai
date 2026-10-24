# Suivi de Claude Code : jeton, hooks, entrées de l'agent

Le temps de Claude est celui d'un membre « agent », un par pilote (« Claude · Yannick »). Les hooks Claude Code
du poste envoient les événements de chaque session ; Flask en recalcule les entrées de l'agent. Plan :
[10-suivi-claude-code.md](../../../plans/10-suivi-claude-code.md).

```mermaid
sequenceDiagram
    autonumber
    actor P as Pilote
    participant App as App du pilote
    participant CC as Claude Code (hooks du plugin)
    participant F as Flask
    participant GT as GoTrue (API admin)
    participant PG as Postgres
    participant PS as PowerSync

    rect rgba(127, 127, 127, 0.1)
    Note over P,PS: Connexion d'un poste, une fois
    P->>App: Réglages › Intégrations › « Connecter Claude Code »
    App->>F: POST /api/tokens {workspace_id, name} (JWT)
    F->>PG: api_tokens (SHA-256 du jeton)
    F->>PG: verrou consultatif par pilote, compte agent existant ?
    opt premier jeton du pilote
        F->>GT: POST admin/users (kind agent, banni, sans mot de passe)
        GT->>PG: auth.users → handle_new_user : profil seul, pas d'espace personnel
    end
    F->>PG: workspace_members (kind agent, agent_owner_id = pilote)
    PG->>PG: team_scope : (pilote, agent), (chef du pilote, agent)
    F-->>App: {token clk_…, agent_id} (affiché une fois)
    P->>F: claude plugin marketplace add https://…/api/claude/marketplace.json
    F-->>P: marketplace, puis zip du plugin (adresse de l'instance par défaut)
    P->>CC: claude plugin install clockifai@clockifai, jeton saisi (magasin sécurisé)
    end

    rect rgba(127, 127, 127, 0.1)
    Note over P,PS: Une session de travail
    P->>CC: prompt
    CC->>F: POST /api/activity/events (Bearer clk_…) : prompt, outils (1 par minute), Stop, commits
    F->>PG: activity_events (idempotent par id)
    F->>PG: verrou de la session, événements des 7 derniers jours, entrées existantes
    F->>F: agent_clock : intervalles de travail, plages figées par un humain
    F->>PG: agent_entry_write (contrôles de la garde) puis agent_entries
    F->>PG: commits de la session → code_repositories, code_commits
    PG->>PS: réplication logique
    PS-->>App: entrée de l'agent (flux managed_team)
    end

    rect rgba(127, 127, 127, 0.1)
    Note over P,PS: Inactivité
    F->>PG: close_idle_agent_entries (chaque minute)
    F->>PG: entrée fermée à sa dernière activité
    end
```

- Une entrée démarre au premier prompt ; une pause de moins de 10 minutes la prolonge ; passé ce délai, elle se
  ferme à la dernière activité. Une commande longue la prolonge grâce à sa durée (`duration_ms`).
- Le serveur ne touche jamais une entrée supprimée, arrêtée ou dont la fin a été corrigée à la main, ni le projet
  ou la description choisis dans l'app. `agent_entry_write` refuse aussi les entrées verrouillées, facturées,
  antérieures à `lock_entries_before` ou dans une période approuvée.
- Projet d'une entrée : tâche donnée dans la session (`session_task`), sinon projet de l'entrée précédente de la
  session, sinon règle personnelle (`POST /api/activity/rules`), sinon projet du dépôt.
- Un agent désactivé ou retiré par un admin : les événements sont gardés, aucune entrée n'est écrite.
- Le script du plugin n'envoie ni prompt, ni contenu des outils, ni transcription : session, dépôt, branche,
  dossier, durée de l'outil. Il lit la commande d'un outil `Bash` sur le poste pour repérer un `git commit` ; la
  session revendique les commits faits pendant sa commande (D13). Instance injoignable : file d'attente locale,
  renvoyée au prochain envoi réussi.
