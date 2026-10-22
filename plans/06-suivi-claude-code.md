# Suivi du temps par Claude Code (hooks + connecteur MCP) — plan

> Objectif : mesurer le temps réellement passé sur chaque projet quand on travaille avec des agents
> Claude Code, **y compris quand on a quitté la fenêtre** pendant que l'agent travaille, et le
> transformer en **suggestions d'entrées** à valider (saisie a posteriori). Un connecteur MCP permet
> ensuite de consulter, valider et décrire ce temps depuis Claude.

## 1. Constat

| Sujet | État | Où |
|---|---|---|
| Façon de travailler visée | Plusieurs fenêtres VSCode, un agent Claude Code par projet ; on lance un prompt puis on va ailleurs | — |
| Fenêtre active (modèle WakaTime) | Mesure le temps où l'on tape, **pas** celui où l'agent travaille seul : écarté comme source principale | — |
| Origine d'une entrée | Aucune colonne `source` ; le plan 02 prévoit `source` (`app`, `kiosk`, `fidwork`) et `external_id` | `0001_core.sql`, `02-integration-fidwork.md` §5 |
| Chronomètres simultanés | `workspaces.max_running_timers` (1 par défaut, 0 = illimité), en cours | `0011_parallel_timers.sql`, `05-chronometres-paralleles.md` |
| Authentification Flask | JWT Supabase (`require_user`) ou jeton d'appareil kiosque haché (`X-Kiosk-Token`) ; **pas de jeton personnel** | `auth.py`, `routes/kiosk.py` |
| Tâches de fond | APScheduler dans le process Flask (`auto_stop_long_timers`, `purge_soft_deleted`) | `jobs/scheduler.py`, `jobs/tasks.py` |
| Écritures client | `put` → upsert, `patch` → update par `id` | `app/lib/data/powersync/connector.dart` |

## 2. Ce que fournit Claude Code (vérifié dans la doc, octobre 2026)

- **Hooks** : `UserPromptSubmit`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `Notification`.
  Champs communs sur stdin : `session_id`, `prompt_id`, `cwd`, `transcript_path`, `hook_event_name`, `permission_mode`.
  `UserPromptSubmit` contient le texte du `prompt` ; `Stop` contient `last_assistant_message` ;
  `PostToolUse` contient `tool_name`, `tool_input`, `tool_response` ; `SessionEnd` contient `reason`.
- `"async": true` sur un hook de type commande : exécution en arrière-plan, sans bloquer Claude.
- Sur `UserPromptSubmit`, ce que le script écrit sur stdout est **injecté dans le contexte** : le script n'écrit rien.
- **Plugin** : `.claude-plugin/plugin.json`, `hooks/hooks.json`, `.mcp.json`, `commands/`, `skills/` à la racine
  du plugin ; `${CLAUDE_PLUGIN_ROOT}` pour les scripts. `userConfig` demande les réglages à l'activation
  (`"sensitive": true` → trousseau du système) : lus par `${user_config.KEY}` dans `.mcp.json`, et par
  `CLAUDE_PLUGIN_OPTION_<KEY>` dans les hooks.
- **Marketplace** : `.claude-plugin/marketplace.json` dans un dépôt git, plugin dans un sous-dossier ;
  `/plugin marketplace add <dépôt>`.
- **MCP distant** dans `.mcp.json` : `"type": "http"`, `url`, `headers` avec expansion de variables.
- **Connecteurs claude.ai** : OAuth 2.0 avec enregistrement dynamique des clients. Ils sont visibles dans
  Claude Code seulement avec une connexion par abonnement claude.ai.
- **À vérifier** : la doc ne confirme pas explicitement que les hooks se déclenchent dans l'extension VSCode
  (son panneau Hooks les liste). Premier test du lot 1.

## 3. Décisions de conception

**D1. La mesure vient des hooks, pas de la fenêtre active ni du modèle.** Un hook s'exécute à chaque
événement, sans exception. Un outil MCP n'est appelé que si le modèle le décide, ce qui ne convient pas
pour mesurer. Le MCP sert à **consulter, valider et décrire** (D8).

**D2. Les événements produisent des suggestions, pas des entrées.** Cela reste cohérent avec la saisie a
posteriori, et les heuristiques (D5) sont des estimations. Une suggestion acceptée devient une
`time_entry` ordinaire (`source = 'claude_code'`), soumise aux mêmes gardes : verrouillage, périodes
approuvées, facturation.

**D3. Jetons d'API personnels.** Ils reprennent le modèle des appareils kiosque : jeton aléatoire
`clk_…` affiché une seule fois, haché en SHA-256, rattaché à **un utilisateur et un workspace**,
révocable, avec `last_used_at`. Un jeton par machine est recommandé. Les jetons sont stockés dans
`clockifai_private` et gérés par Flask.

**D4. Événements bruts côté serveur, jamais répliqués.** Ils vont dans `clockifai_private.activity_events`,
hors API et hors PowerSync, et sont purgés après 30 jours. Le script **filtre par liste blanche** :
il n'envoie jamais `tool_input`, `tool_response` ni `transcript_path`.

**D5. Règles d'agrégation** (fonction pure, testable sans base) :
1. **Agent actif** : de `UserPromptSubmit` à `Stop` dans une session. Les `PostToolUse` (au plus un par minute
   et par session) maintiennent l'intervalle ouvert pendant les longues exécutions, y compris celles des
   sous-agents.
2. **Relecture** : après `Stop`, l'intervalle est prolongé jusqu'au prompt suivant de la session s'il
   arrive dans les `GAP_MERGE` minutes (15 par défaut), sinon de `REVIEW_TAIL` minutes (10 par défaut).
   Cette marge est la partie estimée.
3. **Session interrompue** : sans `Stop` ni `SessionEnd`, l'intervalle se ferme au dernier événement plus
   `IDLE_TIMEOUT` (10 minutes).
4. **Sessions simultanées** : le comportement suit `workspaces.max_running_timers` (plan 05).
   - `1` : pas de chevauchement. Chaque instant va à la session qui a reçu le **dernier prompt**, là où est
     l'attention. Cette règle ne dépend que du passé, donc l'attribution d'un instant écoulé ne change plus.
   - `> 1` ou `0` : une suggestion par session, chevauchements admis. Le cumul peut dépasser le temps réel,
     comme pour les chronomètres simultanés.
5. **Regroupement** : les intervalles consécutifs d'un même (projet, tâche) séparés de moins de `GAP_MERGE`
   forment une seule suggestion. La suggestion garde le détail `agent_seconds` et `review_seconds`.

**D6. Rattachement au projet par règles personnelles.** Table `activity_rules` : un dépôt
(`git_remote` normalisé, sans protocole ni `.git`) ou un préfixe de chemin (`cwd`) mène à un projet,
et optionnellement à une tâche. Le dépôt prime sur le chemin. Une suggestion sans règle affiche le nom
du dépôt, et choisir son projet propose « toujours rattacher ce dépôt ». La branche donne la tâche quand
elle contient un numéro de ticket (`CLK-42`, plan 04), une fois ces numéros en place.

**D7. Recalcul différentiel des suggestions en attente.** Le job recalcule les journées touchées par de
nouveaux événements. Chaque suggestion a une clé stable, `uuid5(user, session_id, début)`. Les suggestions
`pending` absentes du nouveau calcul sont supprimées logiquement, et les autres mises à jour. Une suggestion
acceptée ou ignorée est figée, et sa plage est exclue des calculs suivants. C'est le même principe que
`team_scope` (plan 03, D3).

**D8. Serveur MCP séparé**, sur le même Postgres. Flask (un seul worker synchrone) convient mal au
transport MCP en HTTP. Il partage le code de `services/` (`db.py`) et tourne dans un second conteneur
construit depuis la même image, avec le SDK Python `mcp` (HTTP en flux, sans état). Les écritures
s'exécutent **comme l'utilisateur** : `set local role authenticated` et
`set_config('request.jwt.claims', …, true)`, pour que la RLS et les triggers s'appliquent exactement comme
depuis l'app (garde, `created_by`, limite de chronomètres). Il faut vérifier que `postgres` peut prendre
le rôle `authenticated`.

**D9. Description des entrées.** Les hooks savent *quand* et *où*, pas *sur quoi*. Trois sources, par
ordre de préférence :
- l'outil MCP `describe_current_work`, appelé par Claude (commande `/clockifai:decrire`) ;
- en option, un extrait (200 caractères) du premier prompt ou de `last_assistant_message`, envoyé seulement si l'option du plugin `send_excerpts` est activée ;
- à défaut, le dépôt et la branche.

**D10. Connecteur claude.ai (OAuth) en dernier, et conditionnel.** Pour Claude Code, un jeton personnel
dans l'en-tête suffit. Un connecteur claude.ai (web, bureau, mobile) demande un serveur OAuth : il faut
vérifier ce que Supabase Auth propose dans la version auto-hébergée épinglée (v1.26.08). Sans hooks hors
de Claude Code, le connecteur ne servirait là qu'à consulter et saisir.

## 4. Modèle de données — migration `0012_activity.sql` (+ `0012_activity.admin.sql` si nécessaire)

Numéro à confirmer au moment de l'implémentation (0011 est pris par le plan 05).

| Table | Colonnes | Sync |
|---|---|---|
| `clockifai_private.api_tokens` | `id`, `workspace_id`, `user_id`, `name`, `token_hash` (unique), `last_used_at`, `created_at`, `revoked_at` | non |
| `clockifai_private.activity_events` | `id` (= `event_id` client, clé d'idempotence), `workspace_id`, `user_id`, `token_id`, `source` (`claude_code`), `session_id`, `kind` (`prompt`, `tool`, `stop`, `session_start`, `session_end`), `occurred_at`, `received_at`, `cwd`, `git_remote`, `git_branch`, `excerpt`, `processed_at` ; index `(user_id, occurred_at)` | non |
| `public.activity_rules` | `workspace_id`, `user_id`, `match_kind` (`git_remote`, `path_prefix`), `pattern`, `project_id`, `task_id`, + colonnes standard | `my_time_entries` |
| `public.time_suggestions` | `workspace_id`, `user_id`, `source`, `session_id`, `project_id`, `task_id`, `description`, `start_at`, `end_at`, `agent_seconds`, `review_seconds`, `cwd`, `git_remote`, `git_branch`, `status` (`pending`, `accepted`, `dismissed`), `time_entry_id`, + colonnes standard | `my_time_entries` |
| `public.time_entries` | `+ source text not null default 'app'`. C'est la même colonne que dans le plan 02 : le premier lot livré la crée, avec la valeur `claude_code` parmi les valeurs admises | existante |

RLS :
- `activity_rules` : lecture et écriture de ses propres lignes, membre du workspace.
- `time_suggestions` : lecture de ses propres lignes. **Pas d'insertion côté client**, puisque seul le job crée.
  En mise à jour, le client ne change que `status`, `project_id`, `task_id`, `description` et `time_entry_id`,
  ce que contrôle un trigger de garde.
- Comme le connecteur envoie `patch` → `update`, aucune politique INSERT n'est nécessaire sur cette table.

À aligner, comme toute colonne synchronisée : la migration, `schema.dart`, `database.dart`
(`make app-gen`) et `sync-config.yaml` (flux `my_time_entries`).

## 5. Services Flask

- `POST /api/tokens` `{workspace_id, name}` → `{id, token}`, `GET /api/tokens?workspace_id=…` et
  `DELETE /api/tokens/<id>` (JWT utilisateur, `require_workspace`). Ces routes calquent `kiosk/devices`.
- Décorateur `require_api_token` (`Authorization: Bearer clk_…`) → `g.user`, `g.workspace_id`. Il contrôle
  que l'utilisateur est toujours membre actif du workspace et met à jour `last_used_at`.
- `POST /api/activity/events` : lot d'événements (≤ 200). Insertion `on conflict (id) do nothing` → 202.
  Les événements datés de plus de 5 minutes dans le futur ou de plus de 7 jours sont rejetés.
- `GET /api/activity/today` : total du jour et répartition par projet, suggestions comprises. Il sert à la
  ligne d'état et au MCP.
- Jobs :
  - `aggregate_activity` toutes les 5 minutes : appelle la fonction pure de D5, puis applique le recalcul différentiel de D7 ;
  - `purge_activity_events` chaque nuit (30 jours).

## 6. Plugin Claude Code — `integrations/claude-code/`

```
.claude-plugin/marketplace.json        (racine du dépôt → plugin ./integrations/claude-code)
integrations/claude-code/
├─ .claude-plugin/plugin.json          userConfig : url, token (sensitive), send_excerpts
├─ hooks/hooks.json                    UserPromptSubmit, PostToolUse, Stop, SessionStart, SessionEnd → async
├─ scripts/clockifai_hook.py           Python 3, bibliothèque standard uniquement
├─ .mcp.json                           {"clockifai": {"type": "http", "url": "${user_config.url}/mcp",
│                                        "headers": {"Authorization": "Bearer ${user_config.token}"}}}
└─ commands/  aujourdhui.md, decrire.md, valider.md
```

Le script `clockifai_hook.py` :
- lit stdin et garde la liste blanche de D4 ;
- ajoute `git remote get-url origin` et `git branch --show-current` à partir de `cwd` ;
- génère `event_id` (uuid4) et `occurred_at` (UTC) ;
- **n'écrit rien sur stdout**, et termine toujours avec le code 0 ;
- limite `PostToolUse` à un événement par minute et par session (horodatage dans `~/.cache/clockifai/`) ;
- en cas d'échec réseau (délai de 2 s), ajoute l'événement à `~/.cache/clockifai/spool.jsonl`, renvoyé au
  prochain appel réussi ;
- en dehors d'un dépôt git, envoie seulement `cwd`.

Les commandes :
- `/clockifai:aujourdhui` : résumé du jour (MCP `get_summary`).
- `/clockifai:decrire` : Claude résume en une ligne le travail de la session et appelle `describe_current_work`.
- `/clockifai:valider` : liste les suggestions en attente et les accepte ou les ignore après confirmation.

## 7. Serveur MCP — service `mcp` dans `deploy/`

- Conteneur `clockifai-mcp`, même image que `services`, avec une autre commande. Caddy route `/mcp`.
- Authentification : jeton personnel (D3) ; OAuth plus tard (D10).
- Outils :

| Outil | Rôle |
|---|---|
| `list_projects(query?)` | projets et tâches du workspace |
| `get_summary(period, group_by)` | temps saisi et suggéré, par projet, tâche ou jour |
| `list_suggestions(day?)` | suggestions en attente |
| `accept_suggestions(ids, project_id?, task_id?, description?)` | crée les entrées et marque les suggestions acceptées, dans une transaction |
| `dismiss_suggestions(ids)` | ignore les suggestions |
| `describe_current_work(cwd, description)` | décrit la suggestion la plus récente de ce dossier, en attente ou acceptée du jour |
| `add_time_entry(project_id, start, end, description, task_id?)` | saisie manuelle |
| `map_repository(git_remote or path, project_id, task_id?)` | crée une `activity_rule` et réattribue les suggestions en attente |

## 8. Application Flutter

- **Réglages → Intégrations** : créer un jeton (nom), qui s'affiche une seule fois avec les instructions
  d'installation du plugin ; lister les jetons ; les révoquer (via Flask).
- **Suggestions** : un bandeau « N suggestions » dans la page des entrées du jour mène à la liste.
  - Chaque ligne : projet (ou dépôt inconnu → choix du projet et règle), plage, durée (détail agent / relecture), description modifiable.
  - Actions : accepter, ignorer, tout accepter.
  - L'acceptation crée l'entrée (`source = 'claude_code'`, taux et facturable selon les règles actuelles) et met à jour la suggestion, en une transaction locale.
- **Règles de rattachement** : liste, modification et suppression.
- **Calendrier** (lot 4) : suggestions affichées en blocs en pointillés, à accepter d'un clic.
- **Entrées** : petite étiquette « Claude Code » quand `source = 'claude_code'`.
- ARB FR/EN pour tous les libellés.

## 9. Tests

- `services/tests/` (unitaires, sans base) : la fonction d'agrégation de D5.
  - session simple ;
  - prompt suivant rapproché (fusion) ou éloigné (marge de relecture) ;
  - session interrompue sans `Stop` ;
  - deux sessions simultanées, avec limite 1 (attribution à l'attention) et limite 0 (chevauchement) ;
  - événements arrivés en retard ;
  - plages déjà acceptées exclues ;
  - normalisation de `git_remote` ;
  - priorité des règles.
- `services/tests/integration/` :
  - jetons : création, révocation, jeton d'un ancien membre refusé ;
  - envoi d'événements idempotent ;
  - le job crée et met à jour les suggestions ;
  - RLS : pas d'accès aux suggestions d'autrui, pas d'insertion client ;
  - MCP : une écriture dans une période verrouillée est rejetée par la garde.
- `app/test/` : acceptation d'une suggestion (entrée créée et suggestion acceptée), application d'une règle.
- Plugin : le script avec un stdin factice et un serveur HTTP local.
  - stdout vide ;
  - `tool_input` jamais envoyé ;
  - file locale remplie quand le serveur est coupé, puis vidée.

## 10. Lots

| Lot | Contenu | Taille |
|---|---|---|
| 1 Mesure | Migration (jetons, événements, `source`), Flask (jetons, `events`), plugin minimal (hooks seuls), écran des jetons ; vérifier les hooks dans l'extension VSCode | M |
| 2 Suggestions | Règles, `time_suggestions`, job d'agrégation, écran Suggestions et règles, flux PowerSync | L |
| 3 MCP | Service `mcp`, outils, `.mcp.json` et commandes du plugin | M |
| 4 Confort | `GET /api/activity/today` dans la ligne d'état, blocs du calendrier, extraits de prompt (D9), activité clavier VSCode pour mesurer la relecture au lieu de l'estimer | S/M |
| 5 Connecteur claude.ai | OAuth (selon Supabase Auth auto-hébergé), publication du connecteur | M, conditionnel |

## 11. Points d'attention

- **Horloge client** : `occurred_at` est fourni par le poste et `received_at` est conservé ; on rejette les écarts aberrants (§5).
- **Confidentialité** : les événements bruts ne sont visibles de personne dans l'app. Les suggestions sont personnelles. Les managers ne voient que les entrées acceptées.
- **Sous-agents en arrière-plan** : ils continuent après `Stop`. Si leurs `PostToolUse` arrivent, l'intervalle reste ouvert, comme voulu. À vérifier en conditions réelles.
- **Attente d'une autorisation** : l'événement `Notification` pendant qu'un agent attend une permission n'est pas traité en v1. Ce temps est compté jusqu'à `IDLE_TIMEOUT`.
- **Plusieurs workspaces** : un jeton est lié à un seul workspace. Les dépôts de l'autre workspace ont besoin d'un autre jeton ou d'un réglage de dossier, qui reste à concevoir.

## 12. Questions à trancher

1. Valeurs par défaut de `GAP_MERGE` (15 min), `REVIEW_TAIL` (10 min) et `IDLE_TIMEOUT` (10 min) ; réglables par utilisateur ?
2. Sessions simultanées : suivre `max_running_timers` du workspace (proposé), ou un réglage personnel ?
3. `send_excerpts` désactivé par défaut (proposé) ?
4. Règles de rattachement seulement personnelles en v1 (proposé), ou aussi des règles de workspace posées par un admin ?
5. Acceptation automatique des suggestions après N jours : non (proposé) ?
