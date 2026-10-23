# Demande et décision d'absence

Une demande est une ligne de `time_off_requests` rattachée à une politique (`time_off_policies` : congés,
RTT…). La politique dit si une approbation est nécessaire (`requires_approval`) et qui décide
(`approvers`).

```mermaid
sequenceDiagram
    autonumber
    actor M as Membre
    participant A as App du membre
    participant PG as Postgres (RLS + triggers)
    participant PS as PowerSync
    participant C as App du décideur
    actor D as Décideur

    M->>A: Demander (politique, dates, demi-journée, note)
    A->>A: insert pending dans la base locale
    A->>PG: upsert (file d'envoi)
    PG->>PG: time_off_requests_guard
    alt Politique sans approbation
        PG->>PG: statut forcé à approved
    else Approbation requise
        PG->>PG: reste pending
    end
    PG->>PS: réplication
    PS-->>A: statut définitif
    PS-->>C: flux managed_team (chef d'équipe) ou team_data (manager+)
    D->>C: Approuver ou refuser
    C->>PG: update status
    PG->>PG: RLS et guard via can_decide_time_off(), decided_by et decided_at posés
    PG->>PS: réplication
    PS-->>A: décision
    opt Annulation
        M->>A: Annuler
        A->>PG: status = cancelled
    end
```

- **Qui décide** : manager+ toujours ; un chef d'équipe pour son périmètre si la politique a
  `approvers = managers_and_team_managers`.
- Le demandeur peut modifier une demande tant qu'elle est en attente, ou l'annuler ; il ne peut pas
  l'approuver lui-même (`insufficient_privilege`).
- Les jours sans heure (`start_date`, `end_date`) sont du texte `yyyy-MM-dd` côté app.

Sources : `app/lib/data/repositories/modules_repository.dart` (`requestTimeOff`, `decideRequest`,
`cancelRequest`), `app/lib/features/time_off/time_off_page.dart`,
`supabase/migrations/0009_team_managers.sql` (`can_decide_time_off`, `time_off_requests_guard`).
