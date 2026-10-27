# Invitation dans un workspace

Seul un admin (owner ou admin) invite. L'invitation passe par Flask, qui a besoin du rôle service pour
créer un compte dans GoTrue : c'est une des rares actions qui exige le réseau.

```mermaid
sequenceDiagram
    autonumber
    actor Adm as Admin
    participant App as App Flutter
    participant F as Flask
    participant PG as Postgres
    participant Auth as GoTrue (API admin)
    participant SMTP as SMTP
    participant PS as PowerSync
    actor I as Personne invitée

    Adm->>App: Équipe, Inviter
    App->>F: GET /api/invitations/options (JWT)
    F-->>App: email = SMTP configuré ?
    App-->>Adm: email, rôle, case « Envoyer l'invitation par email » (cochée si SMTP)
    Adm->>App: Inviter
    App->>F: POST /api/invitations (JWT, send_email)
    F->>F: require_user puis require_workspace admin
    F->>PG: compte existant dans auth.users ?
    alt Nouveau compte
        F->>Auth: admin/generate_link type invite (clé service_role)
        Auth->>PG: insert auth.users
        PG->>PG: handle_new_user, profil + workspace personnel
        Auth-->>F: id + action_link
    else Compte existant
        Note over F: invite_link = null, app_url à transmettre
    end
    F->>PG: upsert workspace_members (status active, rôle demandé, un owner reste owner)
    alt SMTP configuré et send_email
        F->>SMTP: email (lien d'activation, ou accès au workspace)
        SMTP-->>I: email
    else Pas de SMTP, ou email non demandé
        Note over F: emailed = false
    end
    F-->>App: 201 user_id, created, emailed, invite_link, app_url
    App-->>Adm: « email envoyé à … » ou « transmettez ce lien », avec le lien et « Copier le lien »
    PG->>PS: réplication de workspace_members
    PS-->>App: le nouveau membre apparaît dans l'équipe
    I->>Auth: ouvre le lien, session ouverte, redirection vers APP_PUBLIC_URL
    Note over I: puis définit son mot de passe dans Paramètres
```

- Un compte existant est ajouté directement, ou réactivé s'il avait quitté le workspace.
- GoTrue en erreur : `502` avec le détail. Voir `POST /api/invitations` dans `openapi.yaml`.

Sources : `services/app/routes/invitations.py`, `services/app/services/mailer.py`,
`app/lib/features/team/team_page.dart`.
