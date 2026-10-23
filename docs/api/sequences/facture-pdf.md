# Facture : création et PDF

La facture se construit dans l'app comme toute donnée (base locale, puis synchronisation) ; la base calcule
le numéro et les totaux. Seul le PDF passe par Flask.

```mermaid
sequenceDiagram
    autonumber
    actor Mgr as Manager
    participant App as App Flutter
    participant DB as Base locale
    participant PG as Postgres (triggers)
    participant PS as PowerSync
    participant F as Flask

    Mgr->>App: Factures, nouvelle facture (client, période, lignes)
    App->>DB: invoices, invoice_items, invoice_entries
    DB->>PG: upsert (file d'envoi)
    PG->>PG: invoice_items_before_write, montant = quantité x prix unitaire
    PG->>PG: invoice_items_after_write touche la facture
    PG->>PG: invoices_before_write
    Note over PG: numéro PRÉFIXE-année-0001 à l'insertion<br/>(compteur dans clockifai_private.invoice_counters)<br/>échéance, sous-total, remise, TVA, total
    PG->>PS: réplication
    PS-->>DB: numéro et totaux calculés
    Mgr->>App: Télécharger le PDF
    App->>F: GET /api/invoices/{id}/pdf?workspace_id= (JWT)
    F->>F: require_workspace manager
    F->>PG: facture, workspace (raison sociale), client, lignes
    F->>F: gabarit HTML puis WeasyPrint
    F-->>App: application/pdf, numéro.pdf
```

- Une entrée de temps rattachée à une facture non annulée n'est plus modifiable (`invoiced_entry`,
  `time_entries_guard`).
- Facture inconnue ou supprimée : `404`. Un chef d'équipe (rôle `member`) reçoit `403`.

Sources : `app/lib/features/invoices/invoices_page.dart`, `services/app/routes/invoices.py`,
`supabase/migrations/0007_modules.sql`, `0008_private_schema.admin.sql`, `0009_team_managers.sql`.
