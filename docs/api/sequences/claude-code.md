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
    CC->>F: SessionStart (hook synchrone) : POST /api/activity/events {session_start}
    F-->>CC: ask_ticket {session: projet}, si le projet est facturé par ticket et la session sans ticket (plan 19)
    opt ticket demandé
        CC->>CC: consigne fixe du plugin ajoutée au contexte : Claude demande le ticket s'il manque au premier message
    end
    P->>CC: prompt
    opt nouveau sujet (D18)
        CC->>CC: Claude appelle set_current_task(nom, étape, ticket), serveur MCP local du plugin, sans réseau
    end
    CC->>CC: au Stop : transcription relue sur le poste depuis la dernière position, usage cumulé par 5 minutes (D17)
    CC->>F: POST /api/activity/events (Bearer clk_…) : prompt, session_task {task_name}, outils (1 par minute), Stop, commits, agent_usage
    F->>PG: activity_events (idempotent par id)
    F->>PG: verrou de la session, événements des 7 derniers jours, entrées existantes
    F->>F: agent_clock : intervalles de travail, coupés au changement de sujet, plages figées par un humain
    F->>PG: tâche du ticket (par sa clé, collante pour la session, ou clé de la branche) et sujet en sous-tâche ; sinon tâche du sujet selon le réglage du pilote : reprise, renommée ou créée (subject_task)
    F->>PG: agent_entry_write (contrôles de la garde) puis agent_entries
    F->>PG: commits de la session → code_repositories, code_commits
    F->>PG: usage de la session → agent_usage par entrée, modèle et effort, coût au tarif de ai_model_prices
    PG->>PS: réplication logique
    PS-->>App: entrée de l'agent et son usage IA (flux managed_team)
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
- Tâche nommée par Claude (D18) : Claude appelle l'outil `set_current_task` du serveur MCP local du plugin ; le
  hook relaie `session_task` `{task_name}` ; le serveur reprend ou crée la tâche de ce nom dans le projet de
  l'entrée, et coupe l'entrée quand le sujet change en cours de route.
- Un agent désactivé ou retiré par un admin : les événements sont gardés, aucune entrée n'est écrite.
- Usage IA (D17) : au `Stop`, au `SubagentStop` et à la fin de la session, le script relit la transcription de la
  session et de ses sous-agents depuis la dernière position lue et n'envoie que des totaux par tranche de 5
  minutes, modèle, effort et vitesse (appels, tokens en entrée, en sortie, écrits en cache à 5 minutes et à 1 heure,
  lus en cache), dédoublonnés par `message.id`. Chaque tranche va à l'entrée qui couvre son heure ; le coût est une
  estimation au tarif public de l'API, en dollars.
- Le script du plugin n'envoie ni prompt, ni contenu des outils, ni texte de la transcription : session, dépôt,
  branche, dossier, durée de l'outil, totaux d'usage. Il lit la commande d'un outil `Bash` sur le poste pour repérer un `git commit` ; la
  session revendique les commits faits pendant sa commande (D13). Instance injoignable : file d'attente locale,
  renvoyée au prochain envoi réussi.
