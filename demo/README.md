# Vidéos de démonstration

Six vidéos sans voix, avec des bandeaux explicatifs incrustés, tournées automatiquement
dans un navigateur (Playwright) sur la pile locale :

| Vidéo | Personne | Ce qu'elle montre |
|---|---|---|
| `1-camille-membre.mp4` | Camille, membre | Saisie après coup et chronomètre, tâche créée à la volée, feuille de temps et soumission, planning, absences, rapports personnels, hors ligne, mobile |
| `2-karim-chef-equipe.mp4` | Karim, chef de l'équipe « Unité 4 » | Pointage d'équipe, saisie pour une collègue, approbation des feuilles de temps et des absences, rapports limités à son équipe |
| `3-julien-manager.mp4` | Julien, conducteur de travaux, manager | Toute l'entreprise : équipe et taux, approbation d'une feuille et d'une absence hors de l'équipe de Karim, affectation au planning, rapports et export Excel, budgets, réglages en lecture seule |
| `4-sophie-gestion-workspace.mp4` | Sophie, propriétaire | Rôles, groupes, chefs d'équipe, invitations, règles (saisie pour autrui, verrouillage, arrondi), projets, absences, planning, rapports, factures, kiosque |
| `5-admin-installation.mp4` | Administrateur de l'installation | Supabase Studio (comptes, données, SQL), paramétrage `deploy/.env`, commandes d'exploitation, récapitulatif des rôles |
| `6-alex-claude-code.mp4` | Alex, développeur indépendant, et son agent Claude | Connexion d'un poste, installation du plugin (terminal en incrustation), session de Claude Code en direct, réglage « Tâches de Claude », postes connectés, fiche de l'agent, rapports humains / agents et détaillé, correction d'une entrée, facture détaillée par tâche |

## Tourner

```bash
make up                         # pile Docker démarrée
make app-build-web              # build web de production à jour
cd demo && npm install
node record.mjs                 # les 5 vidéos → demo/out/*.mp4 (+ *.chapters.json pour le guide)
node record.mjs 2               # une seule vidéo
DEMO_FAST=1 node record.mjs 1   # répétition rapide, sans vidéo, pour mettre au point un scénario
```

Le tournage utilise le Chromium et le ffmpeg de Playwright (`npx playwright install chromium ffmpeg`, une fois).
Le Google Chrome installé (`DEMO_CHANNEL=chrome`) suffit pour les répétitions `DEMO_FAST`, pas pour filmer :
Playwright y produit des vidéos à l'horodatage faux, plus courtes ou plus longues que le temps réel, d'où des
coupes et des chapitres décalés.

Avec Node 26, l'installateur de Playwright peut se figer en pleine décompression et laisser un binaire tronqué
(« spawn Unknown system error -88 », ou un téléchargement qui ne finit jamais). Installer alors à la main, avec
les révisions de `node_modules/playwright-core/browsers.json` (ici Mac Apple Silicon, Playwright 1.55) :

```bash
CDN=https://cdn.playwright.dev/dbazure/download/playwright/builds; PW=~/Library/Caches/ms-playwright
curl -fLo /tmp/ffmpeg.zip $CDN/ffmpeg/1011/ffmpeg-mac-arm64.zip
rm -rf $PW/ffmpeg-1011 && mkdir -p $PW/ffmpeg-1011 && ditto -x -k /tmp/ffmpeg.zip $PW/ffmpeg-1011
curl -fLo /tmp/chromium.zip $CDN/chromium/1187/chromium-mac-arm64.zip
rm -rf $PW/chromium-1187 && mkdir -p $PW/chromium-1187 && ditto -x -k /tmp/chromium.zip $PW/chromium-1187
touch $PW/ffmpeg-1011/INSTALLATION_COMPLETE $PW/chromium-1187/INSTALLATION_COMPLETE
```

Avant chaque vidéo, `prepare-demo.sh` recrée l'entreprise fictive « Échafaudages du Nord » et le studio
d'Alex (comptes `*@demo.clockifai.fr`, mot de passe `Demo-2026-clockifai`). Ces comptes servent aussi
à essayer l'app à la main. `sh prepare-demo.sh --clean-test-accounts` supprime en plus les comptes
laissés par les tests automatiques.

L'historique de Claude (vidéo 6) passe par le vrai chemin : `claude-history.mjs` connecte le « Mac mini »
d'Alex (`POST /api/tokens`, qui crée son agent) puis poste les événements de ses sessions des derniers jours
ouvrés (`POST /api/activity/events`, `lib/claude.mjs`), usage IA compris (`agent_usage` par tranche de 5 minutes,
Opus 5.5 et un sous-agent Haiku) ; le serveur en tire les entrées, tâches, descriptions et coûts estimés. Le Flask
local doit tourner. Pendant le tournage, la vidéo poste de même une session en direct,
avec le jeton qu'elle vient de copier à l'écran (presse-papiers lu par Playwright).

La vidéo 6 montre l'écran Claude Code d'une vraie instance : sur la pile locale, en http, il afficherait les
commandes de développement (marketplace `clockifai-dev`). `lib/public-instance.mjs` compile donc un second
build, `app/build/web-demo`, avec `SERVICES_URL=https://clockifai.example.fr` (refait tout seul, environ
1 min 30, quand il est plus ancien que `app/build/web`), le sert sur le port 3101, et Playwright passe les
requêtes vers cette adresse au Flask local.

L'app est servie depuis `app/build/web` sur le port **3100** (le 3000 sert au `flutter run` de
développement). Une scène qui échoue est notée, une capture est enregistrée dans `demo/out/echec-*.png`
et le tournage continue.

## Publier dans le guide utilisateur

Le guide (`docs/guide/`, en ligne sous `https://<APP_DOMAIN>/guide/`) intègre les vidéos et renvoie à leurs
scènes par leur nom (`h.scene('feuille de temps', …)`) : `*.chapters.json` donne le début de chaque scène.
Renommer une vidéo ou une scène impose de reprendre le guide ; `make docs-check` le signale.

```bash
make guide-videos                          # demo/out → docs/guide/videos (hors git)
make docs-serve                            # aperçu : http://localhost:3200/guide/
make guide-publish HOST=user@serveur       # envoi sur le serveur de production
```

Sous macOS, `record.mjs` réveille l'écran et empêche la mise en veille (`caffeinate`) le temps du
tournage. Sur batterie, capot fermé, le Mac s'endort malgré tout et les vidéos se remplissent de temps
morts : garder l'écran ouvert, ou brancher le secteur.

## Organisation

| Fichier | Rôle |
|---|---|
| `record.mjs` | Lance les vidéos, encode en MP4 (ffmpeg embarqué), assemble les parties |
| `videos/*.mjs` | Un scénario par vidéo : scènes, bandeaux, actions |
| `lib/helpers.mjs` | Pilotage de Flutter web par son arbre d'accessibilité, curseur, enregistrement |
| `lib/overlay.js` | Incrustations : bandeau, carte titre, panneau de code, curseur visible |
| `prepare-demo.sh` | Données de démonstration rejouables |
| `claude-history.mjs`, `lib/claude.mjs` | Poste de Claude Code et sessions d'Alex (vidéo 6), par l'API d'activité |
| `lib/public-instance.mjs` | Build et interception « adresse publique » de la vidéo 6 |
| `serve.mjs` | Petit serveur du build web |
