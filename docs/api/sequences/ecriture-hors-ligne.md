# Écriture hors ligne, envoi et réplication

Toute écriture de l'app (entrée de temps, projet, feuille, absence…) suit ce chemin. L'interface n'attend
jamais le réseau : elle écrit dans la base locale, qui met l'opération dans sa file d'envoi.

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant App as App Flutter (dépôt)
    participant DB as Base locale SQLite
    participant SDK as SDK PowerSync (SupabaseConnector)
    participant REST as Kong puis PostgREST
    participant PG as Postgres (RLS + triggers)
    participant PS as PowerSync
    participant B as Autre appareil

    U->>App: saisit ou modifie une entrée
    App->>DB: insert ou update (Drift, dates en UTC)
    DB->>DB: opération ajoutée à la file d'envoi (ps_crud)
    DB-->>App: les requêtes surveillées se mettent à jour
    Note over App,DB: fonctionne sans réseau

    loop Dès que le réseau est là
        SDK->>DB: getNextCrudTransaction()
        SDK->>REST: put = upsert, patch = update, delete (JWT de l'utilisateur)
        Note right of SDK: updated_at et duration_seconds ne sont jamais envoyés
        REST->>PG: requête soumise à la RLS
        PG->>PG: triggers BEFORE, dans l'ordre alphabétique
        Note over PG: time_entries_a_running_limit, time_entries_before_write<br/>(durée, created_by et updated_by depuis le JWT), time_entries_guard
        alt Accepté
            PG-->>REST: ligne écrite
            REST-->>SDK: 2xx
            SDK->>DB: transaction.complete()
        else Refus définitif (codes 22xxx, 23xxx, 42501)
            PG-->>REST: erreur (RLS, entrée verrouillée, période approuvée…)
            REST-->>SDK: erreur Postgres
            SDK->>DB: transaction.complete(), opération abandonnée
            SDK-->>App: UploadRejection, message affiché
        else Erreur réseau ou serveur
            SDK->>SDK: nouvel essai plus tard
        end
    end

    PG->>PS: réplication logique (publication powersync)
    PS->>PS: évalue les Sync Streams de chaque utilisateur
    PS-->>DB: version serveur de la ligne (valeurs des triggers, ou ligne d'origine après un refus)
    PS-->>B: même ligne si ses flux la couvrent
```

- **Le serveur fait foi.** Après un refus, la synchronisation suivante remet la donnée locale dans l'état du
  serveur. Les règles critiques sont dans les triggers, pas seulement dans l'app.
- Les écritures passent par **upsert** : la politique SELECT doit accepter la nouvelle ligne (migration 0005).
- Les lignes supprimées par soft delete (`deleted_at`) sortent des flux et disparaissent des bases locales.
  `time_entry_tags` est supprimé physiquement.
- Une colonne ajoutée à une table n'est répliquée qu'au prochain changement de ligne (d'où les migrations
  qui « touchent » les lignes).

Sources : `app/lib/data/powersync/connector.dart`, `app/lib/data/powersync/sync_service.dart`,
`app/lib/core/widgets/app_shell.dart`, `supabase/migrations/0003_rls.sql`, `0009_team_managers.sql`,
`0011_parallel_timers.sql`, `powersync/sync-config.yaml`.
