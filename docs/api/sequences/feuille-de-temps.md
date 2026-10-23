# Soumission et approbation d'une feuille de temps

La soumission est une ligne de `timesheet_submissions` (personne, période `period_start` → `period_end`,
statut). Les droits et les effets sont dans les triggers ; l'app ne fait qu'écrire la ligne dans sa base
locale.

```mermaid
sequenceDiagram
    autonumber
    actor M as Membre
    participant A as App du membre
    participant PG as Postgres (RLS + triggers)
    participant PS as PowerSync
    participant C as App du chef d'équipe ou du manager
    actor D as Décideur

    M->>A: Soumettre la semaine
    A->>A: insert, ou remise en submitted d'une soumission existante
    A->>PG: upsert (file d'envoi)
    PG->>PG: timesheet_submissions_guard, une soumission commence en submitted
    PG->>PS: réplication
    PS-->>C: flux managed_team (chef d'équipe) ou team_data (manager+)
    D->>C: Approuver ou refuser (note facultative)
    C->>PG: update status (file d'envoi)
    PG->>PG: RLS manages() et guard, decided_by et decided_at posés
    alt Approuvée
        PG->>PG: timesheet_submissions_apply
        Note over PG: set_config clockifai.bypass_guard = on<br/>locked = true sur les entrées de la période<br/>(jour local de la personne), puis bypass retiré
    else Refusée
        PG->>PG: statut rejected, entrées inchangées
    end
    PG->>PS: réplication
    PS-->>A: statut et entrées verrouillées
    opt Réouverture
        D->>C: Rouvrir une feuille approuvée (note facultative)
        C->>PG: update status = rejected
        PG->>PG: timesheet_submissions_apply déverrouille les entrées
    end
```

- **Qui décide** : manager+ pour tout le workspace ; un chef d'équipe pour les personnes de son périmètre
  (`team_scope`), dont il est lui-même exclu. Le membre ne peut que soumettre ou retirer (`withdrawn`), et
  ne peut plus toucher une feuille approuvée.
- **Période approuvée** : `time_entries_guard` refuse d'y ajouter ou d'y déplacer une entrée
  (`approved_period`), et toute modification d'une entrée verrouillée (`locked_entry`), sauf pour un admin.
  L'app prévient avant, hors ligne compris (`isDayApproved`).
- Période et propriétaire d'une soumission sont immuables.

Sources : `app/lib/data/repositories/modules_repository.dart` (`submitPeriod`, `decideSubmission`),
`app/lib/features/approvals/`, `supabase/migrations/0007_modules.sql` (`timesheet_submissions_apply`,
`guard_bypassed`), `0009_team_managers.sql` (`timesheet_submissions_guard`, `time_entries_guard`).
