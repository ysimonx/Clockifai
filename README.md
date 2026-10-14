# Clockifai

Suivi du temps **libre, gratuit et auto-hébergé**, inspiré de Clockify.
Une seule application Flutter pour le **web, iOS, Android et macOS**, utilisable **hors connexion**,
et un backend entièrement en **conteneurs Docker** que l'on installe où l'on veut :
VPS OVH, Scaleway, ou une machine chez soi.

## Fonctionnalités

| Domaine | Contenu |
|---|---|
| Saisie du temps | Chronomètre (survit au redémarrage, continue sur un autre appareil), saisie manuelle, « continuer », dupliquer, tags, facturable ; sur macOS, icône dans la barre de menus pour démarrer / arrêter sans ouvrir la fenêtre |
| Feuille de temps | Grille hebdomadaire projets × jours, saisie en `1:30`, `1,5`, `90m` |
| Référentiel | Clients, projets (couleur, taux horaire, budget, public/privé), tâches, tags, archivage |
| Équipe | Workspaces multiples, rôles owner / admin / manager / membre, taux par membre |
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

```
 Flutter (web / iOS / Android / macOS)
   ├─ base locale SQLite (PowerSync + Drift) ── lectures/écritures instantanées, hors ligne
   ├─ PowerSync ──────── flux de synchronisation (Sync Streams) ──┐
   └─ Supabase (auth, envoi des modifications via PostgREST) ─────┤
                                                                  ▼
 Docker : Supabase (Postgres 17, GoTrue, PostgREST, Realtime, Storage, Studio, Kong)
          PowerSync Open Edition (réplication logique de Postgres)
          services Flask (exports, jobs planifiés)
          Caddy (HTTPS automatique)  ·  sauvegardes pg_dump quotidiennes
```

- La sécurité multi-tenant repose sur la **Row Level Security** de Postgres : chaque table porte un `workspace_id`.
- Les conflits sont arbitrés côté serveur : dernier écrit gagne, et un seul chronomètre en cours par personne (le plus récent gagne, sans perte de données).

## Démarrage rapide (développement)

Prérequis : Docker Desktop (Compose ≥ 2.24), [fvm](https://fvm.app) pour Flutter, [uv](https://docs.astral.sh/uv/) pour Python.

```bash
make env          # génère deploy/.env avec des secrets aléatoires
make up           # Supabase + PowerSync + Flask + migrations SQL
make app-config   # écrit app/config/local.json (URLs + clé publique)
make app-get      # dépendances Flutter, assets web PowerSync, génération Drift
make app-web      # lance l'app dans Chrome sur http://localhost:3000
```

| Service | URL locale |
|---|---|
| App web | http://localhost:3000 |
| API Supabase + Studio (identifiants `DASHBOARD_*` du `.env`) | http://localhost:8000 |
| PowerSync | http://localhost:8080 |
| Services Flask | http://localhost:5050/api/health |

Mobile : `cd app && fvm flutter run` sur un simulateur iOS ou un émulateur Android.
Sur l'émulateur Android, `localhost` désigne l'émulateur : générez la config avec
`SUPABASE_URL=http://10.0.2.2:8000 POWERSYNC_URL=http://10.0.2.2:8080 SERVICES_URL=http://10.0.2.2:5050 make app-config`.

macOS : `make app-macos` lance « Clockifai Dev » sur la pile locale. La version de production
(« Clockifai », branchée sur le serveur) : `make app-config-prod HOST=user@ip`, `make app-build-macos`,
`make app-install-macos` ; pour d'autres Mac, `make app-dist-macos` produit un zip signé Developer ID et notarisé
par Apple. Les deux cohabitent ; voir [plans/06-macos-barre-de-menus.md](plans/06-macos-barre-de-menus.md).

En développement les comptes sont confirmés sans email (`ENABLE_EMAIL_AUTOCONFIRM=true`).
Pour essayer avec des données : créez un compte dans l'app, puis `make seed EMAIL=votre@email`.

Mode kiosque : un admin crée un appareil dans Paramètres > Appareils kiosque, puis la tablette
ouvre `/kiosk` (lien « Mode kiosque » sur l'écran de connexion) et colle le jeton.
Chaque membre définit son code PIN dans Paramètres.

## Vidéos de démonstration

Cinq vidéos sans voix, avec bandeaux explicatifs, une par rôle : membre, chef d'équipe, manager,
propriétaire du workspace, administrateur de l'installation. Elles se tournent automatiquement
sur la pile locale : voir [demo/README.md](demo/README.md).

## Tests

```bash
make services-test      # tests unitaires Flask
make test-integration   # RLS, rôles, conflits de chronomètre, verrouillage, exports (pile Docker démarrée)
make app-test           # tests Flutter
make app-analyze        # analyse statique Dart
```

## Mise en production

Le même `docker compose` sert partout ; seul le fichier `deploy/.env` change.

1. Un serveur Linux (x86_64 ou arm64) avec **4 vCPU / 8 Go de RAM** minimum et Docker.
2. Trois noms DNS vers ce serveur : `APP_DOMAIN`, `SUPABASE_DOMAIN`, `SYNC_DOMAIN`.
3. Dans `deploy/.env` : ces domaines, `SITE_URL`, `SUPABASE_PUBLIC_URL`, `API_EXTERNAL_URL`, `POWERSYNC_PUBLIC_URL`, le SMTP, et `ENABLE_EMAIL_AUTOCONFIRM=false`.
4. Démarrer : l'image du service `web` compile elle-même l'app Flutter avec ces URLs (pas de SDK Flutter sur le serveur).

```bash
make env                              # sur le serveur, puis éditer deploy/.env
make prod-up                          # + build web + Caddy (HTTPS Let's Encrypt) + sauvegardes
make deploy HOST=user@serveur         # depuis le poste de dev : copie le dépôt (sans .env) et relance
```

| Hébergement | Particularités |
|---|---|
| VPS OVH / Scaleway | Ouvrir 80/443, enregistrements DNS A vers l'IP |
| Chez soi | Redirection 80/443 sur la box + DynDNS (OVH DynHost), ou Cloudflare Tunnel / Tailscale pour ne rien exposer |
| Serveur partagé avec d'autres applications | Reverse proxy commun ([deploy/edge/](deploy/edge/)) et `deploy/docker-compose.edge.yml` copié en `deploy/docker-compose.override.yml` : aucun port publié par la pile. Voir [plans/05-hebergement-maison.md](plans/05-hebergement-maison.md) |

Sauvegardes : `deploy/backups/` (rétention 14 jours), à copier hors du serveur.
Restauration décrite en tête de [deploy/backup.sh](deploy/backup.sh).

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| [app/](app/) | Application Flutter (fvm, Drift, PowerSync, Provider, go_router) |
| [services/](services/) | Service Flask : exports, jobs planifiés (uv) |
| [supabase/migrations/](supabase/migrations/) | Schéma SQL, triggers, RLS (appliqués par le conteneur `migrate`) |
| [supabase/docker/](supabase/docker/) | Pile Supabase officielle épinglée (v1.26.08) |
| [powersync/](powersync/) | Configuration du service et des Sync Streams |
| [deploy/](deploy/) | Compose, Caddyfile, génération des secrets, sauvegardes |
| [demo/](demo/) | Tournage automatique des vidéos de démonstration (un scénario par rôle) |
| [plans/](plans/) | Plan du projet (avec état d'avancement) et plan d'interfaçage avec Fidwork |

## Licence

À définir.
