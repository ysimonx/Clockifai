# Kiosque : pointage par PIN sur un appareil partagé

Une tablette à l'entrée de l'atelier ou de la base vie, ouverte sur la route `/kiosk` de l'app, sans compte
utilisateur. Elle s'authentifie par un jeton d'appareil ; chaque personne pointe avec son PIN.
Le kiosque exige le réseau : il parle à Flask, pas à la base locale.

```mermaid
sequenceDiagram
    autonumber
    actor Adm as Admin
    participant AppA as App de l'admin
    actor M as Membre
    participant AppM as App du membre
    participant REST as Kong puis PostgREST
    participant K as Tablette (route /kiosk)
    participant F as Flask
    participant PG as Postgres

    rect rgba(127, 127, 127, 0.1)
    Note over Adm,PG: Mise en place, une fois
    Adm->>AppA: Paramètres, Kiosque, Ajouter un appareil
    AppA->>F: POST /api/kiosk/devices (JWT admin)
    F->>PG: insert kiosk_devices (hachage SHA-256 du jeton)
    F-->>AppA: jeton kio_… affiché une seule fois
    Adm->>K: saisit le jeton (gardé dans les préférences de la tablette)
    M->>AppM: Paramètres, PIN du kiosque (4 à 8 chiffres)
    AppM->>REST: rpc set_kiosk_pin (JWT du membre)
    REST->>PG: hachage bcrypt dans clockifai_private.member_pins
    end

    loop Toutes les 20 secondes
        K->>F: GET /api/kiosk/state (X-Kiosk-Token)
        F->>PG: last_seen_at, membres, chronomètre en cours, projets
        F-->>K: liste des personnes et de leur état
    end

    M->>K: touche son nom, tape son PIN (et un projet à l'arrivée)
    K->>F: POST /api/kiosk/punch user_id, pin, project_id
    F->>F: bloqué ? 5 échecs donnent 5 minutes de blocage (429)
    F->>PG: compare le PIN au hachage bcrypt
    alt PIN faux
        F->>F: compte un échec pour (appareil, membre)
        F-->>K: 403 wrong PIN
    else Un chronomètre tourne
        F->>PG: end_at = now() sur tous ses chronomètres en cours
        F-->>K: action out
    else Aucun chronomètre
        F->>PG: insert time_entries en cours (projet, facturable, taux)
        PG->>PG: trigger de limite de chronomètres
        F-->>K: action in
    end
    PG-->>AppM: réplication PowerSync, l'entrée apparaît dans l'app du membre
```

- Les écritures de Flask n'ont pas de JWT : `created_by` reste vide et `time_entries_guard` ne s'applique pas
  (pas de contrôle de verrouillage ni de période approuvée sur un pointage kiosque).
- Le compteur d'échecs est en mémoire, dans l'unique worker gunicorn ; il repart de zéro au redémarrage.
- Révoquer l'appareil (`DELETE /api/kiosk/devices/{id}`) rend le jeton inutilisable immédiatement.
- Une personne sans PIN ne peut pas pointer : la tablette le signale avant d'appeler Flask (`has_pin`).

Sources : `services/app/routes/kiosk.py`, `app/lib/features/kiosk/kiosk_page.dart`,
`app/lib/features/settings/settings_page.dart`, `supabase/migrations/0008_private_schema.admin.sql`.
