# Clockifai — clone libre et auto-hébergé de Clockify (web + mobile)

## Contexte

Objectif : disposer d'un équivalent de Clockify (suivi du temps, projets, rapports, équipe,
congés, planning, approbations, facturation) **gratuit, auto-hébergeable** (VPS OVH ou
Scaleway, un seul `docker compose up`), avec **une seule base de code Flutter** pour le web,
iOS et Android, utilisable **hors connexion**.

Le dossier `/Users/ysimonx/Developpement/Clockifai` est vide : projet greenfield.
Les conventions sont reprises des projets existants (`fidwork/app`, `coinalert`) :
Flutter + Drift + go_router + GetIt + Provider, Python/Flask + uv + gunicorn + Docker.

## Décisions d'architecture (validées)

| Sujet | Choix | Pourquoi |
|---|---|---|
| Backend données/auth | **Supabase auto-hébergé** (Postgres 17, GoTrue, PostgREST, Realtime, Storage, Studio) via le `docker/` officiel | Auth, API REST et RLS multi-tenant « gratuits », Studio pour administrer |
| Multi-tenant | `workspace_id` sur toutes les tables + **Row Level Security** | Flutter parle directement à Supabase sans API intermédiaire |
| Offline-first | **PowerSync Open Edition auto-hébergé** (`journeyapps/powersync-service`, licence FSL, gratuit) + SDK Flutter `powersync` (Apache-2) + `drift_sqlite_async` | Moteur de sync éprouvé (sync rules YAML, file d'upload, reprise, web/iOS/Android) au lieu d'une file maison |
| Logique « hors Supabase » | **Flask léger** (`services/`) : exports PDF/Excel/CSV, factures PDF, jobs planifiés, endpoints kiosque | Python, ce que vous maîtrisez ; reste optionnel pour la phase 1 |
| Client | **Flutter 3.41** (fvm), une seule base web + iOS + Android | Habitude fidwork/coinalert |
| Reverse proxy | **Caddy** (HTTPS automatique) | Un fichier de config, zéro certbot |
| Hébergement | **Indifférent** : VPS OVH, Scaleway, ou machine chez vous (mini-PC, NAS, Raspberry 5 8 Go). Prérequis : Linux x86_64 ou arm64, 4 vCPU / 8 Go RAM mini, Docker Compose v2 | Tout tourne dans un seul `docker compose` ; aucun service cloud propriétaire |

Alternative écartée : sync maison Drift + outbox (comme fidwork) — trop de code à maintenir.

## Arborescence du monorepo

```
Clockifai/
├── CLAUDE.md                      # guide du dépôt (stack, commandes, règles)
├── Makefile                       # up/down/logs/migrate/build-web/backup
├── deploy/
│   ├── docker-compose.yml         # inclut supabase/docker + powersync + services + caddy
│   ├── Caddyfile
│   ├── .env.example               # secrets à générer (JWT, anon/service keys, SMTP…)
│   └── backup.sh                  # pg_dump quotidien (cron) vers volume/S3-compatible
├── supabase/
│   ├── docker/                    # copie épinglée du docker/ officiel (version taguée)
│   ├── migrations/                # 0001_core.sql, 0002_rls.sql, 0003_team.sql …
│   └── seed.sql                   # données de démo (workspace, projets, entrées)
├── powersync/
│   ├── service.yaml               # connexion Postgres (réplication), storage, auth Supabase
│   └── sync-config.yaml           # Sync Streams par workspace / utilisateur
├── services/                      # Flask
│   ├── app/{__init__.py, auth.py, routes/, services/, jobs/, templates/}
│   ├── tests/
│   ├── pyproject.toml, Dockerfile, gunicorn.conf.py
├── app/                           # Flutter
│   ├── .fvmrc, pubspec.yaml, l10n.yaml
│   ├── lib/
│   │   ├── main.dart, app.dart, router.dart, di.dart
│   │   ├── core/        # thème, i18n, utils, widgets communs, responsive shell
│   │   ├── data/
│   │   │   ├── powersync/   # schema.dart, database.dart, supabase_connector.dart
│   │   │   ├── drift/       # tables Drift miroir du schéma PowerSync, DAOs
│   │   │   └── repositories/
│   │   └── features/
│   │       ├── auth/, workspace/, timer/, time_entries/, timesheet/, calendar/
│   │       ├── projects/, clients/, tags/, reports/, team/, settings/
│   │       ├── time_off/, schedule/, approvals/, kiosk/, invoices/
│   ├── web/  (sqlite3.wasm, powersync_db.worker.js, powersync_sync.worker.js)
│   └── test/
└── plans/                         # ce plan + plan d'interfaçage Fidwork
```

## Modèle de données (Postgres, `supabase/migrations/`)

Conventions : PK `uuid` générées côté client (`gen_random_uuid()` par défaut), `workspace_id`
sur chaque table métier, `created_at`, `updated_at` (trigger serveur), `deleted_at` (soft delete
pour que PowerSync propage les suppressions proprement).

**Phase 1 – cœur**
- `profiles` (id = auth.users.id, display_name, avatar_url, timezone, locale, default_workspace_id)
- `workspaces` (name, currency, week_start, time_format, rounding, created_by)
- `workspace_members` (workspace_id, user_id, role `owner|admin|manager|member`, hourly_rate_cents, cost_rate_cents, kiosk_pin_hash, status `active|inactive`) — unique (workspace_id, user_id)
- `clients` (name, note, currency_override, archived)
- `projects` (client_id, name, color, billable_default, hourly_rate_cents, budget_hours/amount, is_public, archived)
- `tasks` (project_id, name, estimate_seconds, status)
- `tags` (name, color, archived)
- `time_entries` (user_id, project_id?, task_id?, description, start_at timestamptz, end_at timestamptz NULL = timer en cours, duration_seconds généré, billable, hourly_rate_cents snapshot, locked bool)
  - index partiel unique : **un seul timer en cours par (workspace_id, user_id)** `WHERE end_at IS NULL AND deleted_at IS NULL`
- `time_entry_tags` (time_entry_id, tag_id)

**Phase 3 – équipe** : `invitations` (email, role, token, expires_at, accepted_at), `workspace_settings` (lock_entries_before date, require_project, require_description, allowed_ips…), `project_members` (accès projets privés, taux par projet/membre).

**Phase 4 – modules** : `timesheets` (user_id, period_start/end, status `draft|submitted|approved|rejected`, approved_by, note), `time_off_policies`, `time_off_balances`, `time_off_requests` (status, approver), `holidays`, `schedule_assignments` (user_id, project_id, start/end, hours_per_day, note), `kiosk_devices` (name, token_hash, workspace_id), `kiosk_sessions`, `invoices` (client_id, number, issue/due dates, status, currency, totals), `invoice_items`, `audit_log`.

**Fonctions/triggers SQL**
- `set_updated_at()` : `updated_at = now()` serveur (ordre de sync monotone).
- `handle_new_user()` sur `auth.users` : crée `profiles` + un workspace personnel + membership owner.
- `guard_locked_entry()` : refuse UPDATE/DELETE d'une entrée verrouillée ou dans un timesheet approuvé sauf rôle admin/owner.
- Vues/RPC de rapports (`report_summary(workspace_id, from, to, group_by, filters)`, `report_detailed(...)`) en SECURITY INVOKER pour que Flutter (en ligne) et Flask utilisent la même logique.

**RLS (pattern)**
- Helpers : `is_member(wid)`, `member_role(wid)`, `is_manager_or_above(wid)`.
- `time_entries` : SELECT si propriétaire, ou manager+ du workspace, ou projet `is_public` ; INSERT/UPDATE/DELETE si propriétaire (et non verrouillée) ou admin+.
- `projects/clients/tags/settings` : SELECT tout membre ; écriture admin+ (manager peut créer projets si setting).
- `workspace_members/invitations` : lecture membres ; écriture admin+ ; chacun peut mettre à jour son propre `kiosk_pin_hash`.
- Modules phase 4 : demandes de congé/timesheets écrites par le propriétaire, approuvées par manager+.

## Synchronisation PowerSync

- **Service** : conteneur `journeyapps/powersync-service` dans le compose. Postgres Supabase déjà en `wal_level=logical` ; créer un rôle `powersync_role` REPLICATION + `CREATE PUBLICATION powersync FOR TABLE …` (migration). Storage des buckets : **Postgres** (base séparée `powersync_storage` sur la même instance) pour éviter MongoDB.
- **Auth** : `client_auth: { supabase: true, supabase_jwt_secret: ${JWT_SECRET} }` → le JWT Supabase de l'utilisateur est accepté tel quel.
- **Sync Streams** (`sync-config.yaml`, édition 3) : flux `workspace_core` filtré par `workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.user_id())` → projets, clients, tags, tâches, membres, settings, et les `time_entries` visibles (propres entrées pour tous + toutes les entrées pour manager+ via un second bucket `team_entries[]` conditionné au rôle). Filtre `deleted_at IS NULL` côté bucket, ou on synchronise la colonne et on filtre dans l'app (recommandé : synchroniser, filtrer localement, purger via job Flask).
- **Client Flutter** : `PowerSyncDatabase` + `Schema` Dart miroir des tables, Drift branché dessus via `drift_sqlite_async` (DAOs typés, streams réactifs pour l'UI). `SupabaseConnector implements PowerSyncBackendConnector` : `fetchCredentials()` renvoie le JWT Supabase, `uploadData()` rejoue chaque transaction CRUD en `upsert/update/delete` PostgREST ; erreurs fatales (RLS 42501, contraintes 23xxx, 22xxx) → transaction abandonnée + toast à l'utilisateur ; erreurs réseau → retry automatique.
- **Conflits** : dernier écrit gagne côté serveur ; le `updated_at` serveur est la vérité (PowerSync renvoie la ligne finale).
- **Timer** : un timer = `time_entry` avec `end_at NULL`. L'UI compte à partir de `start_at` (pas de compteur accumulé). Démarrer un timer = `INSERT` ; l'index partiel unique refuse un second timer : le connecteur gère `23505` en arrêtant l'ancien (règle « le plus récent gagne ») — ou mieux, avant tout start, l'app ferme localement tout timer ouvert. Stop sur un autre appareil = `UPDATE end_at`, propagé par la sync.
- **Web** : `powersync` supporte Flutter web ; copier `sqlite3.wasm` + workers PowerSync dans `app/web/` (script `app/tool/setup_web.sh`).
- **Rapports hors ligne** : calculés depuis la base locale pour ses propres entrées ; rapports équipe/exports exigent le réseau.

## Application Flutter

- **État** : Provider + ChangeNotifier (comme vos projets) pour l'état d'écran ; données via streams Drift (`watch`) → UI réactive sans couche supplémentaire. GetIt pour l'injection (`PowerSyncDatabase`, `SupabaseClient`, repositories, `WorkspaceContext`).
- **Navigation** : go_router + `ShellRoute` responsive : barre latérale ≥ 900 px (web/desktop), barre inférieure + tiroir sur mobile. Barre de timer persistante en haut du shell.
- **Auth** : `supabase_flutter` (email+mot de passe, magic link ; OAuth Google/Microsoft possible plus tard via GoTrue). Deep link `clockifai://login-callback` (iOS/Android), redirection `/auth/callback` sur le web. Session persistée par le SDK ; workspace courant dans `shared_preferences`.
- **Packages clés** : supabase_flutter, powersync, drift, drift_sqlite_async, sqlite_async, go_router, get_it, provider, intl + flutter_localizations (ARB FR/EN dès le départ), connectivity_plus, uuid, fl_chart (rapports), flutter_local_notifications (timer en cours), app_links (deep links), file_saver / printing (téléchargement d'exports), shared_preferences, logger.
- **Écrans par phase**
  1. Login / inscription, Timer + liste des entrées groupées par jour (édition inline), Saisie manuelle, Timesheet hebdo (grille projets × jours), Projets, Clients, Tags, Tâches, Paramètres workspace de base, sélecteur de workspace.
  2. Rapports résumé (par projet/client/utilisateur/tag/période, graphes) et détaillé, filtres, export CSV local + PDF/Excel via Flask.
  3. Équipe (membres, rôles, taux), invitations par email, activité équipe (qui chronomètre quoi, via Realtime), verrouillage des entrées, projets privés.
  4. Calendrier semaine/jour, Mode kiosque (plein écran, pavé PIN), Congés (politiques, soldes, demandes, approbation), Planning (assignations), Approbation des timesheets, Factures (génération depuis entrées facturables, PDF).
- **Tests** : unitaires du connecteur (client Supabase factice), Drift/PowerSync en mémoire, widget tests du timer et du timesheet.

## Service Flask (`services/`)

- App factory, blueprints : `health`, `exports` (`POST /api/exports/report` → CSV/XLSX/PDF), `invoices` (`POST /api/invoices/{id}/pdf`), `kiosk` (`POST /api/kiosk/clock` : token appareil + PIN → start/stop d'entrée via service role), `jobs` (déclenchement manuel).
- Auth : vérification du JWT Supabase (PyJWT, HS256, secret partagé) ; vérification explicite de l'appartenance au workspace demandé puis accès Postgres en service role (psycopg 3) en appelant les RPC de rapport.
- Exports : `openpyxl` (Excel), `csv`, **WeasyPrint** (PDF depuis templates Jinja2 HTML ; image Docker un peu plus lourde mais rendu propre pour rapports et factures).
- Jobs APScheduler : auto-stop des timers > N heures (setting workspace), rappels de saisie (SMTP partagé avec GoTrue), verrouillage périodique, purge des `deleted_at` anciens, rappel d'approbation.
- Dockerfile Python 3.12 slim, gunicorn, config par variables d'environnement.

## Déploiement : 100 % conteneurs Docker

**Principe** : le backend complet = un seul `docker compose up -d` dans `deploy/`. Aucune
dépendance à un hébergeur ; seul prérequis sur la machine : Docker + Compose v2.
Les données vivent dans des volumes nommés, donc « déménager » = `backup.sh` → copier
`.env` → `docker compose up` ailleurs → restaurer.

| Conteneur | Image | Rôle | Volume | Exposé |
|---|---|---|---|---|
| `db` | `supabase/postgres` (épinglé) | Postgres 17 + `wal_level=logical` | `db-data` | interne |
| `auth` | `supabase/gotrue` | Inscription, login, magic link, JWT | – | via Kong |
| `rest` | `postgrest/postgrest` | API REST auto-générée + RLS | – | via Kong |
| `realtime` | `supabase/realtime` | Websocket (activité équipe) | – | via Kong |
| `storage` + `imgproxy` | `supabase/storage-api` | Avatars, PDF générés | `storage-data` | via Kong |
| `meta`, `studio` | `supabase/postgres-meta`, `supabase/studio` | Admin web | – | `studio.domaine` (basic-auth) |
| `kong` | `kong` | Passerelle API Supabase | – | `supabase.domaine` |
| `powersync` | `journeyapps/powersync-service` | Moteur de sync offline | `powersync-data` | `sync.domaine` |
| `services` | build `services/Dockerfile` (Flask) | Exports, factures, jobs, kiosque | – | `app.domaine/api/*` |
| `web` | `caddy` | HTTPS auto + sert le build Flutter web | `caddy-data`, `web-build` | 80/443 |
| `backup` | `postgres` (cron pg_dump) | Sauvegarde quotidienne | `backups` | – |

Profils compose : `dev` (sans Caddy, ports locaux, Studio ouvert) et `prod`.
Images multi-arch (amd64/arm64) : fonctionne sur VPS x86 comme sur un mini-PC/ARM à la maison.

- `deploy/docker-compose.yml` : `include:` du compose Supabase épinglé + services `powersync`, `services` (Flask), `web` (Caddy), `backup`.
- Caddyfile : `app.domaine` → web statique ; `app.domaine/api/*` → Flask ; `supabase.domaine` → Kong (API, Auth, Realtime websocket, Storage) ; `studio.domaine` → Studio protégé par basic-auth ; `sync.domaine` → PowerSync.
- `.env.example` + script `deploy/gen-secrets.sh` (JWT secret, ANON/SERVICE keys, POSTGRES_PASSWORD, SMTP, POWERSYNC_*).
- Sauvegarde : `backup.sh` (pg_dump quotidien, rétention 14 jours), restauration documentée en tête du script.
- Cibles d'hébergement documentées dans le `README.md`, même compose pour toutes :
  - **VPS OVH / Scaleway** : Ubuntu 24.04, Docker, DNS A vers l'IP, ports 80/443 ouverts, HTTPS Let's Encrypt automatique par Caddy.
  - **Chez vous** : même compose ; HTTPS via Caddy avec soit redirection de ports 80/443 sur la box + DynDNS (OVH DynHost gratuit), soit **Cloudflare Tunnel** ou **Tailscale** si vous ne voulez rien ouvrir (dans ce cas l'app mobile passe par le tunnel/VPN). Images Docker multi-arch (amd64 + arm64) pour tourner aussi sur un ARM.
  - Variables `SITE_URL`, `SUPABASE_PUBLIC_URL`, `POWERSYNC_URL` centralisées dans `.env` : changer d'hébergeur = changer ces valeurs + restaurer la sauvegarde.
- Mobile : builds `fvm flutter build ipa` / `appbundle` ; l'URL Supabase/PowerSync est injectée via `--dart-define`.

## Lots de livraison (ordre d'implémentation)

| Lot | Contenu | Taille |
|---|---|---|
| 0 | Squelette monorepo, CLAUDE.md, compose Supabase local, migrations 0001 (core) + 0002 (RLS) + triggers, publication PowerSync, service PowerSync + sync rules, seed | M |
| 1a | App Flutter : fvm, DI, router responsive, auth Supabase, PowerSync + Drift schema, connecteur upload, sélection workspace | L |
| 1b | Timer + entrées par jour + saisie manuelle + projets/clients/tags/tâches + timesheet hebdo ; i18n FR/EN ; notification timer mobile | L |
| 1c | Vérification offline web + iOS + Android, tests unitaires connecteur/timer | M |
| 2 | Écrans rapports + graphes (calcul local, hors ligne), export CSV local ; Flask + export CSV/XLSX/PDF ; compose prod + Caddy | L |
| 3 | Invitations (email via GoTrue/Flask), rôles, taux, activité équipe (Realtime), verrouillage, projets privés | L |
| 4a | Calendrier + kiosque (PIN) | M |
| 4b | Congés + planning | L |
| 4c | Approbation des timesheets + factures PDF | L |

Chaque lot se termine par un état déployable.

## Vérification

- **Local** : `make up` (Supabase + PowerSync + Flask en Docker), `make migrate`, Studio sur `localhost:8000`.
- **Flutter** : `cd app && fvm flutter run -d chrome`, simulateur iOS, Android ; scénario offline : couper le réseau, créer/arrêter des entrées, rétablir, vérifier dans Studio ; même compte sur deux appareils → démarrer/arrêter le timer de part et d'autre.
- **RLS** : tests SQL (pgTAP ou script psql avec `set role authenticated` + claims) vérifiant qu'un membre ne voit pas les entrées d'un autre workspace.
- **Flask** : `pytest` (JWT, export sur jeu de données seed), `curl` des exports.
- **Prod** : `docker compose up -d` sur la cible choisie (VPS OVH/Scaleway ou machine locale), HTTPS Caddy, inscription, sync depuis le téléphone hors du réseau local, restauration d'une sauvegarde.

## Hypothèses à confirmer en cours de route

- Cible d'hébergement (OVH, Scaleway ou chez vous) et nom de domaine choisis par vous au moment du lot 2 ; le compose ne change pas.
- SMTP (OVH, Brevo…) pour les emails d'invitation/magic link.
- Pas de publication sur les stores dans ce plan (builds TestFlight/APK internes seulement).

## Ajustements décidés pendant la réalisation

- Supabase épinglé sur la version `v1.26.08` du dépôt officiel (Postgres 17 par défaut).
- PowerSync : **Sync Streams** (successeur des Sync Rules) ; les listes littérales `IN ('a','b')` ne sont pas acceptées dans les sous-requêtes → `role != 'member'`.
- Upsert PostgREST (utilisé par le connecteur) : la politique SELECT s'applique à la nouvelle ligne → migration 0005 « le créateur d'un workspace peut le lire ».
- Conflits de chronomètre résolus **côté serveur** (trigger, migration 0004, « le plus récent gagne ») au lieu d'un rejet.
- Flask exposé sur le port hôte **5050** (5000 est pris par AirPlay sur macOS).
- `connectivity_plus` retiré : l'état réseau vient de PowerSync (`SyncStatus.connected`).
- Outils : **fvm** pour Flutter (SDK 3.47.0 épinglé dans `app/.fvmrc`), **uv** pour Python.

## Plans liés

- [02-integration-fidwork.md](02-integration-fidwork.md) : saisie des temps des échafaudeurs et calorifugeurs depuis Fidwork.

## État d'avancement (11 octobre 2026)

| Lot | État | Vérification |
|---|---|---|
| 0 Socle Docker, migrations, RLS, PowerSync | Fait | Pile complète démarrée en local, 0 erreur |
| 1a/1b App : auth, sync, chronomètre, entrées, feuille de temps, référentiel, FR/EN | Fait | Parcours navigateur : inscription → chronomètre → ligne en base |
| 1c Hors ligne, multi-appareil | Fait | Serveur coupé : saisie conservée puis envoyée au retour ; 2e appareil à jour |
| 2 Rapports, exports CSV/XLSX/PDF | Fait | Tests d'intégration des exports, rapport affiché |
| 3 Équipe : invitations (avec ou sans SMTP), rôles, taux, activité, verrouillage | Fait | Tests d'intégration rôles / RLS / verrouillage / invitations |
| 4a Calendrier, kiosque PIN | Fait | Pointage kiosque de bout en bout dans le navigateur |
| 4b Absences (politiques, soldes, demandes, jours fériés), planning | Fait | Tests serveur + affichage des données synchronisées |
| 4c Approbation des feuilles de temps, factures PDF | Fait | Verrouillage à l'approbation, numérotation, totaux, PDF |

Écarts par rapport au plan initial :
- Rapports calculés **localement** (Dart) plutôt que par RPC SQL : ils fonctionnent hors ligne ; Flask garde sa propre requête pour les exports.
- Pas de `docs/` séparé : le `README.md` couvre installation, hébergement et sauvegardes.
- `supabase/seed.sql` remplacé par `deploy/seed-demo.sql` (`make seed EMAIL=…`), qui cible un compte existant.
- PIN kiosque et compteurs de facture rangés dans un schéma privé `clockifai_private` (jamais exposés à l'API ni à la réplication).

Reste à faire (hors périmètre de cette itération) :
- Publication sur les stores (signature Android, TestFlight), icônes et écran de démarrage.
- Fuseau horaire modifiable par l'utilisateur (Europe/Paris par défaut côté serveur).
- Connexion OAuth (Google, Microsoft) : prête côté GoTrue, à activer dans `.env` et dans l'app.
- Interfaçage Fidwork : voir [02-integration-fidwork.md](02-integration-fidwork.md).
