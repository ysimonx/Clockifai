# Forges git : branches, commits et demandes de fusion rattachés aux tâches — plan

> Objectif : voir, sur chaque tâche, les branches, commits et demandes de fusion (pull requests et merge
> requests) qui la concernent, **quel que soit l'hébergeur** : GitHub, GitLab, Gitea/Forgejo, Bitbucket, ou
> aucun. On les montre à côté du temps des humains et de celui des agents, et leurs messages servent à
> décrire ce temps.
>
> Prérequis : lot 1 du plan 10 (`10-suivi-claude-code.md` : `code_repositories`, `code_commits`) et lot 0 du
> plan 04 (`04-tickets.md` : numéro de tâche `CLK-42`).

## 1. Constat

| Sujet | État | Où |
|---|---|---|
| Commits vus en local | Prévus : hooks Claude Code et extension VSCode, table `code_commits`, avec la session ou la fenêtre d'origine. **Ne dépend d'aucune forge** | `10-suivi-claude-code.md` D13 |
| Temps de Claude | Entrées ordinaires d'un membre « agent », une par session de travail | `10-suivi-claude-code.md` D2 |
| Tâches | Nom, statut `active` / `done`. Numéro lisible `CLK-42` : lot 0 du plan 04, prérequis | `04-tickets.md` §3 |
| Origine externe d'une tâche | `external_source` / `external_id` sur `tasks` : portés par le lot 4 de ce plan (le plan 02 est en attente) | §5 |
| Écran des tâches | Simples lignes dans la page Projets ; pas de fiche de tâche | `app/lib/features/projects/projects_page.dart` |
| Accès depuis Internet | La production est joignable (`clockifai.kysoe.com`, reverse proxy `~/edge`) ; la pile locale ne l'est pas. Le serveur est un PC à la maison : il peut être éteint | `05-hebergement-maison.md` |
| Secrets serveur | Schéma `clockifai_private`, hors API et hors réplication ; une table s'y crée par une migration `*.admin.sql` (`postgres` n'y a que `usage`) | `0008_private_schema.admin.sql`, `deploy/migrate.sh` |
| Capacité de Flask | Un seul worker, 8 threads, 8 connexions Postgres, partagés avec les exports PDF et les événements du plan 10 | `gunicorn.conf.py`, `db.py` |
| Purge | `purge_soft_deleted` supprime chaque nuit les `tasks` et `time_entries` effacées depuis 30 jours | `jobs/tasks.py` |
| Écritures client | Une violation de contrainte (23xxx) abandonne l'envoi PowerSync : un client ne doit pas réinsérer une ligne effacée | `app/lib/data/powersync/connector.dart` |

## 2. Principes

**P1. Un modèle commun, un adaptateur par forge.** Clockifai ne connaît que cinq objets : dépôt, branche,
commit, demande de fusion et, plus tard, issue. Chaque forge a un adaptateur qui :
- vérifie l'authenticité d'un webhook ;
- traduit sa charge utile en ces objets ;
- optionnellement, lit l'API de la forge pour rattraper l'historique.

Le reste du code (rattachement, écrans, rapports) ignore la forge. Le vocabulaire de l'app dit
« demande de fusion », avec le libellé propre à la forge en sous-titre (« PR #18 », « MR !12 »).

**P2. Git d'abord, forge ensuite.** La source locale (plan 10) fonctionne sans forge. La forge complète ce
qu'elle ne voit pas : commits poussés depuis un autre poste, commits des collègues et de la CI, demandes de
fusion, fusions. Le **sha** relie les deux.

**P3. Identité d'un dépôt : son URL distante normalisée** (`remote_key`), `hôte/chemin`, sans protocole,
utilisateur, port ni `.git`, en minuscules. Par exemple `github.com/ysimonx/clockifai` ou
`gitlab.exemple.fr/groupe/sous-groupe/projet`. C'est la même clé que dans le plan 10 (D9). Pour que le local
et la forge tombent sur la même ligne :
- toutes les URL du dépôt présentes dans la charge utile (clone HTTPS, SSH, page web) sont essayées ;
- une connexion déclare ses **alias d'hôte** SSH (`github.com-travail`, `ssh.github.com`,
  `altssh.bitbucket.org`), ramenés à l'hôte réel ;
- pour une instance installée sous un sous-chemin (`hôte/gitlab/…`), le chemin de l'URL de base est retiré ;
- un dépôt `local:<dossier>` qui gagne un remote est fusionné dans la ligne du remote, avec ses commits.

**P4. Des liens explicables et réversibles.** Chaque lien entre une tâche et un objet garde sa **raison**.
L'utilisateur peut retirer un lien automatique, et un lien retiré n'est jamais recréé par les règles ; seul
un rattachement à la main le rétablit.

**P5. Jamais de code.** On ne garde que le sha, la branche, l'auteur, la première ligne du message, les dates
et l'URL. Ni diff, ni contenu de fichier. Le message complet n'est lu qu'à la réception, pour deux choses :
les clés de tâche (§3) et la mention `Co-Authored-By: Claude`, qui marque le commit comme co-écrit par Claude
(Claude Code commite sous l'identité git du pilote).

## 3. Rattachement à une tâche

Raisons, de la plus forte à la plus faible :

| Raison | Règle |
|---|---|
| `manual` | Lien posé ou rétabli à la main depuis la fiche de la tâche (branche, commit ou demande de fusion), par Flask |
| `reference` | Clé de tâche (`CLK-42`, plan 04 lot 0) dans le nom de branche, le message de commit ou le titre de la demande de fusion. Ou, pour une tâche importée d'une forge (lot 4), sa référence d'issue (`#12`, `groupe/projet#12`) dans le même dépôt |
| `branch` | Objet porté par une branche rattachée à la tâche (propagation ci-dessous) |
| `context` | Commit vu en local pendant une entrée de temps rattachée à la tâche, sur le même dépôt (plan 10 D13). Pour un commit de Claude : l'entrée d'agent de sa session. Pour mes commits : mon entrée qui couvre l'heure du commit, issue d'une suggestion acceptée (plan 10, lot 2) |

Propagation :
- **Branche → objets** : une branche rattachée à une tâche y rattache les commits dont elle est la première
  branche connue (`code_branch_commits`), donc pas ceux déjà vus sur la branche par défaut, ainsi que les
  demandes de fusion qui partent de cette branche.
- **Contexte → branche** : un commit rattaché par `context` sur une branche sans tâche y rattache aussi la
  branche (raison `context`), **jamais la branche par défaut**.
- **Conflit** : deux règles qui désignent deux tâches différentes produisent les deux liens. La fiche les
  affiche, et l'utilisateur retire celui qui ne convient pas.

**Un seul module de règles**, `services/app/code_links.py`, appelé :
- à chaque livraison de webhook traitée ;
- à l'arrivée d'un commit vu en local (événements d'activité du plan 10) ;
- par un job toutes les 5 minutes, pour les entrées de temps dont la tâche a changé depuis le passage
  précédent (`updated_at`) : la tâche d'une entrée d'agent est souvent posée après le commit
  (`/clockifai:tache`, ou le pilote dans l'app) ;
- après un rattachement à la main.

## 4. Forges et adaptateurs

| Forge | Vérification du webhook | Identifiant de livraison | Événements utiles | API de rattrapage |
|---|---|---|---|---|
| **GitHub** | `X-Hub-Signature-256` (HMAC SHA-256 du corps brut) ; type de contenu `application/json` exigé | `X-GitHub-Delivery` (le même à chaque relivraison) | `push`, `pull_request`, `create` / `delete` (branches), plus tard `issues` | REST v3, dont la liste et la relivraison des livraisons d'un webhook |
| **GitLab** (gitlab.com ou auto-hébergé) | `X-Gitlab-Token` (secret partagé), comparé en temps constant | `X-Gitlab-Event-UUID`, à confirmer | `Push Hook`, `Merge Request Hook`, plus tard `Issue Hook` | REST v4 |
| **Gitea / Forgejo** | HMAC SHA-256 (`X-Gitea-Signature` / `X-Forgejo-Signature`) | `X-Gitea-Delivery` / `X-Forgejo-Delivery` | `push`, `pull_request`, `create` / `delete`, plus tard `issues` | API v1 |
| **Bitbucket Cloud** | HMAC (`X-Hub-Signature`), à vérifier | `X-Request-UUID`, à vérifier | `repo:push`, `pullrequest:*` | REST 2.0 |
| Aucune / autre | — | — | — | commits vus en local seulement |

- **Ordre** : GitHub, puis GitLab et Gitea/Forgejo. Bitbucket seulement si quelqu'un le demande.
- **Connexion** = type de forge, URL de base (pour l'auto-hébergé), alias d'hôte SSH, secret de webhook, et
  jeton d'API facultatif (jeton personnel à droits fins ou jeton de projet) pour le rattrapage et les dépôts
  privés.
- **Webhook simple** en v1 : sur un dépôt, une organisation ou un groupe, avec le secret de la connexion. Les
  webhooks de groupe GitLab demandent une édition payante : sur GitLab Free, un webhook par projet. Pas de
  GitHub App au départ : chaque instance auto-hébergée devrait créer la sienne, pour un gain limité tant qu'un
  jeton suffit.
- **Code** : `services/app/forges/`.
  - `base.py` définit l'interface `verify(headers, raw_body, secret)`, `parse(event, payload) → list[NormalizedEvent]`,
    `list_failed_deliveries(…)` et `backfill(repo, since)` ;
  - un module par forge (`github.py`, `gitlab.py`, `gitea.py`) ;
  - des charges utiles enregistrées servent de jeux de test.

## 5. Modèle de données — migrations après celles des plans 10 et 04

Les tables privées vont dans une migration `*.admin.sql`, le reste dans une migration ordinaire.

| Table | Colonnes | Sync |
|---|---|---|
| `clockifai_private.forge_connections` | `id`, `workspace_id`, `kind` (`github`, `gitlab`, `gitea`, `forgejo`, `bitbucket`), `name`, `base_url`, `ssh_host_aliases text[]`, `webhook_secret` et `api_token` **chiffrés** (clé `FORGE_SECRET_KEY` hors base, pour qu'ils ne soient pas en clair dans les sauvegardes `pg_dump`), `created_by`, `created_at`, `disabled_at` | non |
| `clockifai_private.forge_deliveries` | `id`, `connection_id`, `delivery_id`, `event`, `payload` (jsonb : le corps reçu), `received_at`, `processed_at`, `attempts`, `error` ; unique `(connection_id, delivery_id)`. Purgée après 14 jours | non |
| `public.code_repositories` (plan 10) | `+ connection_id` (`on delete set null`), `web_url`, `default_branch` | non |
| `public.code_commits` (plan 10) | `+ pushed_at`, `url`, `author_name`, `author_login`, `co_authored_by_claude` | non |
| `public.code_branches` | `id`, `workspace_id`, `repository_id`, `name`, `head_sha`, + colonnes standard ; unique `(repository_id, name)` | non |
| `public.code_branch_commits` | `branch_id`, `commit_id`, `first_seen_at` ; unique `(branch_id, commit_id)`. Dit sur quelles branches un commit a été vu, et la première | non |
| `public.code_change_requests` | `id`, `workspace_id`, `repository_id`, `source_repository` (dépôt d'une fourche), `number`, `title`, `state` (`open`, `draft`, `merged`, `closed`), `source_branch`, `target_branch`, `author_login`, `author_user_id`, `url`, `opened_at`, `merged_at`, `closed_at`, `merge_sha`, `remote_updated_at`, + colonnes standard ; unique `(repository_id, number)` | non |
| `public.task_code_links` | `id`, `workspace_id`, `task_id` (`on delete cascade`), `object_kind` (`branch`, `commit`, `change_request`), `object_id`, `reason` ; **champs d'affichage dénormalisés** : `repository_name`, `ref` (sha court, nom de branche, « #18 »), `title`, `url`, `state`, `author_name`, `occurred_at`, `co_authored_by_claude` ; + colonnes standard, unique `(task_id, object_kind, object_id)` | `workspace_core`, tâches actives seulement |
| `public.identity_links` (lot 3) | `id`, `workspace_id`, `connection_id`, `external_user_id`, `external_login`, `user_id`, + colonnes standard ; unique `(connection_id, external_user_id)`. Le plan 02, en attente, en prévoyait la forme ; ce plan la crée | non |
| `public.tasks` (lot 4) | `+ external_source` (`forge`), `external_connection_id`, `external_id` (`<remote_key>#<numéro>`), `external_url` ; unique `(workspace_id, external_connection_id, external_id)` | `workspace_core` (existant) |

- **Synchronisation** : seule `task_code_links` est synchronisée, et seulement pour les tâches actives. La fiche
  d'une tâche active s'affiche donc hors ligne, le volume reste limité, et une tâche terminée charge ses liens
  en ligne. À aligner : migration, `schema.dart`, `database.dart`, flux `workspace_core`, `make app-gen`.
- **Champs dénormalisés** : le serveur les met à jour dans tous les liens d'un objet quand l'objet change (état
  d'une demande de fusion, URL d'un commit une fois poussé).
- **Auteurs** : `author_user_id` est déduit de l'e-mail de l'auteur (compte Clockifai), ou d'un identifiant de
  forge relié à un membre (`identity_links`, lot 3).
- **RLS et gardes** :
  - tables `code_*` : lecture par les membres du workspace, écriture par le serveur seulement. L'app les lit par
    Flask, puisqu'elles ne sont pas synchronisées ;
  - `task_code_links` : lecture par les membres ; pas d'insertion par un client. Un trigger de garde,
    `task_code_links_guard` (sur le modèle de `tasks_guard`), ne laisse un client changer que `deleted_at`, et
    seulement de nul à une date : retirer un lien. Personne ne réécrit l'URL, le titre ou la raison d'un lien
    depuis l'app ;
  - un lien retiré reste en base : c'est ce qui empêche les règles de le recréer (P4). Il n'entre pas dans
    `purge_soft_deleted`, et disparaît avec sa tâche (`on delete cascade`) ;
  - `tasks` importées (lot 4) : `tasks_guard` interdit de changer leur nom, leur statut et leurs champs
    `external_*` depuis l'app, managers compris. La forge fait foi.

## 6. Services Flask — blueprint `forges`

- **Administration** (JWT, `require_workspace("admin")`) :
  - `POST /api/forges` `{workspace_id, kind, name, base_url?, ssh_host_aliases?, api_token?}` →
    `{id, webhook_url, webhook_secret}` (secret affiché une seule fois) ;
  - `GET /api/forges?workspace_id=…` : connexions, dépôts vus, dernière livraison, dernière erreur, trous
    détectés ;
  - `POST /api/forges/<id>/secret` : régénère le secret du webhook ;
  - `DELETE /api/forges/<id>`, filtré sur le workspace de l'admin. Les dépôts gardent leurs données,
    `connection_id` passe à nul.
- **Réception** : `POST /api/forges/<connection_id>/webhook` (sans JWT).
  1. Corps limité (`MAX_CONTENT_LENGTH`, 25 Mo) ; signature vérifiée sur le corps brut par l'adaptateur.
     Toute comparaison de secret se fait en temps constant (`hmac.compare_digest`).
  2. La livraison est enregistrée avec son corps. Si une livraison de même identifiant est déjà **traitée**
     (`processed_at` non nul), rien de plus. Une livraison en échec, elle, est retraitée quand la forge la
     relivre.
  3. Réponse 202 immédiate, bien sous les délais des forges (10 s pour GitHub et GitLab, 5 s par défaut pour
     Gitea).
  4. Un job APScheduler traite les livraisons en attente toutes les 15 s, dans l'ordre de réception :
     normalisation, upsert des dépôts, branches, commits et demandes de fusion, puis règles (§3). Une
     demande de fusion n'est mise à jour que si `remote_updated_at` est plus récent : un événement arrivé en
     retard ne fait pas revenir son état en arrière.
- **Rattrapage** (lot 1), indispensable avec un serveur qui peut être éteint : GitHub et Gitea ne relivrent pas
  d'eux-mêmes, et GitLab désactive un webhook après des échecs répétés.
  - Job `forge_catch_up` toutes les heures. Pour une connexion avec jeton d'API, il liste les livraisons en
    échec (GitHub : `hooks/{id}/deliveries`) et les fait relivrer.
  - Un `push` dont le `before` ne correspond pas à la tête connue de la branche révèle un trou. Avec un
    jeton, l'API comble l'écart `before..after` ; sans jeton, le trou est signalé sur l'écran de la
    connexion.
  - Le rattrapage d'historique (`backfill`, lot 3) tourne aussi en job, jamais dans une requête.
- **Liens** (JWT, membre du workspace) :
  - `GET /api/tasks/<id>/code` : branches, commits et demandes de fusion de la tâche, avec le détail ;
  - `GET /api/code/search?workspace_id=…&q=…` : objets à rattacher (nom de branche, sha, numéro, titre) ;
  - `POST /api/tasks/<id>/code-links` `{object_kind, object_id}` : pose un lien `manual`, ou rétablit un lien
    retiré, puis applique la propagation (§3).
- **Temps** : `GET /api/time-entries/<id>/commits` : commits rattachés à une entrée (plan 10), pour l'app.
- Le nom de branche proposé se calcule dans l'app, hors ligne (plan 04, §3) : pas de route.
- Jobs : traitement des livraisons (15 s), `forge_catch_up` (1 h), règles différées (5 min, §3),
  `purge_forge_deliveries` chaque nuit.

## 7. Application Flutter

- **Réglages → Intégrations → Forges** (admins) :
  - ajouter une connexion : type, URL pour l'auto-hébergé, alias d'hôte SSH, jeton facultatif ;
  - copier l'URL et le secret du webhook, avec une aide propre à chaque forge (où les coller), et régénérer
    le secret ;
  - voir les dépôts reçus, l'état de la dernière livraison et les trous détectés.
- **Fiche de tâche** (nouvelle, ouverte depuis la ligne de tâche de la page Projets ; le plan 04 y ajoutera
  commentaires et historique) :
  - en-tête : clé (`CLK-42`), temps des humains, temps des agents et durée calendaire (plan 10) ;
  - volet **Développement** : branches, demandes de fusion (état en couleur), commits (sha court, message,
    auteur, date, lien vers la forge, mention « local » s'il n'a jamais été poussé, mention « avec Claude »
    s'il est co-écrit). Hors ligne depuis `task_code_links` ; le détail en ligne ;
  - chaque lien montre sa raison. « Retirer » marche hors ligne ; « rattacher à la main » demande une
    connexion (recherche et pose par Flask) ;
  - bouton **créer une branche** : copie `git switch -c clk-42-<titre>`. Désactivé tant que la tâche n'a pas
    de numéro (créée hors ligne). Clockifai ne crée pas la branche sur la forge en v1.
- **Entrées d'agent et suggestions** (plan 10) : les commits faits pendant la plage, en ligne
  (`GET /api/time-entries/<id>/commits`), avec un lien vers la forge quand il existe.
- ARB FR/EN pour tous les libellés.

## 8. Tests

- `services/tests/` (unitaires, sans base) :
  - par adaptateur, sur des charges utiles enregistrées : signature valide ou invalide, objets normalisés,
    push forcé, suppression de branche, fusion d'une demande (fusion simple, squash, rebase) ;
  - normalisation de `remote_key` : ssh, https, port, sous-groupes GitLab, majuscules, alias d'hôte, instance
    sous un sous-chemin ;
  - analyse des références : `CLK-42` (analyseur du plan 04), `#12`, `groupe/projet#12`, faux positifs (`#`
    dans du texte) ; détection de `Co-Authored-By: Claude` ;
  - règles de rattachement : priorités, propagation par première branche connue, branche par défaut jamais
    rattachée par contexte, lien retiré jamais recréé par les règles mais rétabli à la main ;
  - état d'une demande de fusion : un événement plus ancien ne la fait pas revenir en arrière.
- `services/tests/integration/` :
  - livraison de webhook → livraison enregistrée, réponse 202, puis lignes créées par le job ;
  - livraison rejouée après succès → rien de plus ; relivrée après un échec → retraitée ;
  - signature invalide → 401 ; corps trop gros → 413 ;
  - `task_code_links` : un membre ne peut ni insérer un lien, ni changer son URL ou sa raison ; il peut le
    retirer ; un lien retiré puis rattaché à la main par Flask → la même ligne rétablie ; pas d'accès d'un
    autre workspace ;
  - commit vu en local puis poussé → une seule ligne, avec `pushed_at` et `url` ; dépôt `local:` qui gagne un
    remote → lignes fusionnées ;
  - tâche d'une entrée d'agent posée après le commit → lien `context` créé par le job ;
  - purge de nuit d'une tâche avec des liens → aucune erreur ;
  - trou détecté sur un `push` → signalé, comblé avec un jeton.
- `app/test/` : fiche de tâche, avec liens groupés par type, action « retirer » hors ligne, bouton « créer une
  branche » désactivé sans numéro.
- Bout à bout :
  - GitHub : `gh webhook forward` (extension `gh`) vers la pile locale ;
  - GitLab et Gitea : bouton « tester » du webhook, à travers un tunnel.

## 9. Lots

| Lot | Contenu | Taille |
|---|---|---|
| 1 Socle et GitHub | Migrations, adaptateur GitHub (`push`, `pull_request`, `create`, `delete`), réception en tâche de fond, rattrapage des livraisons GitHub, module de règles §3 (liens `context` des commits de Claude), routes de liens, administration des connexions, fiche de tâche et volet Développement. Prérequis : plan 10 lot 1, plan 04 lot 0 | M/L |
| 2 GitLab et Gitea/Forgejo | Deux adaptateurs de plus et leurs jeux de test | S chacun |
| 3 Rattrapage et auteurs | `backfill` par API (en job), `identity_links` et rapprochement auteurs ↔ membres | S/M |
| 4 Issues | Issues importées comme tâches (`external_*` sur `tasks`, garde de lecture seule), références `#12`, tâche terminée à la fusion de sa demande. Le dépôt doit avoir un projet (`code_repositories.project_id`) : une issue devient une tâche de ce projet | M |
| 5 Bitbucket | À la demande | S |

Les liens `context` de **mes** commits (piste humaine) arrivent avec le lot 2 du plan 10 (suggestions acceptées).

## 10. Points d'attention

- **Charges utiles tronquées** : GitLab ne met que 20 commits par push, avec `total_commits_count`. GitHub en met
  2048 au plus, sans total : un trou se voit en comparant `before` à la tête connue (§6). Le rattrapage par API
  complète.
- **Réécritures** :
  - les sha d'un rebase ou d'un `--amend` jamais poussés restent « local » ;
  - un push forcé met à jour la tête de la branche, et les commits abandonnés restent visibles ;
  - une fusion par squash relie le commit final à la tâche par la demande de fusion.
- **Branche par défaut** : jamais rattachée à une tâche par contexte. Un commit direct sur `main` n'est
  rattaché que par référence ou par contexte individuel.
- **Plusieurs workspaces** sur le même dépôt : une connexion par workspace, donc chaque workspace reçoit son
  propre webhook.
- **Pile locale** non joignable depuis Internet : `gh webhook forward` ou un tunnel pour les tests.
- **Confidentialité** : les messages de commit sont visibles des membres du workspace qui voient la tâche.
- **Secrets** : chiffrés en base avec une clé hors base ; perdre la clé oblige à recréer les connexions.
- **Commits de Claude** : ils portent l'identité git du pilote, donc lui sont attribués comme auteur. La mention
  `Co-Authored-By: Claude` les signale ; localement, la session suffit (plan 10 D13).

## 11. Questions à trancher

1. GitHub : webhook simple (proposé), ou GitHub App dès le départ ?
2. Propagation automatique d'un commit de contexte à sa branche (proposé : oui, sauf branche par défaut) ?
3. Issues importées comme tâches (lot 4), ou tâches Clockifai seulement ?
4. Bouton « créer une branche » : copier la commande (proposé), ou créer la branche sur la forge par l'API ?
