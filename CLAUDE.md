# CLAUDE.md

Guide pour Claude Code dans le dépôt Clockifai (clone libre et auto-hébergé de Clockify).

## Vue d'ensemble

| Dossier | Stack | Rôle |
|---|---|---|
| `app/` | Flutter 3.47 (fvm), Drift sur PowerSync, Provider + ChangeNotifier, GetIt, go_router, l10n ARB FR/EN | App unique web / iOS / Android / macOS, offline-first |
| `services/` | Python 3.12, Flask, psycopg 3, APScheduler, openpyxl, WeasyPrint (uv) | Exports, jobs planifiés, futurs endpoints (invitations, kiosque, intégrations) |
| `supabase/migrations/` | SQL Postgres 17 | Schéma, triggers, RLS, publication PowerSync |
| `supabase/docker/` | Copie épinglée du `docker/` officiel Supabase v1.26.08 | **Ne pas modifier** (sauf montée de version) |
| `powersync/` | `service.yaml`, `sync-config.yaml` (Sync Streams, édition 3) | Moteur de sync |
| `deploy/` | Docker Compose, Caddy, scripts | Tout le backend en conteneurs |
| `plans/` | Markdown | Plans (envisagés, validés, en cours, faits) ; statut en tête, index `plans/README.md` ; à tenir à jour avec les décisions prises |
| `docs/` | Markdown + Mermaid, OpenAPI 3.1, HTML statique | Documentation de l'état actuel (voir § Documentation) |
| `demo/` | Node, Playwright, ffmpeg | Vidéos de démonstration tournées automatiquement |
| `integrations/` | Python 3.9 (bibliothèque standard) | Plugin Claude Code (`claude-code/` : hooks et serveur MCP local), servi par Flask sur `/api/claude` ; marketplace locale `clockifai-dev` |

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
make app-macos            # « Clockifai Dev » (macOS, pile locale)
make app-config-prod HOST=ysimonx@192.168.0.84 && make app-build-macos && make app-install-macos  # « Clockifai » (prod)
make app-dist-macos       # « Clockifai » signée Developer ID + notarisée (zip), via le compte ajouté dans Xcode
make app-dist-macos-testflight   # « Clockifai » pour Mac → App Store Connect / TestFlight
make app-ios / make app-android-emulator && make app-android   # « Clockifai Dev » sur simulateur / émulateur
make app-dist-ios         # « Clockifai » → App Store Connect / TestFlight (compte Xcode)
make app-dist-testflight  # iPhone puis Mac ; clé d'API App Store Connect dans ~/.config/clockifai/apple/ si présente
make app-android-keystore && make app-dist-android            # clé d'envoi (une fois) puis .aab Google Play
make app-dist-stores      # iPhone, Mac, Android ; le .aab part sur Google Play si compte de service (play_upload.py)
make app-analyze / make app-test
make docs-check           # routes Flask ↔ openapi.yaml, liens et scènes vidéo du guide, statuts des plans
make docs-serve           # guide servi comme en prod : http://localhost:3200/guide/
make guide-videos && make guide-publish HOST=ysimonx@192.168.0.84   # vidéos tournées → guide en ligne
```

Production (`plans/05-hebergement-maison.md`) : `make prod-up` construit aussi l'app web (`app/Dockerfile`, SDK Flutter
dans l'image) ; `make deploy HOST=ysimonx@192.168.0.84` copie le dépôt sur le serveur (rsync, sans `.env`) et relance.
Sur un serveur partagé, `deploy/docker-compose.override.yml` (copie de `docker-compose.edge.yml`) retire tous les ports
publiés et raccorde `clockifai-web` au reverse proxy commun `~/edge` (modèle `deploy/edge/`).

## Règles d'architecture

### Données et synchronisation
- **L'UI ne parle jamais à Supabase pour les données** : elle lit/écrit la base locale via les dépôts de `app/lib/data/repositories/`. PowerSync envoie la file locale au serveur (`SupabaseConnector.uploadData`, upsert PostgREST) et redescend les changements.
- **Trois endroits à garder alignés** pour toute colonne synchronisée : la migration SQL, `app/lib/data/powersync/schema.dart`, et la table Drift dans `app/lib/data/drift/database.dart` (puis `make app-gen`). Si la table doit être synchronisée, l'ajouter aussi dans `powersync/sync-config.yaml`.
- Tables Drift posées sur les **vues** PowerSync : pas de `withDefault` (utiliser `clientDefault`), pas d'upsert / `insertOnConflictUpdate` / `RETURNING`, pas de migrations Drift.
- Dates : écrites en **UTC** ; comparaisons et tris via `epoch()` / `unixepoch()` car le serveur et le client n'emploient pas le même format ISO texte.
- Suppressions : **soft delete** (`deleted_at`) pour les tables métier ; les Sync Streams filtrent `deleted_at IS NULL`. `time_entry_tags` est supprimé physiquement.
- Booléens : `integer` 0/1 côté SQLite, acceptés tels quels par Postgres.
- Après modification de `powersync/sync-config.yaml` : `docker compose … restart powersync`. Les listes littérales `IN ('a','b')` sont refusées dans les sous-requêtes des streams.
- Cinq flux : `my_profile` (son profil, auto), `workspace_core` (référentiel, auto), `my_time_entries` (données personnelles, auto), `team_data` (tout le workspace, souscrit par `SessionController` pour les managers), `managed_team` (temps, feuilles, absences, planning et relances des collaborateurs d'un chef d'équipe, auto, jointure sur `team_scope` par `(workspace_id, user_id)`).
- Une colonne non nulle ajoutée à une table existante n'est répliquée qu'au prochain changement de ligne : la migration « touche » les lignes (`update … set col = col`) et la colonne Drift reste nullable.
- Une insertion PowerSync (PUT) n'envoie pas les colonnes nulles ; remettre une colonne à nul passe par une mise à jour (PATCH). « Annuler » rétablit une ligne par `AppDatabase.restoreRow` (réinsérée si la sync l'a déjà retirée). Pas de transaction Drift imbriquée sur sqlite_async.
- Dates sans heure (`period_start`, `start_date`, `date`…) : texte `yyyy-MM-dd` côté client (`dayKey()` / `parseDay()` dans `modules_repository.dart`).
- Présence chantier (`features/presence/`, plan 13, lot 13) : la position ne quitte jamais le téléphone ; seul le
  journal d'heures `PresenceLog` (préférences locales, par utilisateur) alimente les propositions d'« Aujourd'hui ».
- Sync figée (flux PowerSync sans délai de lecture, après une veille) : `SyncService.refreshIfStale` reconnecte une sync « connectée » sans point de contrôle depuis 10 min (chaque minute, et dès 2 min au retour au premier plan) ; le pied du menu affiche l'âge au-delà de 15 min (`staleSyncLabel`).
- Le worker web PowerSync est **compilé depuis l'app** (`make app-web-assets`), pas téléchargé : le worker publié peut être en décalage de version avec `sqlite_async`.

### Base de données
- Migrations **append-only** numérotées dans `supabase/migrations/` ; ne jamais réécrire une migration déjà appliquée, en ajouter une nouvelle. `*.admin.sql` s'exécute en `supabase_admin` (rôles, publication, `auth.users`), le reste en `postgres`. Suivi : `clockifai_meta.schema_migrations`.
- Toute nouvelle table métier : `workspace_id`, `created_at`, `updated_at` (trigger `set_updated_at`), `deleted_at`, RLS activée avec les helpers `is_member` / `is_manager` / `is_admin`.
- Chefs d'équipe (migration 0009, `plans/03-saisie-pour-autrui.md`) : ce n'est pas un rôle. Le périmètre est matérialisé dans `team_scope`, recalculé par trigger (`refresh_team_scope`) depuis `team_manager_assignments` et `user_groups`. Droits : `manages()` (lecture), `can_edit_others_time()` (saisie pour autrui selon `workspaces.time_for_others`), `can_decide_time_off()` (selon `time_off_policies.approvers`). `time_entries.created_by` / `updated_by` sont posés par trigger depuis le JWT. Côté app, `TeamRights` (`core/team_rights.dart`) reproduit ces règles pour l'affichage.
- Les écritures client passent par **upsert** : la politique SELECT doit accepter la nouvelle ligne (cf. migration 0005).
- Règles métier critiques côté serveur (triggers), pas seulement dans l'app : verrouillage des entrées, limite de chronomètres simultanés (`workspaces.max_running_timers`, trigger 0011, « le plus récent gagne » ; un seul par tâche, contrôlé côté app : `sameTimerTarget`), garde des rôles, approbations, absences, numérotation et totaux de facture, taux des entrées hors managers (`time_entries_rate`, 0023).
- Un trigger qui doit modifier des entrées sans passer la garde pose `set_config('clockifai.bypass_guard', 'on', true)` (voir `timesheet_submissions_apply`).
- Données sensibles (hash de PIN, compteurs) dans le schéma `clockifai_private` : hors API, hors réplication.

### Flask
- Authentifie le JWT Supabase (`auth.py`), puis vérifie explicitement l'appartenance au workspace (`require_workspace`) : la connexion psycopg contourne la RLS.
- Un seul worker gunicorn (le scheduler APScheduler tourne dans le process).
- Blueprints : `exports`, `invitations` (lien renvoyé si pas de SMTP), `kiosk` (jeton d'appareil `X-Kiosk-Token`, anti force brute en mémoire), `invoices` (PDF), `jobs`, `tokens` (jetons personnels `clk_…`), `agents` (agents retirés, restaurés par un admin), `activity` (événements des hooks Claude Code, temps des agents : `services/agent_clock.py` recalcule, `services/agent_tasks.py` nomme les tâches (objectif, étape), `agent_entry_write` écrit ; usage IA : `link_usage` cumule `agent_usage` par entrée, coût au tarif de `ai_model_prices`, mis à jour par migration), `claude` (marketplace publique : zip de `integrations/claude-code/`, HTTPS exigé par Claude Code), `traces` (journal du jour : agenda iCal privé de chacun, lu par Flask en https public seulement, et ses commits), `reports` (rapports enregistrés par un manager et leur lien public `/api/reports/public/<jeton>`, sans compte : page HTML sans script ou PDF, calculée à l'ouverture ; envoi par email chaque semaine ou chaque mois, job `send_scheduled_reports`), `assistant` (« Demander à Clockifai » : Claude par le SDK `anthropic`, outils en lecture sur des agrégats, jamais les descriptions ; désactivé sans `ANTHROPIC_API_KEY`).

### Plugin Claude Code (`plans/10-suivi-claude-code.md`)
- `integrations/claude-code/scripts/clockifai_hook.py` tourne avec le `python3` de macOS : **Python 3.9, bibliothèque standard** (ruff le vérifie avec `integrations/claude-code/ruff.toml`). Il sort toujours avec 0 et n'écrit sur stdout qu'au `SessionStart` (seul hook synchrone, délai réseau court), quand le serveur répond `ask_ticket` : la consigne fixe de demander le ticket du client (plan 19).
- Liste blanche (D6) : jamais le prompt, `tool_input`, `tool_response` ni le texte de la transcription, sauf l'objectif, l'étape et le ticket du client (adresse ou clé, titre) passés à l'outil `set_current_task` (D18, plan 19). La transcription (et celles des sous-agents) est relue sur le poste au `Stop` pour l'usage IA (D17) : seuls partent des totaux `agent_usage` par tranche de 5 minutes, modèle, effort et vitesse. Ajouter un fichier au plugin, c'est aussi l'ajouter à `PLUGIN_FILES` (`routes/claude.py`).
- `scripts/clockifai_mcp.py` : serveur MCP local (stdio, `.mcp.json`), même contrainte Python 3.9 ; il n'appelle pas le réseau, le hook relaie l'objectif et l'étape (`session_task` `{task_name, step_name}`) : l'objectif devient la tâche, l'étape une sous-tâche (plan 16).
- Sous-tâches (`tasks.parent_id`, 0021, plan 16) : un seul niveau, même projet (trigger) ; côté app, `catalog.tasksOf` ne rend que le premier niveau, `subtasksOf`, `rootTask` et `taskPath` (« Tâche › Sous-tâche ») le reste.
- Clôture (plan 20) : le job `close_idle_agent_tasks` termine chaque nuit les tâches de `agent_tasks` sans temps depuis 7 jours ; reprendre = rouvrir (`_task_named` et `_ticket_row` trouvent aussi les terminées, `reopen_task` dans `process_session` pour l'entrée en cours seulement ; côté app `reopenTask`, managers).

### Flutter
- Organisation par fonctionnalité dans `lib/features/<feature>/` ; transverse dans `lib/core/`.
- État : `SessionController` (utilisateur, workspace courant, rôle, statut de sync) et `CatalogController` (référentiel en mémoire) fournis par Provider ; dépôts et `SyncService` via GetIt (`core/di.dart`).
- Tous les textes passent par l'ARB (`lib/l10n/app_fr.arb` = modèle, `app_en.arb`) ; `context.l10n`.
- Les droits affichés suivent `session.isManager` / `isAdmin`, mais la RLS reste la seule vraie barrière.
- Agents Claude (`workspace_members.kind = 'agent'`, plan 10) : `catalog.humans` / `agents` pour toute liste de personnes ; créer du temps passe par `TeamRights.canCreateTimeFor` (jamais pour un agent, seul le serveur écrit ses entrées), modifier par `canEditTimeOf` (le pilote compris).
- Libellés : ajouter les clés directement dans les deux ARB (`tool/gen_arb.py` est en retard et en supprimerait).
- Coquille (`core/widgets/app_shell.dart`, plan 14) : menu de sept rubriques ; une rubrique à plusieurs pages (Équipe, Projets et clients) les montre en onglets ; « Semaine » regroupe `/timesheet`, `/calendar` et `/` (vues de `WeekViews`). Chronomètre : `TimerControl` (`features/timer/timer_control.dart`), monté une seule fois dans la coquille.
- Raccourcis clavier : `core/shortcuts.dart` (écoute `HardwareKeyboard` ; une touche seule seulement hors saisie, `plainKey`) ; ceux d'une page dans `PageShortcuts`, ceux de l'app dans la coquille ; palette ⌘K dans `features/commands/`. Annuler : `showUndo` (bandeau, ⌘Z).

### macOS (`plans/06-macos-barre-de-menus.md`)
- Icône dans la barre de menus : panneau natif SwiftUI (`macos/Runner/MenuBar*.swift`) sans accès aux données ;
  `MacMenuBar` (`features/timer/menu_bar.dart`, monté dans `MaterialApp.builder`) lui envoie l'état par le canal
  `clockifai/menu_bar` et exécute ses commandes (`start`, `stop`, `setDescription`, `setProject`, `continue`,
  `previewQuick` et `quickEntry` pour la saisie express, ouverte aussi par ⌥⌘T, raccourci Carbon ; `openToday` pour
  la fin de journée) sur la base locale.
- Fermer la fenêtre ne quitte pas l'app (le moteur Flutter et la sync continuent) ; l'icône du Dock suit la fenêtre
  (`LSUIElement`, `MainFlutterWindow.present()`). Démarrage à l'ouverture de session : `LaunchAtLogin.swift`
  (`SMAppService`, macOS 13+), canal `clockifai/launch_at_login`, réglage dans Paramètres et clic droit sur l'icône.
- Debug = « Clockifai Dev » (`com.kysoe.clockifai.dev`, pile locale), Release = « Clockifai » (`com.kysoe.clockifai`,
  `app/config/prod.json`) : deux bacs à sable, donc bases locales et sessions séparées. Swift Package Manager, pas de CocoaPods.

### iOS et Android (`plans/07-ios-android.md`)
- Même séparation : Debug = « Clockifai Dev » (`….dev`), Release = « Clockifai ». iOS : `APP_DISPLAY_NAME` et identifiant
  par configuration dans `project.pbxproj` ; Android : `applicationIdSuffix` et `resValue app_name` dans `build.gradle.kts`.
- Android joint la pile locale par `adb reverse` (8000 / 8080 / 5050) : même `config/local.json` partout.
- Clé d'envoi Google Play hors dépôt (`~/.config/clockifai/android/`) ; numéro de build = minutes depuis le 2026-01-01.

## Tests
- `services/tests/` : unitaires sans base ; `services/tests/integration/` : contre la pile Docker (inscription, RLS, rôles, chronomètres simultanés, verrouillage, upsert du connecteur, exports, chefs d'équipe, agents Claude, jetons et événements d'activité, script du plugin jusqu'à l'entrée de l'agent) ; `test_claude_plugin.py` : script du plugin (liste blanche, nom de tâche relayé, usage lu dans la transcription, serveur MCP local, commits par session, file locale, lancé avec le python3 de macOS) et marketplace.
- `app/test/` : parsing des durées, dépôts (entrées, modules, équipes), `TeamRights`, pont de la barre de menus macOS (canal simulé), regroupement des entrées similaires (dont la ligne dépliable), commandes de connexion de Claude Code et « dernier événement », bandeau et pastille « Claude travaille », Annuler et édition sur place d'une entrée, sélection multiple et clavier du « Suivi du temps », palette ⌘K, usage IA des entrées d'agent (lignes et totaux du rapport), journal automatique (`features/today` : calcul `planDay` et page « Aujourd'hui »), présence chantier (journal de l'appareil, propositions), pointage d'équipe, glisser sur téléphone, jetons du thème, chronomètre (bouton Démarrer et pastille), feuille « + » du téléphone, tickets des clients (analyse des URL, sélecteur), sur base Drift en mémoire.
- Parcours navigateur (Playwright, hors dépôt) : activer l'arbre d'accessibilité Flutter en cliquant `flt-semantics-placeholder`, puis cliquer un champ et taper au clavier (`fill` ne suffit pas).

## Ports locaux
Kong/Supabase 8000, PowerSync 8080, Flask 5050 (5000 est pris par AirPlay sur macOS), Postgres via Supavisor 5432, app web 3000 (`flutter run`), build de démo 3100.

## Documentation (à tenir à jour)

**Une tâche n'est terminée que lorsque la documentation qu'elle touche est à jour, dans le même commit.** En fin de
tâche, parcourir le tableau ci-dessous ; une mise à jour reportée (vidéo à retourner, par exemple) est signalée
explicitement dans le compte rendu, jamais passée sous silence. La doc décrit l'état actuel ; l'historique et les
raisons restent dans `plans/` et git (`plans/11-documentation.md` pour les choix de cette documentation).
`make docs-check` doit passer.

**Plans** : chacun porte en tête `> Statut : **…** (date)` — `envisagé`, `validé`, `en cours`, `fait`, `en attente`
ou `remplacé` — et ses lots une colonne « État ». Commencer ou livrer un lot met à jour le statut du plan et
l'index `plans/README.md`, dans le même commit. Les numéros ne sont jamais réutilisés.

| Doc | Où | À mettre à jour quand… |
|---|---|---|
| Architecture | `docs/architecture/` | un conteneur, un port, un domaine, un flux réseau ou de sync, une table, un rôle change |
| API | `docs/api/openapi.yaml`, `docs/api/sequences/` | une route Flask, ses paramètres ou réponses, une RPC, un enchaînement entre composants change |
| Vidéos de démonstration | `demo/videos/` → `demo/out/*.mp4` | l'interface d'un parcours filmé change, ou une fonction importante apparaît |
| Guide utilisateur | `docs/guide/` (HTML), en ligne sur `https://<APP_DOMAIN>/guide/` | une fonction visible apparaît, change ou disparaît ; un libellé de l'ARB change |
| Guide d'exploitation | `docs/exploitation.md` | installation, `deploy/.env`, sauvegarde / restauration, mise à jour, cibles `make` de prod |
| Notes de version | `CHANGELOG.md` | toute évolution visible ; sert aussi de texte pour TestFlight et Google Play |
| README | `README.md` | point d'entrée court qui renvoie vers `docs/` ; suivre les changements de commandes |

### Architecture
- Diagrammes en **Mermaid** dans le Markdown (rendus par GitHub et VSCode, relus dans les diffs), pas d'images
  exportées à la main : un schéma qu'on ne peut pas modifier en même temps que le code finit faux.
- `composants.md` : clients (web, macOS + barre de menus, iOS, Android, kiosque) → HTTPS → reverse proxy `~/edge` (TLS)
  ou Caddy (Let's Encrypt) → trois domaines : `APP_DOMAIN` (build web, `/api` → Flask), `SUPABASE_DOMAIN` (Kong → Auth,
  PostgREST, Realtime, Storage ; Studio sous basic auth), `SYNC_DOMAIN` (PowerSync) ; Postgres 17 et Supavisor,
  réplication logique vers PowerSync, Flask en psycopg direct, APScheduler, SMTP, Fidwork.
- `deploiement.md` : pile locale (ports ci-dessus) et prod sur serveur partagé (`deploy/edge/`, conteneurs, volumes).
- `donnees.md` : schéma relationnel des tables métier, les Sync Streams (qui reçoit quoi), matrice des droits
  par rôle (membre, chef d'équipe, manager, admin, propriétaire) alignée sur la RLS et `TeamRights`.

### API
- `docs/api/openapi.yaml` (OpenAPI 3.1) décrit **toutes** les routes Flask (`services/app/routes/`) : authentification
  (JWT Supabase ou `X-Kiosk-Token`), paramètres, schémas, erreurs. Un test (`services/tests/test_openapi.py`) compare
  `app.url_map` au fichier et échoue en cas d'écart.
- PostgREST publie sa propre description (`/rest/v1/`) : ne pas la recopier ; documenter seulement les RPC et les règles
  imposées par trigger que le client doit connaître (verrouillage, chronomètres, approbations).
- Diagrammes de séquence Mermaid dans `docs/api/sequences/`, un fichier par parcours : connexion, écriture hors ligne →
  `uploadData` → triggers → réplication → autres appareils, chronomètres simultanés, soumission et approbation,
  invitation, kiosque, export, facture PDF, barre de menus macOS, échanges Fidwork.

### Vidéos de démonstration
`demo/` (Node, Playwright, ffmpeg embarqué) : `node record.mjs [n]`, données recréées par `prepare-demo.sh`
(comptes `*@demo.clockifai.fr`). Après une évolution d'interface, rejouer `DEMO_FAST=1 node record.mjs n`
(répétition sans vidéo, captures `demo/out/echec-*.png`) et ajuster le scénario dans `demo/videos/`.
Les éléments Flutter sont repérés par leur étiquette d'accessibilité ou leur texte propre (`find()` dans `demo/lib/helpers.mjs`).
Filmer avec le Chromium de Playwright (défaut), pas avec Chrome (`DEMO_CHANNEL=chrome`, répétitions seulement :
horodatage des vidéos faux). La vidéo 6 (Claude Code, studio d'Alex) tourne sur un second build compilé avec
`SERVICES_URL=https://clockifai.example.fr` (`app/build/web-demo`, port 3101, refait seul s'il est plus ancien que
`app/build/web`) ; Playwright passe ces requêtes au Flask local, et l'activité de Claude est postée par l'API
d'activité (`demo/claude-history.mjs`, `demo/lib/claude.mjs`). Sous Node 26, `npx playwright install` peut se figer : installation manuelle dans `demo/README.md`.
Le tournage écrit aussi `demo/out/<nom>.chapters.json` (début de chaque `h.scene(…)`, d'après un repère filmé
puis effacé, car la vidéo de Playwright s'étire par rapport à l'horloge). Le nom
de la vidéo (`export const name`) et ceux des scènes sont référencés par le guide : les renommer impose de reprendre
le guide (`make docs-check` le signale). Une vidéo retournée est republiée : `make guide-videos && make guide-publish`.

### Guide utilisateur
- HTML statique sans étape de build ni ressource externe, en français, pour les utilisateurs : `index.html` puis une
  page par rôle (membre, chef d'équipe, manager, propriétaire, administrateur), mêmes libellés que l'app (`app_fr.arb`).
  N'y décrire que ce qui est implémenté.
- Lien vers une scène : `<a class="scene" data-video="<nom>" data-scene="<scène>" href="videos/<nom>.mp4">` ;
  `guide.js` lit les chapitres et cale le lecteur, donc retourner une vidéo met les liens à jour sans toucher au HTML.
- Servi par le Caddy du profil prod sous `https://<APP_DOMAIN>/guide/` (`docs/guide` monté en lecture seule).
  Les vidéos (`docs/guide/videos/`) sont hors git et `make deploy` ne copie que les fichiers suivis : elles partent
  par `make guide-publish`.

### Exploitation et notes de version
- `docs/exploitation.md` : pour l'administrateur d'une installation (pas pour le développeur) ; reprend et complète
  `plans/05-hebergement-maison.md`, avec la procédure de sauvegarde **et de restauration testée** de Postgres.
- `CHANGELOG.md` : section « Non publié » alimentée au fil des commits, figée en version à chaque envoi en prod ou sur les stores.

## Interfaçage Fidwork
Plan **en attente** dans `plans/02-integration-fidwork.md` : Fidwork pousse son référentiel (sites, interventions, compagnons) et les pointages `work_start` / `work_stop` via son outbox `partner_calls` ; Clockifai renvoie les heures par intervention.
