# Export d'un rapport

Deux chemins depuis l'écran Rapports :
- **CSV local** (`csv-local`) : calculé dans l'app à partir de la base locale, hors ligne, limité aux entrées
  que la personne voit et encadre ;
- **CSV, Excel, PDF serveur** : `GET /api/exports/report`, qui lit Postgres directement (réseau requis).

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant App as App Flutter
    participant DB as Base locale
    participant F as Flask
    participant PG as Postgres

    U->>App: Rapports, période, filtres, format
    alt CSV local
        App->>DB: entrées de la période (watchEntries)
        App->>App: filtre sur ses entrées et celles qu'il encadre (TeamRights)
        App-->>U: fichier enregistré (FileSaver)
    else CSV, XLSX ou PDF serveur
        App->>F: GET /api/exports/report workspace_id, from, to, format, filtres (JWT)
        F->>F: require_user puis require_workspace member
        F->>PG: rôle dans le workspace
        opt Rôle member
            F->>PG: team_scope, personnes encadrées
            F->>F: user_id hors périmètre donne 403, sinon limite à soi et à son équipe
        end
        F->>PG: entrées terminées + personne, client, projet, tâche, tags
        F->>F: CSV (point-virgule, BOM) ou openpyxl ou WeasyPrint
        F-->>App: fichier (Content-Disposition)
        App-->>U: fichier enregistré (FileSaver)
    end
```

- Le connecteur psycopg contourne la RLS : le périmètre est recalculé dans la route (manager+ : tout le
  workspace ; membre : soi et son `team_scope`).
- Paramètres et formats : `GET /api/exports/report` dans `openapi.yaml`.

Sources : `app/lib/features/reports/reports_page.dart` (`_export`), `services/app/routes/exports.py`,
`services/app/services/exporters.py`.
