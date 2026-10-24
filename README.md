# Clockifai

Suivi du temps **libre, gratuit et auto-hébergé**, inspiré de Clockify.
Une seule application Flutter pour le **web, iOS, Android et macOS**, utilisable **hors connexion**,
et un backend entièrement en **conteneurs Docker** que l'on installe où l'on veut :
VPS OVH, Scaleway, ou une machine chez soi.

## Fonctionnalités

| Domaine | Contenu |
|---|---|
| Saisie du temps | Chronomètre (survit au redémarrage, continue sur un autre appareil), saisie manuelle, « continuer », dupliquer, tags, facturable, tâche créée à la volée ; chronomètres simultanés (limite par workspace, un seul par tâche) ; entrées similaires regroupées ; sur macOS, icône dans la barre de menus pour démarrer / arrêter sans ouvrir la fenêtre |
| Feuille de temps | Grille hebdomadaire projets × jours, saisie en `1:30`, `1,5`, `90m` |
| Référentiel | Clients, projets (couleur, taux horaire, budget, public/privé), tâches, tags, archivage |
| Équipe | Workspaces multiples, rôles owner / admin / manager / membre, taux par membre, invitations ; chefs d'équipe (groupes, saisie pour un collègue, pointage d'équipe, approbations et rapports de leur équipe) |
| Règles | Projet ou description obligatoires, arrondi, arrêt automatique des chronomètres oubliés, verrouillage des périodes |
| Rapports | Résumé et détail, graphiques, regroupements, arrondi, exports CSV / Excel / PDF |
| Calendrier | Vue semaine (jour sur mobile), création d'une entrée en touchant un créneau |
| Planning | Affectations par membre et projet, capacité quotidienne, surcharge signalée |
| Absences | Types d'absence, droits annuels, soldes, demandes, validation, jours fériés |
| Approbations | Soumission hebdomadaire, validation ou refus ; une semaine approuvée est verrouillée |
| Facturation | Facture générée depuis le temps facturable, numérotation continue, TVA, remise, PDF |
| Kiosque | Tablette partagée où chacun pointe avec son code PIN, sans compte sur l'appareil |
| Hors ligne | Toutes les données du workspace en base locale, synchronisation automatique au retour du réseau |
| Langues | Français, anglais |

L'avancement détaillé par lot est suivi dans [plans/01-plan-clockifai.md](plans/01-plan-clockifai.md).

## Architecture

L'application lit et écrit dans une base SQLite locale (PowerSync + Drift) : tout est instantané et fonctionne
hors ligne. PowerSync envoie les modifications au serveur et redescend celles des autres. Côté serveur, tout est en
conteneurs Docker : Supabase (Postgres 17, Auth, PostgREST, Realtime, Studio, Kong), PowerSync Open Edition
(réplication logique de Postgres), un service Flask (exports, factures, invitations, kiosque, tâches planifiées),
Caddy (HTTPS automatique) et une sauvegarde quotidienne.

- La sécurité multi-tenant repose sur la **Row Level Security** de Postgres : chaque table porte un `workspace_id`.
- Les conflits sont arbitrés côté serveur : dernier écrit gagne, et le nombre de chronomètres en cours par personne est limité par workspace (le plus récent gagne, sans perte de données).

Schémas des composants, du déploiement et des données : [docs/architecture/](docs/architecture/).

## Documentation

L'index est dans [docs/README.md](docs/README.md) :

- [guide utilisateur](docs/guide/index.html), avec les vidéos, en ligne sur `https://<APP_DOMAIN>/guide/` ;
- [exploitation](docs/exploitation.md) : installation, mise à jour, sauvegarde, restauration ;
- [architecture](docs/architecture/) et [API](docs/api/) (OpenAPI du service Flask, diagrammes de séquence) ;
- [notes de version](CHANGELOG.md).

## Démarrage rapide (développement)

Prérequis : Docker Desktop (Compose ≥ 2.24), [fvm](https://fvm.app) pour Flutter, [uv](https://docs.astral.sh/uv/) pour Python ;
Xcode pour macOS / iOS, Android Studio (SDK 36) pour Android.

```bash
make env          # génère deploy/.env avec des secrets aléatoires
make up           # backend local : Supabase + PowerSync + Flask + migrations SQL
make app-config   # écrit app/config/local.json (URLs + clé publique)
make app-get      # dépendances Flutter, assets web PowerSync, génération Drift
make app-web      # lance l'app dans Chrome sur http://localhost:3000
```

| Service local | URL |
|---|---|
| App web | http://localhost:3000 |
| API Supabase + Studio (identifiants `DASHBOARD_*` du `.env`) | http://localhost:8000 |
| PowerSync | http://localhost:8080 |
| Services Flask | http://localhost:5050/api/health |

En développement les comptes sont confirmés sans email (`ENABLE_EMAIL_AUTOCONFIRM=true`).
Pour essayer avec des données : créez un compte dans l'app, puis `make seed EMAIL=votre@email`.

Mode kiosque : un admin crée un appareil dans Paramètres > Appareils kiosque, puis la tablette
ouvre `/kiosk` (lien « Mode kiosque » sur l'écran de connexion) et colle le jeton.
Chaque membre définit son code PIN dans Paramètres.

## Deux versions de l'application : Dev et Prod

Sur macOS, iOS et Android, chaque build existe en deux applications installables côte à côte (bases locales et
sessions séparées). L'écran de connexion indique celle qui tourne (« Version locale » ou « Production »).

| Version | Nom | Identifiant | Backend | Config |
|---|---|---|---|---|
| Développement (Debug) | Clockifai Dev | `com.kysoe.clockifai.dev` | pile Docker locale | `app/config/local.json` (`make app-config`) |
| Production (Release) | Clockifai | `com.kysoe.clockifai` | clockifai.kysoe.com | `app/config/prod.json` (`make app-config-prod`) |

Détails : [plans/06-macos-barre-de-menus.md](plans/06-macos-barre-de-menus.md) (macOS, barre de menus, ouverture de
session) et [plans/07-ios-android.md](plans/07-ios-android.md) (iOS, Android, TestFlight, Google Play).

## Commandes

`make help` liste toutes les cibles ; le `Makefile` fait foi.

### Backend local (Docker, sur le poste de développement)

| Commande | Rôle |
|---|---|
| `make env` | Génère `deploy/.env` avec des secrets aléatoires |
| `make up` | Démarre Supabase, PowerSync, Flask et applique les migrations |
| `make down` | Arrête les conteneurs (les données restent dans les volumes) |
| `make ps` | État des conteneurs |
| `make logs SERVICE=powersync` | Suit les journaux (tous les services sans `SERVICE`) |
| `make migrate` | Rejoue les migrations SQL (idempotent) |
| `make psql` | Ouvre `psql` sur la base (rôle `postgres`) |
| `make seed EMAIL=vous@exemple.fr` | Données de démo dans le workspace d'un compte existant |
| `make reset` | **Détruit** les données locales (volumes Postgres et stockage) et redémarre |
| `make services-sync` / `make services-run` | Environnement Python (uv) / Flask hors Docker, sur le Postgres du compose |

### Backend de production (serveur)

| Commande | Où | Rôle |
|---|---|---|
| `make env`, puis éditer `deploy/.env` | serveur, une fois | Secrets propres au serveur, domaines, SMTP (voir [docs/exploitation.md](docs/exploitation.md)) |
| `make prod-up` | serveur | Démarre tout + build de l'app web + Caddy (HTTPS) + sauvegardes |
| `make deploy HOST=ysimonx@192.168.0.84` | poste de dev | Copie le dépôt sur le serveur (rsync, sans `.env` ni données) et lance `make prod-up` |
| `make backup` | serveur | Sauvegarde immédiate de Postgres dans `deploy/backups/` |
| `make ps`, `make logs` | serveur | État et journaux, comme en local |

### Application : configuration et génération de code

| Commande | Rôle |
|---|---|
| `make app-config` | `app/config/local.json` (URLs + clé publique) depuis `deploy/.env` du poste |
| `make app-config-prod HOST=ysimonx@192.168.0.84` | `app/config/prod.json` depuis le `.env` du serveur (seules les valeurs publiques sont lues) |
| `make app-get` | Dépendances Flutter, assets web PowerSync, génération Drift |
| `make app-gen` | Régénère le code Drift / l10n (après modification des tables) |
| `make app-web-assets` | `sqlite3.wasm` + worker PowerSync compilé avec les dépendances de l'app |

### Application : développement (« Clockifai Dev », backend local)

| Commande | Plateforme |
|---|---|
| `make app-web` | Web, dans Chrome sur http://localhost:3000 |
| `make app-macos` | macOS, avec l'icône dans la barre de menus |
| `make app-ios` | Simulateur iPhone (`IOS_SIMULATOR="iPhone 18 Pro"` par défaut) |
| `make app-android-emulator` | Démarre l'émulateur Android (`ANDROID_AVD=…`, le premier par défaut) |
| `make app-android` | Android (émulateur ou téléphone branché) ; `adb reverse` relie `localhost` de l'appareil au poste |

### Application : production et distribution (« Clockifai », clockifai.kysoe.com)

Prérequis : `make app-config-prod HOST=…`. Côté Apple, le compte développeur ajouté dans Xcode (Réglages > Comptes ;
équipe `APPLE_TEAM`, `9SGKL7VUD3` par défaut) et la fiche « clockifai » (`com.kysoe.clockifai`, plateformes iOS et
macOS) dans App Store Connect. Côté Google, la clé d'envoi créée une fois et **sauvegardée**.

| Plateforme | Commande | Résultat |
|---|---|---|
| Web | `make prod-up` (serveur) | L'image du service `web` compile l'app avec les URLs de production |
| Web | `make app-build-web` | Build web local (`app/build/web`), pour essai |
| macOS | `make app-build-macos` puis `make app-install-macos` | Build signé localement, copié dans `/Applications` (ce Mac seulement) |
| macOS | `make app-dist-macos` | Zip signé Developer ID et notarisé par Apple, pour n'importe quel Mac (`app/build/macos/Clockifai-<version>.zip`) |
| macOS | `make app-dist-macos-testflight` | Envoi à App Store Connect, installation et mises à jour par TestFlight sur Mac |
| iPhone | `make app-dist-ios` | Envoi à App Store Connect, installation et mises à jour par TestFlight |
| Android | `make app-android-keystore` | Une fois : clé d'envoi Google Play dans `~/.config/clockifai/android/`, à sauvegarder |
| Android | `make app-dist-android` | App bundle signé `app/build/Clockifai-<version>-<build>.aab`, à déposer dans la Play Console |

Le numéro de build croît tout seul (minutes depuis le 2026-01-01) : TestFlight et Google Play l'exigent.
Après un envoi, TestFlight propose le build au bout de 5 à 30 minutes de traitement par Apple.

### Tests

| Commande | Rôle |
|---|---|
| `make services-test` | Tests unitaires Flask |
| `make test-integration` | RLS, rôles, conflits de chronomètre, verrouillage, exports (backend local démarré) |
| `make app-test` | Tests Flutter |
| `make app-analyze` | Analyse statique Dart |

### Documentation et guide en ligne

| Commande | Rôle |
|---|---|
| `make docs-check` | Routes Flask ↔ `docs/api/openapi.yaml`, liens et scènes vidéo du guide, statuts des plans |
| `make docs-serve` | Guide servi comme en production : http://localhost:3200/guide/ |
| `make guide-videos` | Copie les vidéos tournées (`demo/out/`) et leurs chapitres dans `docs/guide/videos/` |
| `make guide-publish HOST=ysimonx@192.168.0.84` | Envoie ces vidéos sur le serveur (`make deploy` ne copie que les fichiers suivis par git) |

## Vidéos de démonstration

Cinq vidéos sans voix, avec bandeaux explicatifs, une par rôle : membre, chef d'équipe, manager,
propriétaire du workspace, administrateur de l'installation. Elles se tournent automatiquement
sur la pile locale ([demo/README.md](demo/README.md)) et se regardent dans le guide utilisateur en ligne.

## Mise en production

Le même `docker compose` sert partout ; seul le fichier `deploy/.env` change. Il faut un serveur Linux
(4 vCPU / 8 Go de RAM minimum) avec Docker, et trois noms DNS : `APP_DOMAIN`, `SUPABASE_DOMAIN`, `SYNC_DOMAIN`.

```bash
make env                              # sur le serveur, puis éditer deploy/.env
make prod-up                          # + build web + Caddy (HTTPS Let's Encrypt) + sauvegardes
make deploy HOST=user@serveur         # depuis le poste de dev : copie le dépôt (sans .env) et relance
```

Installation pas à pas, variables de `deploy/.env`, serveur partagé avec d'autres applications, mises à jour,
sauvegardes **et restauration**, surveillance : [docs/exploitation.md](docs/exploitation.md).

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| [app/](app/) | Application Flutter (fvm, Drift, PowerSync, Provider, go_router) ; scripts de distribution dans [app/tool/](app/tool/) |
| [services/](services/) | Service Flask : exports, jobs planifiés (uv) |
| [supabase/migrations/](supabase/migrations/) | Schéma SQL, triggers, RLS (appliqués par le conteneur `migrate`) |
| [supabase/docker/](supabase/docker/) | Pile Supabase officielle épinglée (v1.26.08) |
| [powersync/](powersync/) | Configuration du service et des Sync Streams |
| [deploy/](deploy/) | Compose, Caddyfile, génération des secrets, sauvegardes |
| [demo/](demo/) | Tournage automatique des vidéos de démonstration (un scénario par rôle) |
| [integrations/](integrations/) | Plugin Claude Code (hooks) servi par chaque instance sur `/api/claude/marketplace.json` |
| [docs/](docs/) | Documentation : guide utilisateur (HTML), exploitation, architecture, API ; notes de version dans [CHANGELOG.md](CHANGELOG.md) |
| [plans/](plans/) | Plans validés : projet (avec état d'avancement et liste des plans), Fidwork (en attente), saisie pour autrui, tickets, chronomètres simultanés, hébergement, macOS, iOS et Android, regroupement des entrées, forges git, suivi de Claude Code |

## Licence

À définir.
