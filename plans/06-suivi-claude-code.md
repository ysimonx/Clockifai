# Suivi du temps : Claude et moi (hooks, activité éditeur, connecteur MCP) — plan

> Objectif : mesurer, projet par projet, **deux temps distincts** :
> - le **temps de Claude**, pendant que les agents Claude Code travaillent, y compris quand on a quitté la fenêtre ;
> - **mon temps**, pendant que je travaille moi aussi : écrire un prompt, relire, coder, tester.
>
> Le temps de Claude est mesuré exactement et enregistré directement. Mon temps est estimé à partir de
> signaux d'activité et proposé en **suggestions d'entrées** à valider (saisie a posteriori). Un connecteur
> MCP permet de consulter, valider et décrire ces temps depuis Claude.

## 1. Constat

| Sujet | État | Où |
|---|---|---|
| Façon de travailler visée | Plusieurs fenêtres VSCode, un agent Claude Code par projet ; on lance un prompt, puis on relit, on teste ou on passe à un autre projet | — |
| Hooks Claude Code | Disent exactement quand un agent travaille, mais rien de ce que je fais entre deux prompts | §2 |
| Activité dans l'éditeur (modèle WakaTime) | Dit quand je travaille dans un projet, mais rien du travail de l'agent fenêtre quittée. **Les deux sources sont complémentaires** | — |
| Origine d'une entrée | Aucune colonne `source` ; le plan 02 prévoit `source` (`app`, `kiosk`, `fidwork`) et `external_id` | `0001_core.sql`, `02-integration-fidwork.md` §5 |
| Chronomètres simultanés | `workspaces.max_running_timers` (1 par défaut, 0 = illimité) | `0011_parallel_timers.sql`, `05-chronometres-paralleles.md` |
| App macOS | Barre de menus native, lancée à l'ouverture de session, **en bac à sable** (`app-sandbox`, `network.client`) | `06-macos-barre-de-menus.md`, `app/macos/Runner/` |
| Authentification Flask | JWT Supabase (`require_user`) ou jeton d'appareil kiosque haché (`X-Kiosk-Token`) ; **pas de jeton personnel** | `auth.py`, `routes/kiosk.py` |
| Tâches de fond | APScheduler dans le process Flask | `jobs/scheduler.py`, `jobs/tasks.py` |
| Écritures client | `put` → upsert, `patch` → update par `id` | `app/lib/data/powersync/connector.dart` |

## 2. Ce que fournissent les outils

**Claude Code** (vérifié dans la doc, octobre 2026) :
- **Hooks** : `UserPromptSubmit`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `Notification`.
  - Champs communs sur stdin : `session_id`, `prompt_id`, `cwd`, `transcript_path`, `hook_event_name`, `permission_mode`.
  - `UserPromptSubmit` contient le texte du `prompt` ; `Stop` contient `last_assistant_message`.
  - `PostToolUse` contient `tool_name`, `tool_input`, `tool_response` ; `SessionEnd` contient `reason`.
- `"async": true` sur un hook de type commande : exécution en arrière-plan, sans bloquer Claude.
- Sur `UserPromptSubmit`, ce que le script écrit sur stdout est **injecté dans le contexte** : le script n'écrit rien.
- **Plugin** :
  - `.claude-plugin/plugin.json`, `hooks/hooks.json`, `.mcp.json`, `commands/` et `skills/` à la racine du plugin ;
  - `${CLAUDE_PLUGIN_ROOT}` pour les scripts ;
  - `userConfig` demande les réglages à l'activation (`"sensitive": true` → trousseau du système). Ils sont lus par `${user_config.KEY}` dans `.mcp.json` et par `CLAUDE_PLUGIN_OPTION_<KEY>` dans les hooks.
- **Marketplace** : `.claude-plugin/marketplace.json` dans un dépôt git, `/plugin marketplace add <dépôt>`.
- **MCP distant** dans `.mcp.json` : `"type": "http"`, `url`, `headers` avec expansion de variables.
- **Connecteurs claude.ai** : OAuth 2.0 avec enregistrement dynamique des clients. Ils sont visibles dans
  Claude Code seulement avec une connexion par abonnement claude.ai.
- **À vérifier** : la doc ne confirme pas explicitement que les hooks se déclenchent dans l'extension VSCode
  (son panneau Hooks les liste). Premier test du lot 1.

**WakaTime** (formats à confirmer au lot 2 sur `wakatime-cli` et le serveur compatible Wakapi) :
- Les extensions officielles (VSCode, JetBrains, terminal, navigateurs…) passent toutes par `wakatime-cli`.
- `wakatime-cli` lit `api_url` et `api_key` dans `~/.wakatime.cfg`. Il envoie
  `POST {api_url}/users/current/heartbeats.bulk` avec `Authorization: Basic base64(api_key)`.
- Les heartbeats partent toutes les ~2 minutes pendant l'activité, et à chaque changement de fichier. Ils
  contiennent `time`, `project` (par défaut le nom du dossier racine git), `branch`, `entity` (le fichier),
  `category`, `language`, `is_write` et l'éditeur (dans `User-Agent`).
- L'extension VSCode affiche le total du jour via `GET {api_url}/users/current/statusbar/today`.
- `wakatime-cli` exige une clé au **format UUID**.

**macOS** : la durée d'inactivité du poste (clavier, souris) est lisible sans autorisation
(`CGEventSource.secondsSinceLastEventType`). Son fonctionnement en bac à sable est à vérifier.

## 3. Décisions de conception

**D1. Deux pistes, deux mesures, jamais additionnées.**
- **Piste Claude** : intervalles de travail des agents, mesurés par les hooks.
- **Piste humaine** : mes intervalles d'activité, mesurés par plusieurs signaux (D4).

Pour un projet et une période, on affiche **mon temps**, **le temps de Claude** et la **durée calendaire**
(union des deux). Pendant qu'un agent travaille et que je relis, les deux pistes avancent ensemble.

**D2. Le temps de Claude est enregistré directement dans `agent_time`, pas dans `time_entries`.**
- La mesure est exacte (début et fin de tour) : aucune validation n'est nécessaire, mais les lignes restent
  modifiables (projet, description) et supprimables.
- Mettre ce temps dans `time_entries` le compterait deux fois dans les feuilles de temps, les approbations,
  les totaux et les factures.
- Une ligne est **ouverte en direct** à la réception du prompt et **fermée** au `Stop`. On peut donc afficher
  « Claude travaille sur Clockifai depuis 12 min ».
- Alternative écartée pour l'instant (question 1, §12) : un membre « agent » par personne, avec de vraies
  entrées. Les rapports par utilisateur et l'équipe le montreraient tel quel, mais il faudrait un faux compte
  `auth.users` et l'exclure de l'inscription, des invitations, des approbations, du kiosque et des listes de
  membres.

**D3. Mon temps devient des suggestions, puis des entrées.** Il est estimé : une pause de moins de
15 minutes reste du travail. Une suggestion acceptée devient une `time_entry` ordinaire
(`source = 'activity'`), soumise aux mêmes gardes : verrouillage, périodes approuvées, facturation.

**D4. Signaux de mon activité**, dans l'ordre des lots :
1. **Prompts** (hook `UserPromptSubmit`) : écrire un prompt, c'est travailler.
2. **Éditeurs** : heartbeats WakaTime (D6), reçus par une API compatible. Aucune extension à écrire : il suffit
   de pointer `~/.wakatime.cfg` vers Clockifai. Cela couvre VSCode, JetBrains, le terminal, etc.
3. **Présence au poste** (app macOS, lot 4) : l'app signale chaque minute si le poste est actif. Elle ne voit
   pas le projet, mais elle **coupe** un intervalle quand on a quitté le poste, au lieu de compter jusqu'à
   15 minutes d'absence.

Lire la réponse de Claude dans son panneau ne produit aucun signal. C'est le délai de 15 minutes (D8) qui
la couvre, jusqu'à l'action suivante.

**D5. Jetons d'API personnels**, sur le modèle des appareils kiosque :
- le jeton est un **UUID v4**, pour être accepté par `wakatime-cli` ;
- affiché une seule fois, haché en SHA-256, rattaché à **un utilisateur et un workspace**, révocable, avec `last_used_at` ;
- un jeton par machine, utilisé à la fois par les hooks, `wakatime-cli` et le MCP ;
- stockés dans `clockifai_private` et gérés par Flask.

**D6. Événements bruts côté serveur, jamais répliqués.** Ils vont dans `clockifai_private.activity_events`,
hors API et hors PowerSync, et sont purgés après 30 jours. Les données sont réduites au départ :
- **Hooks** : liste blanche dans le script. Jamais `tool_input`, `tool_response` ni `transcript_path`.
- **Heartbeats** : on garde `time`, `project`, `branch`, `category`, `language`, l'éditeur et la machine.
  On ne garde pas `entity` (le chemin du fichier).

**D7. Règles de la piste Claude** (calculées à la réception des événements) :
1. Un `UserPromptSubmit` ouvre une ligne `agent_time` pour la session. Si la ligne précédente de la session
   s'est fermée il y a moins de `AGENT_GAP` (5 min), on la rouvre au lieu d'en créer une nouvelle.
2. Un `Stop` ou un `SessionEnd` ferme la ligne à l'heure de l'événement. Les `PostToolUse` (au plus un par
   minute et par session) servent de signe de vie, y compris pour les sous-agents.
3. Une ligne ouverte sans événement depuis `IDLE_TIMEOUT` (10 min) est fermée par un job à l'heure de son
   dernier événement (session plantée).
4. **Sessions simultanées** : une ligne par session, sans limite. Deux agents pendant une heure font deux
   heures de Claude. `max_running_timers` ne s'applique pas ici : il concerne mes chronomètres.

**D8. Règles de la piste humaine** (fonction pure, testable sans base, appelée par un job) :
1. Mes événements (prompts, heartbeats) sont regroupés en intervalles : un écart de moins de
   `HUMAN_TIMEOUT` (15 min, comme WakaTime) ne coupe pas. Un intervalle va de son premier événement au
   dernier, plus 2 minutes (le rythme des heartbeats).
2. **Une seule attention** : chaque instant va au projet de mon **dernier** événement. Mes suggestions ne se
   chevauchent jamais, quel que soit `max_running_timers`. Cette règle ne dépend que du passé : l'attribution
   d'un instant écoulé ne change plus.
3. **Présence** (lot 4) : une période où le poste est inactif plus de `IDLE_CUT` (5 min) coupe l'intervalle.
4. Les plages déjà acceptées ou ignorées sont exclues.
5. **Recalcul différentiel** des suggestions en attente. Chaque suggestion a une clé stable,
   `uuid5(user, projet, début)`. Celles qui disparaissent du calcul sont supprimées logiquement, les autres
   mises à jour. C'est le même principe que `team_scope` (plan 03, D3).

**D9. Rattachement au projet, commun aux deux pistes.** La clé principale est le **nom du dépôt**, c'est-à-dire
le nom du dossier racine git. C'est ce que `wakatime-cli` envoie comme `project`, et le script de hook le
calcule de la même façon.
- Table `activity_rules` : un nom de dépôt ou un préfixe de chemin (`cwd`) mène à un projet, et
  optionnellement à une tâche. Le chemin, plus précis, prime.
- Une ligne sans règle affiche le nom du dépôt ; choisir son projet propose « toujours rattacher ce dépôt »,
  et la règle réattribue aussi les lignes passées en attente.
- La branche donnera la tâche quand elle contiendra un numéro de ticket (`CLK-42`, plan 04).

**D10. Descriptions.**
- Pour une ligne `agent_time` : l'outil MCP `describe_current_work`, appelé par Claude (commande
  `/clockifai:decrire`). En option, un extrait (200 caractères) du prompt ou de `last_assistant_message`, si
  l'option `send_excerpts` du plugin est activée.
- Pour une suggestion humaine : préremplie avec les descriptions des lignes `agent_time` du même projet qui la
  chevauchent (« ce que Claude faisait pendant ce temps »), sinon avec le dépôt et la branche.

**D11. Serveur MCP séparé**, sur le même Postgres. Flask (un seul worker synchrone) convient mal au
transport MCP en HTTP.
- Il partage le code de `services/` (`db.py`) et tourne dans un second conteneur construit depuis la même
  image, avec le SDK Python `mcp` (HTTP en flux, sans état).
- Les écritures s'exécutent **comme l'utilisateur** : `set local role authenticated` et
  `set_config('request.jwt.claims', …, true)`. La RLS et les triggers s'appliquent donc exactement comme
  depuis l'app. Il faut vérifier que `postgres` peut prendre le rôle `authenticated`.

**D12. Connecteur claude.ai (OAuth) en dernier, et conditionnel.**
- Pour Claude Code, un jeton personnel dans l'en-tête suffit.
- Un connecteur claude.ai demande un serveur OAuth : il faut vérifier ce que Supabase Auth propose dans la
  version auto-hébergée épinglée (v1.26.08).
- Comme les hooks n'existent pas hors de Claude Code, le connecteur ne servirait là qu'à consulter et saisir.

## 4. Modèle de données — migration `0012_activity.sql`

| Table | Colonnes | Sync |
|---|---|---|
| `clockifai_private.api_tokens` | `id`, `workspace_id`, `user_id`, `name`, `token_hash` (unique), `last_used_at`, `created_at`, `revoked_at` | non |
| `clockifai_private.activity_events` | `id` (clé d'idempotence : `event_id` du hook, ou hash du heartbeat), `workspace_id`, `user_id`, `token_id`, `actor` (`agent`, `human`), `kind` (`prompt`, `agent_tool`, `agent_stop`, `session_start`, `session_end`, `editor`, `presence`), `occurred_at`, `received_at`, `session_id`, `repo`, `cwd`, `git_remote`, `git_branch`, `editor`, `machine`, `category`, `active` (présence), `excerpt` ; index `(user_id, occurred_at)` | non |
| `public.activity_rules` | `workspace_id`, `user_id`, `match_kind` (`repo`, `path_prefix`), `pattern`, `project_id`, `task_id`, + colonnes standard | `my_time_entries` |
| `public.agent_time` | `workspace_id`, `user_id` (la personne qui pilote l'agent), `session_id`, `project_id`, `task_id`, `description`, `start_at`, `end_at` (nul = en cours), `last_event_at`, `prompt_count`, `repo`, `git_branch`, `cwd`, + colonnes standard | `my_time_entries`, puis `team_data` et `managed_team` |
| `public.time_suggestions` | `workspace_id`, `user_id`, `project_id`, `task_id`, `description`, `start_at`, `end_at`, `repo`, `git_branch`, `signals` (jsonb : nombre de prompts et de heartbeats, éditeurs), `status` (`pending`, `accepted`, `dismissed`), `time_entry_id`, + colonnes standard | `my_time_entries` |
| `public.time_entries` | `+ source text not null default 'app'`. C'est la même colonne que dans le plan 02 : le premier lot livré la crée, avec la valeur `activity` parmi les valeurs admises | existante |

RLS :
- `activity_rules` : lecture et écriture de ses propres lignes, membre du workspace.
- `agent_time` :
  - lecture de ses lignes ; managers et chefs d'équipe selon `manages()` ;
  - mise à jour de `project_id`, `task_id` et `description`, et suppression logique, par la personne seulement ;
  - **pas d'insertion côté client**, puisque seul le serveur crée.
- `time_suggestions` :
  - lecture de ses lignes ; pas d'insertion côté client ;
  - en mise à jour, le client ne change que `status`, `project_id`, `task_id`, `description` et `time_entry_id`, ce que contrôle un trigger de garde.
- Comme le connecteur envoie `patch` → `update`, aucune politique INSERT n'est nécessaire sur ces deux tables.

À aligner, comme toute colonne synchronisée : la migration, `schema.dart`, `database.dart`
(`make app-gen`) et `sync-config.yaml`.

## 5. Services Flask

- `POST /api/tokens` `{workspace_id, name}` → `{id, token}`, `GET /api/tokens?workspace_id=…` et
  `DELETE /api/tokens/<id>` (JWT utilisateur, `require_workspace`). Ces routes calquent `kiosk/devices`.
- Décorateur `require_api_token` : accepte `Authorization: Bearer <uuid>` (hooks, MCP) et `Basic` (wakatime-cli)
  → `g.user`, `g.workspace_id`. Il contrôle que l'utilisateur est toujours membre actif du workspace et met à
  jour `last_used_at`.
- `POST /api/activity/events` (hooks) : lot d'événements (≤ 200), insertion `on conflict (id) do nothing`.
  **Dans la même transaction**, il applique D7 sur `agent_time` (ouvrir, rouvrir, fermer), puis répond 202.
  Les événements datés de plus de 5 minutes dans le futur ou de plus de 7 jours sont rejetés.
- **Compatibilité WakaTime**, sous `/api/compat/wakatime/v1` :
  - `users/current/heartbeats` et `heartbeats.bulk` : conversion en événements `editor` ;
  - `users/current/statusbar/today` : renvoie mon temps du jour, et celui de Claude dans les catégories.
- `GET /api/activity/today` : mon temps, celui de Claude et la durée calendaire, par projet. Il sert à la
  ligne d'état et au MCP.
- Jobs :
  - `close_stale_agent_time` toutes les minutes (D7.3) ;
  - `aggregate_human_activity` toutes les 5 minutes (D8) ;
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
- lit stdin et garde la liste blanche de D6 ;
- ajoute le dépôt (`git rev-parse --show-toplevel`, nom du dossier), `git remote get-url origin` et
  `git branch --show-current` à partir de `cwd` ;
- génère `event_id` (uuid4) et `occurred_at` (UTC) ;
- **n'écrit rien sur stdout**, et termine toujours avec le code 0 ;
- limite `PostToolUse` à un événement par minute et par session (horodatage dans `~/.cache/clockifai/`) ;
- en cas d'échec réseau (délai de 2 s), ajoute l'événement à `~/.cache/clockifai/spool.jsonl`, renvoyé au
  prochain appel réussi.

Les commandes :
- `/clockifai:aujourdhui` : mon temps et celui de Claude aujourd'hui (MCP `get_summary`).
- `/clockifai:decrire` : Claude résume en une ligne le travail de la session et appelle `describe_current_work`.
- `/clockifai:valider` : liste mes suggestions en attente et les accepte ou les ignore après confirmation.

L'activité dans l'éditeur ne passe pas par le plugin. Il suffit d'installer l'extension WakaTime et de
renseigner `~/.wakatime.cfg` (`api_url = <url>/api/compat/wakatime/v1`, `api_key = <jeton>`). L'écran des
jetons donne ces lignes toutes prêtes.

## 7. Serveur MCP — service `mcp` dans `deploy/`

- Conteneur `clockifai-mcp`, même image que `services`, avec une autre commande. Caddy route `/mcp`.
- Authentification : jeton personnel (D5) ; OAuth plus tard (D12).
- Outils :

| Outil | Rôle |
|---|---|
| `list_projects(query?)` | projets et tâches du workspace |
| `get_summary(period, group_by)` | mon temps (saisi et suggéré), celui de Claude et la durée calendaire, par projet, tâche ou jour |
| `list_suggestions(day?)` | mes suggestions en attente |
| `accept_suggestions(ids, project_id?, task_id?, description?)` | crée les entrées et marque les suggestions acceptées, dans une transaction |
| `dismiss_suggestions(ids)` | ignore les suggestions |
| `describe_current_work(cwd, description)` | décrit la ligne `agent_time` la plus récente de ce dossier |
| `add_time_entry(project_id, start, end, description, task_id?)` | saisie manuelle |
| `map_repository(repo or path, project_id, task_id?)` | crée une `activity_rule` et réattribue les lignes en attente des deux pistes |

## 8. Application Flutter

- **Réglages → Intégrations** :
  - créer un jeton (nom), affiché une seule fois avec deux blocs à copier : l'installation du plugin Claude Code et les lignes de `~/.wakatime.cfg` ;
  - lister et révoquer les jetons (via Flask).
- **Page des entrées du jour** :
  - un bandeau « Claude travaille : clockifai (12 min), fidwork (3 min) » quand des lignes `agent_time` sont ouvertes ;
  - un bandeau « N suggestions » qui mène à la liste des suggestions.
- **Suggestions** :
  - chaque ligne montre le projet (ou le dépôt inconnu → choix du projet et règle), la plage, la durée, le temps de Claude sur la même plage et une description modifiable ;
  - actions : accepter, ignorer, tout accepter ;
  - l'acceptation crée l'entrée (`source = 'activity'`, taux et facturable selon les règles actuelles) et met à jour la suggestion, en une transaction locale.
- **Temps de Claude** : liste par jour (projet, plage, description) avec modification et suppression.
- **Rapports** : une colonne « Claude » à côté du temps saisi, par projet et par tâche.
- **Calendrier** (lot 4) : les lignes `agent_time` dans une voie à part, les suggestions en blocs en pointillés.
- **Barre de menus macOS** (lot 4) : nombre d'agents actifs, et signal de présence (D4.3).
- **Entrées** : petite étiquette « Activité » quand `source = 'activity'`.
- ARB FR/EN pour tous les libellés.

## 9. Tests

- `services/tests/` (unitaires, sans base) :
  - D7 :
    - ouverture et fermeture ;
    - réouverture en deçà de `AGENT_GAP` ;
    - deux sessions simultanées ;
    - session plantée ;
    - événements en retard ou en double ;
  - D8 :
    - regroupement à 15 min ;
    - une seule attention entre deux projets ;
    - coupure par la présence ;
    - plages acceptées exclues ;
    - recalcul différentiel ;
  - rattachement par dépôt et par chemin ;
  - conversion des heartbeats WakaTime.
- `services/tests/integration/` :
  - jetons : création, révocation, jeton d'un ancien membre refusé, Basic et Bearer ;
  - envoi d'événements idempotent, `agent_time` ouvert puis fermé ;
  - le job crée et met à jour les suggestions ;
  - RLS : pas d'accès aux lignes d'autrui, pas d'insertion client ;
  - MCP : une écriture dans une période verrouillée est rejetée par la garde.
- `app/test/` : acceptation d'une suggestion, application d'une règle, totaux par piste.
- Plugin : le script avec un stdin factice et un serveur HTTP local.
  - stdout vide ;
  - `tool_input` jamais envoyé ;
  - file locale remplie quand le serveur est coupé, puis vidée.
- Bout à bout : `wakatime-cli` réel, pointé sur la pile locale, envoie des heartbeats acceptés.

## 10. Lots

| Lot | Contenu | Taille |
|---|---|---|
| 1 Temps de Claude | Migration (jetons, événements, `agent_time`, règles), Flask (jetons, `events`, D7), plugin minimal (hooks seuls), écrans des jetons et du temps de Claude, bandeau « Claude travaille » ; vérifier les hooks dans l'extension VSCode | M |
| 2 Mon temps | API compatible WakaTime, prompts comme signal humain, `time_suggestions`, job D8, écran Suggestions, `source` sur les entrées | L |
| 3 MCP | Service `mcp`, outils, `.mcp.json` et commandes du plugin | M |
| 4 Rapports et confort | Colonne Claude dans les rapports, calendrier, barre de menus macOS, signal de présence, extraits de prompt | M |
| 5 Connecteur claude.ai | OAuth (selon Supabase Auth auto-hébergé), publication du connecteur | M, conditionnel |

## 11. Points d'attention

- **Horloge client** : `occurred_at` est fourni par le poste et `received_at` est conservé ; on rejette les écarts aberrants (§5).
- **Confidentialité** : les événements bruts ne sont visibles de personne dans l'app. Les suggestions sont personnelles. Le temps de Claude est visible des managers comme les entrées.
- **Un seul serveur WakaTime par poste** : `~/.wakatime.cfg` n'a qu'un `api_url`. Garder aussi un compte WakaTime demanderait un relais côté Clockifai (renvoi des heartbeats), hors périmètre.
- **Fichiers hors dépôt** : un heartbeat sans projet n'est rattaché à rien et ne produit pas de suggestion.
- **Sous-agents en arrière-plan** : ils continuent après `Stop`. Si leurs `PostToolUse` arrivent, la ligne `agent_time` reste ouverte (D7.2). À vérifier en conditions réelles.
- **Attente d'une autorisation** : l'événement `Notification` n'est pas traité en v1. Ce temps compte pour Claude jusqu'à `IDLE_TIMEOUT`.
- **Plusieurs workspaces** : un jeton est lié à un seul workspace. Les dépôts de l'autre workspace ont besoin d'un autre jeton ou d'un réglage de dossier, qui reste à concevoir.

## 12. Questions à trancher

1. Temps de Claude : table `agent_time` (proposé), ou membre « agent » avec de vraies entrées (D2) ?
2. Le temps de Claude peut-il être facturé un jour (taux « IA » par projet) ? Si oui, il faudra le convertir en entrées.
3. Valeurs par défaut : `AGENT_GAP` 5 min, `IDLE_TIMEOUT` 10 min, `HUMAN_TIMEOUT` 15 min, `IDLE_CUT` 5 min ; réglables par utilisateur ?
4. `send_excerpts` désactivé par défaut (proposé) ?
5. Règles de rattachement seulement personnelles en v1 (proposé), ou aussi des règles de workspace posées par un admin ?
