# Journal du jour : propositions et traces

La page « Aujourd'hui » propose la journée à partir de ce que Clockifai sait déjà. Tout est calculé sur l'appareil
(`features/today/day_plan.dart`, `planDay`), hors ligne compris ; seules les **traces** (agenda, commits) demandent
le serveur, et la journée se propose sans elles quand il est injoignable. Rien n'est enregistré avant que la
personne confirme.

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant A as Page « Aujourd'hui » (Flutter)
    participant DB as Base locale
    participant F as Flask /api/traces
    participant PG as Postgres
    participant I as Agenda (iCal, https)

    A->>DB: ses entrées (5 semaines), sessions de son agent Claude, planning
    A->>F: GET /api/traces (jour affiché), toutes les 5 minutes pour aujourd'hui
    F->>PG: ses commits (code_commits, auteur reconnu) et l'adresse de son agenda (clockifai_private)
    opt Agenda relié
        F->>I: lecture (https public, 5 minutes de cache)
        I-->>F: événements, récurrences dépliées
    end
    F-->>A: events (heure, titre), commits (dépôt, projet du dépôt)
    A->>A: planDay : journée type (profil, sinon historique), créneaux libres,<br/>propositions Claude > agenda > commits > habitudes > planning
    A-->>U: frise : Vous, Claude, Traces ; « Tout confirmer » ou bloc par bloc
    U->>A: Confirmer
    A->>DB: entrées créées (Annuler les retire)
    Note over DB: envoi au serveur par le chemin habituel (ecriture-hors-ligne.md)
```

- Projet d'une réunion : deviné d'après son titre, comme la saisie express (`parseQuick`). Projet d'une série de
  commits : celui du dépôt. Les événements d'une journée entière, annulés ou hors de la journée de travail sont
  ignorés.
- Une proposition ignorée est mémorisée sur l'appareil par sa clé (`cal:…`, `git:…`, `habit:…`) et ne revient pas.

Sources : `app/lib/features/today/`, `services/app/routes/traces.py`, `services/app/services/calendar.py`,
`plans/13-ux-moderne.md`.
