# Rapport partagé par lien public

Un manager enregistre le rapport affiché (période, filtres, options) et ouvre un lien public en lecture seule
(plan 18, lot 3). La personne qui reçoit le lien n'a pas de compte : Flask calcule la page à chaque ouverture, dans
le fuseau et la langue du créateur, tant que celui-ci est manager actif du workspace.

```mermaid
sequenceDiagram
    autonumber
    actor M as Manager
    participant App as App Flutter
    participant F as Flask
    participant PG as Postgres
    actor C as Destinataire du lien

    M->>App: Rapports, période et filtres, Partager ce rapport
    App->>F: POST /api/reports/saved nom, période, filtres, options, public (JWT)
    F->>F: require_user puis require_workspace manager
    F->>PG: insert clockifai_private.saved_reports, jeton aléatoire
    F-->>App: rapport et public_path
    App-->>M: lien (adresse de l'instance + public_path), Copier le lien

    C->>F: GET /api/reports/public/jeton
    F->>PG: rapport, workspace, créateur encore manager actif, fuseau et langue
    alt Jeton inconnu, retiré, rapport supprimé ou créateur sans droit
        F-->>C: 404
    else Lien valide
        F->>F: période relative calculée aujourd'hui (fuseau du créateur)
        F->>PG: entrées terminées de la période et des filtres (report_rows)
        F->>F: arrondi éventuel, totaux, projets et tâches, détail si demandé
        F-->>C: page HTML sans script (noindex, no-store), ou PDF avec format=pdf
    end

    M->>App: Changer de lien, Fermer le lien ou Supprimer
    App->>F: PUT /api/reports/saved/id new_link ou public faux, ou DELETE
    F->>PG: nouveau jeton, ou jeton retiré
    Note over C,F: l'ancien lien renvoie 404
```
