# Connexion, inscription et choix du workspace

L'app s'authentifie auprès de GoTrue (Supabase Auth, derrière Kong), puis présente le même JWT à PowerSync.
Toutes les données arrivent ensuite par la synchronisation : l'app ne lit jamais une table par PostgREST.

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant App as App Flutter
    participant DB as Base locale (PowerSync + Drift)
    participant Auth as Kong puis GoTrue
    participant PG as Postgres
    participant PS as PowerSync

    alt Inscription
        App->>Auth: signUp(email, mot de passe, display_name)
        Auth->>PG: insert auth.users
        PG->>PG: trigger on_auth_user_created, handle_new_user()
        Note over PG: profil + workspace « Espace de nom »<br/>workspaces_after_insert ajoute l'auteur en owner<br/>profiles.default_workspace_id = ce workspace
    else Mot de passe
        U->>App: email + mot de passe
        App->>Auth: signInWithPassword
    else Lien magique ou mot de passe oublié
        App->>Auth: signInWithOtp ou resetPasswordForEmail
        Auth-->>U: email (SMTP de GoTrue)
        U->>App: ouvre le lien
    end
    Auth-->>App: session (access_token JWT, refresh_token)
    App->>App: AuthChangeEvent.signedIn, SyncService.connect()
    App->>PS: connexion avec le JWT (fetchCredentials)
    PS->>PS: vérifie signature et audience authenticated
    PS-->>DB: flux auto my_profile, workspace_core, my_time_entries, managed_team
    DB-->>App: watchMemberships, watchProfile
    App->>App: workspace courant = préférence locale, sinon profil, sinon 1re adhésion
    opt Rôle owner, admin ou manager
        App->>PS: syncStream team_data (workspace_id), ttl 7 jours
        PS-->>DB: temps, feuilles et absences de tout le workspace
    end
    opt Changement de workspace
        U->>App: choisit un workspace
        App->>DB: préférence locale + profiles.default_workspace_id
        Note over DB,PG: remonte par la file d'envoi (voir ecriture-hors-ligne.md)
    end
    opt Déconnexion
        App->>Auth: signOut
        App->>DB: disconnectAndClear() efface la base locale
    end
```

- Tant que la première synchronisation n'a livré aucune adhésion, l'app affiche « première synchronisation »
  (`SessionController.waitingForFirstSync`).
- À l'expiration du JWT, PowerSync demande de nouveaux identifiants (`invalidateCredentials` relance
  `refreshSession`).
- La déconnexion efface la base locale : un autre compte peut se connecter sur le même appareil.
- Une sync connectée sans point de contrôle depuis 10 minutes (2 minutes au retour au premier plan) est reconnectée
  par `SyncService.refreshIfStale` : `connect()` remplace la connexion en cours.

Sources : `app/lib/features/auth/login_page.dart`, `app/lib/core/session.dart`,
`app/lib/data/powersync/sync_service.dart`, `app/lib/data/powersync/connector.dart`,
`supabase/migrations/0001_core.sql`, `0002_auth_trigger.admin.sql`, `0006_personal_workspace_name.sql`,
`powersync/sync-config.yaml`.
