# CLAUDE.md

Guide pour Claude Code dans le dépôt Clockifai (clone libre et auto-hébergé de Clockify).

## Vue d'ensemble

| Dossier | Stack | Rôle |
|---|---|---|
| `app/` | Flutter 3.47 (fvm), Drift sur PowerSync, Provider + ChangeNotifier, GetIt, go_router, l10n ARB FR/EN | App unique web / iOS / Android, offline-first |
| `services/` | Python 3.12, Flask, psycopg 3, APScheduler, openpyxl, WeasyPrint (uv) | Exports, jobs planifiés, futurs endpoints (invitations, kiosque, intégrations) |
| `supabase/migrations/` | SQL Postgres 17 | Schéma, triggers, RLS, publication PowerSync |
| `supabase/docker/` | Copie épinglée du `docker/` officiel Supabase v1.26.08 | **Ne pas modifier** (sauf montée de version) |
| `powersync/` | `service.yaml`, `sync-config.yaml` (Sync Streams, édition 3) | Moteur de sync |
| `deploy/` | Docker Compose, Caddy, scripts | Tout le backend en conteneurs |
| `plans/` | Markdown | Plans validés ; à tenir à jour avec les décisions prises |

## Commandes

Toujours **fvm** pour Flutter et **uv** pour Python. Les cibles du `Makefile` font foi.

```bash
make env / make up / make down / make logs SERVICE=powersync / make migrate / make psql
make seed EMAIL=vous@exemple.fr   # données de démo dans le workspace d'un compte existant
make services-test        # cd services && uv run pytest -q
make test-integration     # tests contre la pile Docker locale (INTEGRATION=1)
make app-config           # app/config/local.json depuis deploy/.env
make app-get              # fvm flutter pub get + powersync:setup_web + build_runner
make app-gen              # fvm dart run build_runner build (Drift, après modif des tables)
make app-web              # fvm flutter run -d chrome --web-port 3000
make app-analyze / make app-test
```

## Règles d'architecture

### Données et synchronisation
- **L'UI ne parle jamais à Supabase pour les données** : elle lit/écrit la base locale via les dépôts de `app/lib/data/repositories/`. PowerSync envoie la file locale au serveur (`SupabaseConnector.uploadData`, upsert PostgREST) et redescend les changements.
- **Trois endroits à garder alignés** pour toute colonne synchronisée : la migration SQL, `app/lib/data/powersync/schema.dart`, et la table Drift dans `app/lib/data/drift/database.dart` (puis `make app-gen`). Si la table doit être synchronisée, l'ajouter aussi dans `powersync/sync-config.yaml`.
- Tables Drift posées sur les **vues** PowerSync : pas de `withDefault` (utiliser `clientDefault`), pas d'upsert / `insertOnConflictUpdate` / `RETURNING`, pas de migrations Drift.
- Dates : écrites en **UTC** ; comparaisons et tris via `epoch()` / `unixepoch()` car le serveur et le client n'emploient pas le même format ISO texte.
- Suppressions : **soft delete** (`deleted_at`) pour les tables métier ; les Sync Streams filtrent `deleted_at IS NULL`. `time_entry_tags` est supprimé physiquement.
- Booléens : `integer` 0/1 côté SQLite, acceptés tels quels par Postgres.
- Après modification de `powersync/sync-config.yaml` : `docker compose … restart powersync`. Les listes littérales `IN ('a','b')` sont refusées dans les sous-requêtes des streams.
- Quatre flux : `workspace_core` (référentiel, auto), `my_time_entries` (données personnelles, auto), `team_data` (tout le workspace, souscrit par `SessionController` pour les managers), `managed_team` (temps, feuilles et absences des collaborateurs d'un chef d'équipe, auto, jointure sur `team_scope` par `(workspace_id, user_id)`).
- Une colonne non nulle ajoutée à une table existante n'est répliquée qu'au prochain changement de ligne : la migration « touche » les lignes (`update … set col = col`) et la colonne Drift reste nullable.
- Dates sans heure (`period_start`, `start_date`, `date`…) : texte `yyyy-MM-dd` côté client (`dayKey()` / `parseDay()` dans `modules_repository.dart`).
- Le worker web PowerSync est **compilé depuis l'app** (`make app-web-assets`), pas téléchargé : le worker publié peut être en décalage de version avec `sqlite_async`.

### Base de données
- Migrations **append-only** numérotées dans `supabase/migrations/` ; ne jamais réécrire une migration déjà appliquée, en ajouter une nouvelle. `*.admin.sql` s'exécute en `supabase_admin` (rôles, publication, `auth.users`), le reste en `postgres`. Suivi : `clockifai_meta.schema_migrations`.
- Toute nouvelle table métier : `workspace_id`, `created_at`, `updated_at` (trigger `set_updated_at`), `deleted_at`, RLS activée avec les helpers `is_member` / `is_manager` / `is_admin`.
- Chefs d'équipe (migration 0009, `plans/03-saisie-pour-autrui.md`) : ce n'est pas un rôle. Le périmètre est matérialisé dans `team_scope`, recalculé par trigger (`refresh_team_scope`) depuis `team_manager_assignments` et `user_groups`. Droits : `manages()` (lecture), `can_edit_others_time()` (saisie pour autrui selon `workspaces.time_for_others`), `can_decide_time_off()` (selon `time_off_policies.approvers`). `time_entries.created_by` / `updated_by` sont posés par trigger depuis le JWT. Côté app, `TeamRights` (`core/team_rights.dart`) reproduit ces règles pour l'affichage.
- Les écritures client passent par **upsert** : la politique SELECT doit accepter la nouvelle ligne (cf. migration 0005).
- Règles métier critiques côté serveur (triggers), pas seulement dans l'app : verrouillage des entrées, limite de chronomètres simultanés (`workspaces.max_running_timers`, trigger 0011, « le plus récent gagne »), garde des rôles, approbations, absences, numérotation et totaux de facture.
- Un trigger qui doit modifier des entrées sans passer la garde pose `set_config('clockifai.bypass_guard', 'on', true)` (voir `timesheet_submissions_apply`).
- Données sensibles (hash de PIN, compteurs) dans le schéma `clockifai_private` : hors API, hors réplication.

### Flask
- Authentifie le JWT Supabase (`auth.py`), puis vérifie explicitement l'appartenance au workspace (`require_workspace`) : la connexion psycopg contourne la RLS.
- Un seul worker gunicorn (le scheduler APScheduler tourne dans le process).
- Blueprints : `exports`, `invitations` (lien renvoyé si pas de SMTP), `kiosk` (jeton d'appareil `X-Kiosk-Token`, anti force brute en mémoire), `invoices` (PDF), `jobs`.

### Flutter
- Organisation par fonctionnalité dans `lib/features/<feature>/` ; transverse dans `lib/core/`.
- État : `SessionController` (utilisateur, workspace courant, rôle, statut de sync) et `CatalogController` (référentiel en mémoire) fournis par Provider ; dépôts et `SyncService` via GetIt (`core/di.dart`).
- Tous les textes passent par l'ARB (`lib/l10n/app_fr.arb` = modèle, `app_en.arb`) ; `context.l10n`.
- Les droits affichés suivent `session.isManager` / `isAdmin`, mais la RLS reste la seule vraie barrière.

## Tests
- `services/tests/` : unitaires sans base ; `services/tests/integration/` : contre la pile Docker (inscription, RLS, rôles, chronomètres simultanés, verrouillage, upsert du connecteur, exports, chefs d'équipe).
- `app/test/` : parsing des durées, dépôts (entrées, modules, équipes), `TeamRights`, sur base Drift en mémoire.
- Parcours navigateur (Playwright, hors dépôt) : activer l'arbre d'accessibilité Flutter en cliquant `flt-semantics-placeholder`, puis cliquer un champ et taper au clavier (`fill` ne suffit pas).

## Ports locaux
Kong/Supabase 8000, PowerSync 8080, Flask 5050 (5000 est pris par AirPlay sur macOS), Postgres via Supavisor 5432, app web 3000 (`flutter run`), build de démo 3100.

## Vidéos de démonstration
`demo/` (Node, Playwright, ffmpeg embarqué) : `node record.mjs [n]`, données recréées par `prepare-demo.sh`
(comptes `*@demo.clockifai.fr`). Après une évolution d'interface, rejouer `DEMO_FAST=1 node record.mjs n`
(répétition sans vidéo, captures `demo/out/echec-*.png`) et ajuster le scénario dans `demo/videos/`.
Les éléments Flutter sont repérés par leur étiquette d'accessibilité ou leur texte propre (`find()` dans `demo/lib/helpers.mjs`).

## Interfaçage Fidwork
Plan dans `plans/02-integration-fidwork.md` : Fidwork pousse son référentiel (sites, interventions, compagnons) et les pointages `work_start` / `work_stop` via son outbox `partner_calls` ; Clockifai renvoie les heures par intervention.
