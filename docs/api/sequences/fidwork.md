# Échanges Fidwork — prévu, non implémenté

> **Statut : en attente** (`plans/02-integration-fidwork.md`). Aucune des routes ci-dessous n'existe encore ;
> elles ne figurent pas dans `openapi.yaml`. Ce diagramme décrit la cible du plan et sera remplacé par le
> fonctionnement réel quand un lot sera livré.

Fidwork reste le registre des interventions, Clockifai le registre du temps. Fidwork pousse son référentiel
et les pointages par son outbox `partner_calls` ; Clockifai renvoie les heures par intervention.

```mermaid
sequenceDiagram
    autonumber
    actor C as Compagnon
    participant FA as App Fidwork
    participant FW as API Fidwork (outbox partner_calls)
    participant F as Flask Clockifai
    participant PG as Postgres Clockifai
    participant PS as PowerSync

    rect rgba(127, 127, 127, 0.1)
    Note over FW,PG: Lot F1, référentiel (prévu)
    FW->>F: POST /api/integrations/fidwork/sync (clé d'intégration du workspace)
    F->>PG: upsert clients, projets, tâches, membres par external_id
    F->>FW: réconciliation horaire (job APScheduler, compte de service)
    end

    rect rgba(127, 127, 127, 0.1)
    Note over C,PS: Lot F2, pointage terrain (prévu)
    C->>FA: scan du QR code de l'échafaudage, work_start
    FA->>FW: événement (heure réelle occurred_at, file hors ligne)
    FW->>F: POST /api/integrations/fidwork/events
    F->>PG: inbox idempotente puis time_entries (source fidwork)
    PG->>PS: réplication vers l'app Clockifai du compagnon
    end

    rect rgba(127, 127, 127, 0.1)
    Note over FA,PG: Lot F3, retour des heures (prévu)
    FA->>FW: page intervention
    FW->>F: GET /api/integrations/fidwork/interventions/{id}/labour
    F->>PG: heures par phase, par personne, nombre de compagnons
    F-->>FW: agrégats
    end
```

Points à reprendre avant la relance (plan 02, § 9) : les écritures sans JWT contournent `time_entries_guard`
(périodes verrouillées, approuvées, facturées), et la limite de chronomètres interagit avec le kiosque et
l'app.
