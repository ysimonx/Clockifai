# Chronomètres simultanés

`workspaces.max_running_timers` fixe le nombre de chronomètres qu'une personne peut faire tourner en même
temps : 1 par défaut, 0 = illimité. La règle est « le plus récent gagne » : démarrer au-delà de la limite
arrête les plus anciens. L'app l'applique dans sa base locale (hors ligne compris) et le trigger
`time_entries_running_limit` l'applique de nouveau au serveur, qui tranche.

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant App as App Flutter
    participant DB as Base locale
    participant PG as Postgres (trigger 0011)
    participant PS as PowerSync

    U->>App: Démarrer (description, projet, tâche)
    App->>App: règles du workspace (projet ou description obligatoires)
    App->>App: sameTimerTarget, la même tâche tourne-t-elle déjà ?
    alt Même tâche déjà en cours
        App-->>U: message « déjà en cours », rien ne change
    else Nouveau chronomètre
        App->>DB: transaction, arrête les plus anciens au-delà de la limite puis insère le nouveau
        DB-->>App: chronomètre affiché tout de suite
    end
    Note over App,DB: hors ligne, tout s'arrête ici

    App->>PG: upsert de l'entrée (end_at nul)
    PG->>PG: verrou consultatif par (workspace, personne)
    PG->>PG: classe les chronomètres en cours du plus récent au plus ancien
    alt Le nouveau est parmi les plus récents
        PG->>PG: arrête ceux qui dépassent la limite, end_at = début du nouveau
    else Démarré hors ligne et plus ancien que les chronomètres en cours
        PG->>PG: enregistré déjà terminé, end_at = début du plus ancien conservé
    end
    PG->>PG: time_entries_guard refuse un chronomètre démarré pour quelqu'un d'autre (timer_for_others)
    PG->>PS: réplication
    PS-->>DB: état arbitré par le serveur, sur tous les appareils
```

- **Un seul chronomètre par tâche** (même description, projet et tâche) : contrôle côté app seulement
  (`sameTimerTarget`, `alreadyRunningViolation`). La barre du chronomètre, la liste des entrées
  (« Continuer » devient « Arrêter ») et la barre de menus macOS le partagent.
- **Arrêt automatique** : APScheduler arrête toutes les 5 minutes les chronomètres qui dépassent
  `workspaces.auto_stop_after_hours`, à `start_at + limite` (voir `POST /api/jobs/auto-stop`).
- Le **kiosque** pointe la présence : un départ arrête tous les chronomètres en cours de la personne
  (voir `kiosque.md`).
- Avec une limite de 1, le comportement est celui de la migration 0004.

Sources : `app/lib/data/repositories/time_entry_repository.dart` (`start`, `sameTimerTarget`),
`app/lib/features/timer/timer_rules.dart`, `supabase/migrations/0011_parallel_timers.sql`,
`0009_team_managers.sql` (`time_entries_guard`), `services/app/jobs/tasks.py`.
