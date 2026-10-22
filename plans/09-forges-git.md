# Forges git : branches, commits et demandes de fusion rattachés aux tâches — plan

> Objectif : voir, sur chaque tâche, les branches, commits et demandes de fusion (pull requests et merge
> requests) qui la concernent, **quel que soit l'hébergeur** : GitHub, GitLab, Gitea/Forgejo, Bitbucket, ou
> aucun. On les montre à côté de mon temps et de celui de Claude, et leurs messages servent à décrire ce temps.

## 1. Constat

| Sujet | État | Où |
|---|---|---|
| Commits vus en local | Prévus : hooks Claude Code et extension VSCode, table `code_commits`, avec la session ou la fenêtre d'origine. **Ne dépend d'aucune forge** | `06-suivi-claude-code.md` D13 |
| Tâches | Nom, statut `active` / `done` ; pas de numéro lisible. `CLK-42` est envisagé, non engagé | `04-tickets.md` §2 |
| Origine externe d'une tâche | `external_source` / `external_id` sur `tasks` prévus, non livrés | `02-integration-fidwork.md` §5, `04-tickets.md` §4 |
| Écran des tâches | Simples lignes dans la page Projets ; pas de fiche de tâche | `app/lib/features/projects/projects_page.dart` |
| Accès depuis Internet | La production est joignable (`clockifai.kysoe.com`, reverse proxy `~/edge`) ; la pile locale ne l'est pas | `05-hebergement-maison.md` |
| Secrets serveur | Schéma `clockifai_private`, hors API et hors réplication | `0008_private_schema.admin.sql` |

## 2. Principes

**P1. Un modèle commun, un adaptateur par forge.** Clockifai ne connaît que cinq objets : dépôt, branche,
commit, demande de fusion et, plus tard, issue. Chaque forge a un adaptateur qui :
- vérifie l'authenticité d'un webhook ;
- traduit sa charge utile en ces objets ;
- optionnellement, lit l'API de la forge pour rattraper l'historique.

Le reste du code (rattachement, écrans, rapports) ignore la forge. Le vocabulaire de l'app dit
« demande de fusion », avec le libellé propre à la forge en sous-titre (« PR #18 », « MR !12 »).

**P2. Git d'abord, forge ensuite.** La source locale (plan 06) fonctionne sans forge. La forge complète ce
qu'elle ne voit pas : commits poussés depuis un autre poste, commits des collègues et de la CI, demandes de
fusion, fusions. Le **sha** relie les deux.

**P3. Identité d'un dépôt : son URL distante normalisée**, `hôte/chemin`, sans protocole, utilisateur, port
ni `.git`, en minuscules. Par exemple `github.com/ysimonx/clockifai` ou `gitlab.exemple.fr/groupe/sous-groupe/projet`.
C'est la même clé `remote_key` que dans le plan 06. Un dépôt sans remote reste `local:<dossier>`.

**P4. Des liens explicables et réversibles.** Chaque lien entre une tâche et un objet garde sa **raison**.
L'utilisateur peut retirer un lien automatique, et un lien retiré n'est jamais recréé.

**P5. Jamais de code.** On ne garde que le sha, la branche, l'auteur, la première ligne du message, les dates
et l'URL. Ni diff, ni contenu de fichier.

## 3. Rattachement à une tâche

Raisons, de la plus forte à la plus faible :

| Raison | Règle |
|---|---|
| `manual` | Lien posé à la main depuis la fiche de la tâche |
| `reference` | Clé `CLK-42` (si le plan 04 la livre) dans le nom de branche, le message de commit ou le titre de la demande de fusion. Ou, pour une tâche importée d'une forge (lot 4), sa référence d'issue (`#12`, `groupe/projet#12`) dans le même dépôt |
| `branch` | Branche attribuée à la tâche : soit choisie dans la fiche, soit créée avec le nom proposé par le bouton « créer une branche » (`clk-42-titre`, ou `<id court>-titre`) |
| `context` | Commit vu en local pendant une ligne `agent_time` ou un intervalle de focus rattaché à la tâche, sur le même dépôt (plan 06 D13) |

Propagation :
- **Branche → objets** : une branche rattachée à une tâche y rattache ses commits, sauf ceux déjà présents sur
  la branche par défaut, ainsi que les demandes de fusion qui partent de cette branche.
- **Contexte → branche** : un commit rattaché par `context` sur une branche sans tâche y rattache aussi la
  branche (raison `context`), **jamais la branche par défaut**.
- **Conflit** : deux règles qui désignent deux tâches différentes produisent les deux liens. La fiche les
  affiche, et l'utilisateur retire celui qui ne convient pas.

## 4. Forges et adaptateurs

| Forge | Vérification du webhook | Événements utiles | API de rattrapage |
|---|---|---|---|
| **GitHub** | `X-Hub-Signature-256` (HMAC SHA-256 du corps), identifiant de livraison `X-GitHub-Delivery` | `push`, `pull_request`, `create` / `delete` (branches), plus tard `issues` | REST v3 |
| **GitLab** (gitlab.com ou auto-hébergé) | `X-Gitlab-Token` (secret partagé) ; identifiant de livraison à vérifier | `Push Hook`, `Merge Request Hook`, plus tard `Issue Hook` | REST v4 |
| **Gitea / Forgejo** | HMAC SHA-256 (`X-Gitea-Signature` / `X-Forgejo-Signature`), à vérifier | `push`, `pull_request`, `create` / `delete`, plus tard `issues` | API v1 |
| **Bitbucket Cloud** | HMAC (`X-Hub-Signature`), à vérifier | `repo:push`, `pullrequest:*` | REST 2.0 |
| Aucune / autre | — | — | commits vus en local seulement |

- **Ordre** : GitHub, puis GitLab et Gitea/Forgejo. Bitbucket seulement si quelqu'un le demande.
- **Connexion** = type de forge, URL de base (pour l'auto-hébergé), secret de webhook, et jeton d'API facultatif
  (jeton personnel à droits fins ou jeton de projet) pour le rattrapage et les dépôts privés.
- **Webhook simple** en v1 : sur un dépôt, une organisation ou un groupe, avec le secret de la connexion. Pas de
  GitHub App au départ : chaque instance auto-hébergée devrait créer la sienne, pour un gain limité tant qu'un
  jeton suffit.
- **Code** : `services/app/forges/`.
  - `base.py` définit l'interface `verify(request, secret)`, `parse(event, payload) → list[NormalizedEvent]`
    et `backfill(repo, since)` ;
  - un module par forge (`github.py`, `gitlab.py`, `gitea.py`) ;
  - des charges utiles enregistrées servent de jeux de test.

## 5. Modèle de données — migration à numéroter après celles du plan 06

| Table | Colonnes | Sync |
|---|---|---|
| `clockifai_private.forge_connections` | `id`, `workspace_id`, `kind` (`github`, `gitlab`, `gitea`, `forgejo`, `bitbucket`), `name`, `base_url`, `webhook_secret`, `api_token`, `created_by`, `created_at`, `disabled_at` | non |
| `clockifai_private.forge_deliveries` | `connection_id`, `delivery_id` (unique par connexion), `event`, `received_at`, `processed_at`, `error`. Idempotence et diagnostic, purgé après 14 jours | non |
| `public.code_repositories` (plan 06) | `+ connection_id`, `web_url`, `default_branch` | non |
| `public.code_commits` (plan 06) | `+ pushed_at`, `url`, `author_name`, `author_login` | non |
| `public.code_branches` | `workspace_id`, `repository_id`, `name`, `head_sha`, `created_at`, `deleted_at` ; unique `(repository_id, name)` | non |
| `public.code_change_requests` | `workspace_id`, `repository_id`, `number`, `title`, `state` (`open`, `draft`, `merged`, `closed`), `source_branch`, `target_branch`, `author_login`, `author_user_id`, `url`, `opened_at`, `merged_at`, `closed_at`, `merge_sha` | non |
| `public.task_code_links` | `workspace_id`, `task_id`, `object_kind` (`branch`, `commit`, `change_request`), `object_id`, `reason` ; **champs d'affichage dénormalisés** : `repository_name`, `ref` (sha court, nom de branche, « #18 »), `title`, `url`, `state`, `author_name`, `occurred_at` ; + colonnes standard, unique `(task_id, object_kind, object_id)` | `workspace_core` |

- Seule `task_code_links` est synchronisée : la fiche d'une tâche s'affiche donc hors ligne, et le volume se
  limite aux objets rattachés.
- **Auteurs** : `author_user_id` est déduit de l'e-mail de l'auteur (compte Clockifai), ou d'un identifiant de
  forge relié à un membre. Ce sont les `identity_links` du plan 02, avec `source = 'github'`, etc.
- **RLS** :
  - lecture par les membres du workspace ;
  - écriture par le serveur, sauf sur `task_code_links`, où un membre peut insérer un lien `manual` et
    supprimer logiquement n'importe quel lien ;
  - un lien supprimé reste en base, et c'est ce qui empêche de le recréer (P4).
- **Secrets** : le secret de webhook doit rester lisible en clair pour vérifier les signatures HMAC. Il vit dans
  `clockifai_private`, lu par Flask seulement. Le passage à Supabase Vault reste une option.

## 6. Services Flask — blueprint `forges`

- Administration (JWT, `require_workspace("admin")`) :
  - `POST /api/forges` `{workspace_id, kind, name, base_url?, api_token?}` → `{id, webhook_url, webhook_secret}`
    (secret affiché une seule fois) ;
  - `GET /api/forges?workspace_id=…` : connexions, dépôts vus, dernière livraison, dernière erreur ;
  - `DELETE /api/forges/<id>`.
- `POST /api/forges/<connection_id>/webhook` (sans JWT) : vérification par l'adaptateur, puis déduplication
  par `delivery_id`. Ensuite :
  1. normalisation et upsert des dépôts, branches, commits et demandes de fusion ;
  2. règles de rattachement (§3) ;
  3. réponse 2xx rapide.
  Le traitement reste dans la requête, car les volumes sont faibles. Le passer en tâche de fond est possible si
  besoin.
- `POST /api/forges/<id>/backfill` `{repository, since}` (lot 3) : lecture par l'API de la forge, mêmes
  normalisation et règles.
- `GET /api/tasks/<id>/branch-name` : nom de branche proposé pour le bouton « créer une branche ».
- Job : `purge_forge_deliveries` chaque nuit.

## 7. Application Flutter

- **Réglages → Intégrations → Forges** (admins) :
  - ajouter une connexion : type, URL pour l'auto-hébergé, jeton facultatif ;
  - copier l'URL et le secret du webhook, avec une aide propre à chaque forge (où les coller) ;
  - voir les dépôts reçus et l'état de la dernière livraison.
- **Fiche de tâche** (nouvelle, ouverte depuis la ligne de tâche de la page Projets) :
  - en-tête : mon temps, celui de Claude et la durée calendaire (plan 06) ;
  - volet **Développement** : branches, demandes de fusion (état en couleur), commits (sha court, message,
    auteur, date, lien vers la forge, mention « local » s'il n'a jamais été poussé) ;
  - chaque lien montre sa raison, et propose « retirer » ou « rattacher à la main » ;
  - bouton **créer une branche** : copie `git switch -c <nom proposé>`. Clockifai ne crée pas la branche sur la
    forge en v1.
- **Temps de Claude et suggestions** (plan 06) : les commits faits pendant la plage, avec un lien vers la forge
  quand il existe.
- ARB FR/EN pour tous les libellés.

## 8. Tests

- `services/tests/` (unitaires, sans base) :
  - par adaptateur, sur des charges utiles enregistrées : signature valide ou invalide, objets normalisés,
    push forcé, suppression de branche, fusion d'une demande (fusion simple, squash, rebase) ;
  - normalisation de `remote_key` : ssh, https, port, sous-groupes GitLab, majuscules ;
  - analyse des références : `CLK-42`, `#12`, `groupe/projet#12`, faux positifs (`#` dans du texte) ;
  - règles de rattachement : priorités, propagation, branche par défaut jamais rattachée par contexte, lien
    retiré jamais recréé.
- `services/tests/integration/` :
  - livraison de webhook → lignes créées ;
  - livraison rejouée → rien de plus ;
  - signature invalide → 401 ;
  - RLS de `task_code_links` (lien manuel par un membre, pas d'accès d'un autre workspace) ;
  - commit vu en local puis poussé → une seule ligne, avec `pushed_at` et `url`.
- `app/test/` : fiche de tâche, avec liens groupés par type et action « retirer ».
- Bout à bout :
  - GitHub : `gh webhook forward` (extension `gh`) vers la pile locale ;
  - GitLab et Gitea : bouton « tester » du webhook, à travers un tunnel.

## 9. Lots

| Lot | Contenu | Taille |
|---|---|---|
| 1 Socle et GitHub | Migration, adaptateur GitHub (`push`, `pull_request`, `create`, `delete`), règles §3, administration des connexions, fiche de tâche et volet Développement. Prérequis : plan 06 lot 1 (`code_repositories`, `code_commits`) | M |
| 2 GitLab et Gitea/Forgejo | Deux adaptateurs de plus et leurs jeux de test | S chacun |
| 3 Rattrapage et auteurs | `backfill` par API, rapprochement auteurs ↔ membres (`identity_links`) | S/M |
| 4 Issues | Issues importées comme tâches (`external_source` / `external_id`, plan 02 / 04 §4), références `#12`, tâche terminée à la fusion de sa demande | M |
| 5 Bitbucket | À la demande | S |

## 10. Points d'attention

- **Charges utiles tronquées** : GitLab ne met que 20 commits par push, et GitHub a aussi une limite. Le total
  annoncé permet de détecter le manque, et le rattrapage par API (lot 3) complète.
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

## 11. Questions à trancher

1. GitHub : webhook simple (proposé), ou GitHub App dès le départ ?
2. Propagation automatique d'un commit de contexte à sa branche (proposé : oui, sauf branche par défaut) ?
3. Issues importées comme tâches (lot 4), ou tâches Clockifai seulement ?
4. Bouton « créer une branche » : copier la commande (proposé), ou créer la branche sur la forge par l'API ?
5. Format du nom de branche sans numéro `CLK-42` : identifiant court de la tâche + titre (proposé) ?
