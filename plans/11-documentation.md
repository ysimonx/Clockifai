# Plan 11 — Documentation tenue à jour

> Statut : **fait** (23 octobre 2026). Pistes : « Suites ».

## Objectif

Une documentation qui décrit l'état actuel de Clockifai et qui le reste : architecture, API, vidéos de
démonstration, guide utilisateur en ligne, exploitation, notes de version. La règle de mise à jour est dans
`CLAUDE.md` (§ Documentation) : une tâche n'est terminée que lorsque la doc qu'elle touche est à jour, dans le
même commit.

## Décisions

- **Texte d'abord.** Markdown + Mermaid (rendu par GitHub et VSCode, relu dans les diffs), OpenAPI en YAML,
  guide en HTML statique sans étape de build. Pas d'image exportée à la main ni de générateur de site : ce qu'on
  ne peut pas modifier dans le même commit que le code finit faux.
- **Contrôles automatiques là où c'est possible.**
  - `services/tests/test_openapi.py` compare les routes Flask (`app.url_map`) à `docs/api/openapi.yaml`.
  - `docs/check.py` (`make docs-check`) vérifie les liens internes du guide et que chaque scène citée existe
    dans les scénarios `demo/videos/*.mjs`.
  - `DEMO_FAST=1 node record.mjs` rejoue les scénarios des vidéos (déjà en place).
- **PostgREST n'est pas redocumenté** : il publie sa propre description sur `/rest/v1/`. On ne documente que
  les RPC et les règles imposées par trigger.
- **Le guide renvoie aux scènes des vidéos, pas à des minutes figées.** Le tournage écrit
  `demo/out/<vidéo>.chapters.json` (`[{"scene": "feuille de temps", "start": 83.4}, …]`, temps morts retirés,
  parties assemblées). Les instants viennent d'un repère filmé (carré magenta dans le coin au début de chaque
  scène, retrouvé par ffmpeg puis effacé par `delogo`), pas de l'horloge : la vidéo de Playwright s'étire quand
  l'app anime l'écran (chaque image reçue est écrite au moins une fois à 25 i/s), jusqu'à plusieurs secondes de
  décalage en quelques minutes. Pour la même raison, filmer avec le Chromium de Playwright et non avec Chrome,
  dont les vidéos ont un horodatage encore plus faux. Le guide référence `data-video="1-camille-membre" data-scene="feuille de temps"` ;
  `guide.js` lit les chapitres et pose le lien horodaté. Retourner une vidéo met donc les liens à jour sans
  toucher au guide ; renommer une scène est détecté par `make docs-check`.
- **Hébergement sur la plateforme.** Le Caddy du profil prod sert `docs/guide/` sous
  `https://<APP_DOMAIN>/guide/` (montage en lecture seule dans `clockifai-web`). Les vidéos sont hors git :
  `make guide-videos` les copie de `demo/out/` vers `docs/guide/videos/` (ignoré par git),
  `make guide-publish HOST=…` les envoie sur le serveur (`make deploy` ne copie que les fichiers suivis et ne
  supprime rien côté serveur, elles y restent). `make docs-serve` sert le guide en local sur le port 3200.

## Arborescence

```
docs/
  README.md                 index de la documentation
  architecture/
    composants.md           composants et flux réseau (HTTPS, Caddy / edge, Kong, Postgres, PowerSync, Flask…)
    deploiement.md          pile locale et prod sur serveur partagé
    donnees.md              schéma relationnel, Sync Streams, matrice des droits par rôle
  api/
    openapi.yaml            routes Flask (OpenAPI 3.1)
    README.md               authentification, conventions, renvoi vers PostgREST
    sequences/*.md          un diagramme de séquence Mermaid par parcours
  guide/                    HTML statique, servi sous /guide/
    index.html, membre.html, chef-equipe.html, manager.html, proprietaire.html, administrateur.html
    guide.css, guide.js
    videos/                 hors git : *.mp4 + *.chapters.json
  exploitation.md           pour l'administrateur d'une installation
  check.py                  contrôle des liens et des scènes du guide
CHANGELOG.md                notes de version (« Non publié » puis versions)
```

## Étapes

1. Infra : chapitres dans `demo/` ; route `/guide/` dans Caddy et montage dans le compose ; cibles `make`
   `docs-serve`, `docs-check`, `guide-videos`, `guide-publish` ; `.gitignore`.
2. Architecture (`docs/architecture/`).
3. API : `openapi.yaml`, son test, séquences.
4. Guide utilisateur HTML, une page par rôle, liens vers les scènes.
5. `docs/exploitation.md`, `CHANGELOG.md`, README raccourci vers `docs/`.
6. Mettre à jour `CLAUDE.md` (cibles et chemins réels).
7. Lien « Guide d'utilisation » dans l'app (en bas du menu, et Paramètres › Aide), vers la page du rôle
   (`core/guide.dart`, `GUIDE_URL` écrit par `make app-config`).
8. Statuts des plans : ligne `> Statut` en tête, index `plans/README.md`, contrôlés par `make docs-check`.

## Suites

- Vidéos retournées le 23 octobre 2026 avec chapitres. Les scénarios ne montrent pas encore le regroupement des
  entrées similaires ni les chronomètres simultanés : à ajouter (vidéo 1), avec les sections du guide correspondantes.
- Les coupes de temps morts reposent encore sur l'horloge, donc sur le même décalage que les anciens chapitres :
  les repérer de la même façon (repère filmé au début et à la fin de l'attente).
- Restauration de sauvegarde (`docs/exploitation.md`) à répéter une fois sur une machine de test.
- Politique de confidentialité hébergée à côté du guide (exigée par l'App Store et Google Play).
- Guide en anglais, si des utilisateurs anglophones arrivent (l'app est déjà bilingue).
