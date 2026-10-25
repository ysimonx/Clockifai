# Suivi du temps : Claude et moi (hooks, extension VSCode, connecteur MCP) — plan 10

> Statut : **en cours** (lot 1 commencé le 23 octobre 2026, branche `plan-10-lot-1`, fait le 24 octobre 2026).
> Les lots 2, 3, 4 et 7 sont validés, les lots 5 et 6 restent envisagés.
>
> Objectif : mesurer, projet par projet, **deux temps distincts** :
> - le **temps de Claude**, pendant que les agents Claude Code travaillent, y compris quand on a quitté la fenêtre ;
> - **mon temps**, pendant que je travaille moi aussi : écrire un prompt, relire, coder, tester.
>
> Chaque pilote a son **agent**, « Claude · Yannick », **membre de l'équipe**. Le temps de Claude est enregistré
> directement en entrées de cet agent : un chronomètre démarre au premier prompt d'une session et s'arrête
> après 10 minutes d'inactivité, à l'heure de la dernière activité. Mon temps est estimé à partir de signaux
> d'activité et proposé en **suggestions d'entrées** à valider (saisie a posteriori). Un connecteur MCP permet
> de consulter, valider et décrire ces temps depuis Claude.
>
> Anciennement `06-suivi-claude-code.md`, renuméroté le 23 octobre 2026 : le numéro 06 est aussi celui de la
> barre de menus macOS.

## 1. Constat

| Sujet | État | Où |
|---|---|---|
| Façon de travailler visée | Plusieurs fenêtres VSCode, un agent Claude Code par projet ; on lance un prompt, puis on relit, on teste ou on passe à un autre projet | — |
| Hooks Claude Code | Disent exactement quand un agent travaille, mais rien de ce que je fais entre deux prompts | §2 |
| Activité dans VSCode | Dit quelle fenêtre, donc quel projet, a mon attention, mais rien du travail de l'agent fenêtre quittée. **Les deux sources sont complémentaires** | §2 |
| Origine d'une entrée | Aucune colonne `source` (le plan 02, en attente, la prévoyait aussi) | `0001_core.sql` |
| Membres | `role` et `status` seulement : aucune notion de membre non humain. Toute personne est une ligne `auth.users`, référencée par toutes les tables (`time_entries`, `team_scope`, `user_group_members`…) | `0001_core.sql`, `0009_team_managers.sql` |
| Périmètre d'encadrement | `team_scope`, recalculé par trigger ; `manages()`, `can_edit_others_time()` et le flux `managed_team` en dépendent. Côté app, toute ligne où je suis `manager_id` fait de moi un chef d'équipe (`TeamRights.isTeamManager`) | `0009_team_managers.sql`, `core/team_rights.dart` |
| Écritures sans JWT | `time_entries_guard` ne contrôle alors rien : ni verrou, ni `lock_entries_before`, ni période approuvée, ni facture | `0009_team_managers.sql` (`time_entries_guard`) |
| Chronomètres simultanés | `workspaces.max_running_timers` (1 par défaut, 0 = illimité) | `0011_parallel_timers.sql`, `05-chronometres-paralleles.md` |
| Taux et facturable d'une entrée | Instantané pris par le client (`catalog.rateFor` : taux du projet, sinon du membre ; facturable selon le projet). Côté serveur, même recherche dans le kiosque | `core/catalog.dart`, `routes/kiosk.py` |
| Schéma privé | `clockifai_private` appartient à `supabase_admin` ; `postgres` n'y a que `usage`. Une table s'y crée donc par une migration `*.admin.sql` | `0008_private_schema.admin.sql`, `deploy/migrate.sh` |
| Appareils kiosque | Jetons hachés dans `public.kiosk_devices` (RLS admin), révocation par `deleted_at` | `0007_modules.sql`, `routes/kiosk.py` |
| Purge | `purge_soft_deleted` supprime chaque nuit les lignes effacées depuis 30 jours : `time_entries`, `tasks`, `workspace_members`… | `jobs/tasks.py` |
| App macOS | Barre de menus native, lancée à l'ouverture de session, **en bac à sable** (`app-sandbox`, `network.client`) | `06-macos-barre-de-menus.md`, `app/macos/Runner/` |
| Authentification Flask | JWT Supabase (`require_user`) ou jeton d'appareil kiosque haché (`X-Kiosk-Token`) ; **pas de jeton personnel** | `auth.py`, `routes/kiosk.py` |
| Comptes créés par Flask | API admin GoTrue (`_gotrue_admin`, invitations) | `routes/invitations.py` |
| Tâches de fond | APScheduler dans le process Flask ; un seul worker gunicorn, 8 threads, 8 connexions Postgres. Désactivables par `JOBS_ENABLED` | `jobs/scheduler.py`, `gunicorn.conf.py`, `db.py`, `app/__init__.py` |
| Écritures client | `put` → upsert **sans les colonnes nulles** (le défaut serveur s'applique), `patch` → update des seules colonnes écrites ; une erreur 23xxx abandonne l'envoi | `app/lib/data/powersync/connector.dart` |

## 2. Ce que fournissent les outils

**Claude Code** (vérifié dans la doc, octobre 2026) :
- **Où s'exécutent les hooks** : le terminal, l'extension VSCode et l'onglet Code de l'app desktop lisent les
  mêmes fichiers de réglages. Un plugin installé au niveau utilisateur vaut donc pour les trois. Les sessions
  cloud (Claude Code sur le web) ne lisent pas les réglages utilisateur et ne chargent pas les plugins (§6.3).
- **Hooks** : `UserPromptSubmit`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `Notification`.
  - Champs communs sur stdin : `session_id`, `prompt_id`, `cwd`, `transcript_path`, `hook_event_name`, `permission_mode`.
    Chaque session a son `session_id`, y compris plusieurs onglets dans la même fenêtre VSCode.
  - `UserPromptSubmit` contient le texte du `prompt` ; `Stop` contient `last_assistant_message`.
  - `PostToolUse` contient `tool_name`, `tool_input`, `tool_response` ; `SessionEnd` contient `reason`.
  - `SessionStart` porte `source` : `startup`, `resume`, `clear`, `compact` ou `fork`. Il part aussi à
    l'ouverture du panneau VSCode, sans travail derrière : il ne démarre pas de chronomètre (D7).
  - `Notification` porte `notification_type` : `permission_prompt` (attente d'une autorisation),
    `idle_prompt`, etc. Dans VSCode et l'app desktop, le moment de `permission_prompt` diffère du terminal.
- **Types de hook** : `command`, `http`, `mcp_tool`, `prompt` et `agent`. Le type `http` poste le JSON de
  l'événement tel quel. Il enverrait donc le texte des prompts et le contenu des outils (contraire à D6),
  ignorerait le dépôt et la branche, et n'a pas de file d'attente hors ligne. Le plugin garde un hook
  `command` (script Python).
- `"async": true` sur un hook de type commande : exécution en arrière-plan, sans bloquer Claude. Plusieurs
  hooks d'une même session peuvent donc arriver en même temps au serveur (D7.9).
- Sur `UserPromptSubmit`, ce que le script écrit sur stdout est **injecté dans le contexte** : le script n'écrit rien.
- **Plugin** :
  - `.claude-plugin/plugin.json`, `hooks/hooks.json`, `.mcp.json`, `commands/` et `skills/` à la racine du plugin ;
  - `${CLAUDE_PLUGIN_ROOT}` pour les scripts ;
  - `userConfig` demande les réglages à l'installation (types `string`, `number`, `boolean`…, avec `default`
    et `required`). `"sensitive": true` masque la saisie et range la valeur dans le magasin sécurisé du
    système. Les hooks lisent les valeurs dans `CLAUDE_PLUGIN_OPTION_<KEY>` (une commande en forme shell
    refuse `${user_config.*}`), et `.mcp.json` par `${user_config.KEY}` ;
  - les outils d'un serveur MCP fourni par un plugin portent le nom `mcp__plugin_<plugin>_<serveur>__<outil>`
    (vérifié, voir ci-dessous), soit `mcp__plugin_clockifai_clockifai__set_current_task`. Le hook les reconnaît
    par leur suffixe (§6.1).
- **Marketplace** : `/plugin marketplace add` accepte un dépôt GitHub, une URL git sur n'importe quel hôte,
  un chemin local, ou **l'URL HTTPS d'un `marketplace.json`**. Dans ce dernier cas, le plugin y est référencé
  par une source non relative (archive, git…). Un dépôt peut proposer une marketplace et un plugin dans son
  `.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`), pris en compte une fois le dossier
  approuvé ; chacun installe quand même le plugin.
- **MCP distant** dans `.mcp.json` : `"type": "http"`, `url`, `headers` avec expansion de variables. Le
  serveur MCP ne reçoit **aucun identifiant de session** : seuls les hooks connaissent `session_id` (D9).
- **Sessions cloud** :
  - seuls les hooks du `.claude/settings.json` du dépôt s'exécutent, et seulement dans les sessions à un seul
    dépôt ; ils reçoivent `CLAUDE_CODE_REMOTE=true` ;
  - réseau « Trusted » par défaut (liste d'hôtes autorisés) ; « Custom » pour ajouter un hôte ; « Full » ou
    « None » sinon ;
  - secrets : variables d'environnement, lisibles par tous les utilisateurs de l'environnement, ou **secrets
    réseau**, que le proxy ajoute aux requêtes vers les hôtes listés sans qu'ils entrent dans la machine.
- **Connecteurs claude.ai** : OAuth 2.0 avec enregistrement dynamique des clients. Ils sont visibles dans
  Claude Code seulement avec une connexion par abonnement claude.ai.
- **Essai du 23 octobre 2026** (Claude Code 2.1.309, extension VSCode, hooks d'un `.claude/settings.local.json`
  journalisant les seuls noms d'événements et de champs, plugin jetable avec un serveur MCP `ping`) :
  - les hooks se déclenchent dans l'extension : `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Stop`,
    `SessionEnd`. Ajoutés en cours de session, ils sont actifs aussitôt ;
  - une conversation reprise depuis l'historique **garde son `session_id`** (`SessionStart` de source `resume`) ;
  - une nouvelle conversation envoie `SessionStart` (`startup`) à son premier prompt, dans la même seconde ;
  - nom vu par `PostToolUse` : `mcp__plugin_essai_essai__ping` ;
  - `PostToolUse` porte aussi `duration_ms` (durée de l'outil), `prompt_id`, `tool_use_id` et `effort` ;
  - une commande `claude plugin …` lancée dans le dossier du projet déclenche les hooks du projet
    (`SessionEnd`, raison `other`, sans prompt) : une session sans prompt ne produit rien (D7.1) ;
  - **`/plugin` n'existe pas dans l'extension VSCode** (« isn't available in this environment ») : le plugin
    s'installe depuis un terminal (§6.1), et un plugin installé n'est chargé qu'au démarrage d'une session ;
  - non observés, faute d'occasion : `SubagentStop`, `Notification` (aucune demande d'autorisation en mode
    automatique).
- **Essai du plugin, même jour** (marketplace locale `clockifai-dev`, pile locale) : une nouvelle conversation
  dans l'extension envoie `session_start`, `prompt`, `agent_tool` (avec `duration_ms`) et `agent_stop`, reçus
  dans la seconde ; l'entrée de « Claude · Yannick » démarre au prompt, décrite par le dépôt et la branche.
  Dix minutes plus tard, le job la ferme à l'heure de la dernière activité (19 s comptées, pas 10 min 43 s).
  Le jeton marqué `sensitive` arrive bien au hook par `CLAUDE_PLUGIN_OPTION_TOKEN`. Un plugin installé depuis
  une marketplace locale est lu dans son dossier source : une correction du script vaut sans réinstaller.

**API des extensions VSCode** (vérifié dans `vscode.d.ts`, octobre 2026) :
- `window.state.focused` : la fenêtre a le focus.
- `window.state.active` : « la fenêtre a reçu une interaction récemment ». La valeur change dès qu'il y a une
  activité, ou après un court moment d'inactivité, d'une durée non documentée.
- `window.onDidChangeWindowState` signale les changements de ces deux valeurs.
- Chaque fenêtre VSCode a son propre hôte d'extensions : une instance de l'extension par fenêtre, qui connaît
  ses dossiers ouverts (`workspace.workspaceFolders`).
- Signaux d'activité :
  - `window.onDidChangeTextEditorSelection` ;
  - `workspace.onDidChangeTextDocument` et `workspace.onDidSaveTextDocument` ;
  - `window.onDidStartTerminalShellExecution` (commandes lancées dans le terminal intégré).
- `ExtensionContext.secrets` (`SecretStorage`) conserve le jeton dans le trousseau du système.
- L'extension WakaTime ne réagit qu'aux modifications de fichiers et passe par `wakatime-cli` et un fichier
  `~/.wakatime.cfg` global. Elle ne voit pas le temps de lecture : d'où une extension maison (D4).

**macOS** : la durée d'inactivité du poste (clavier, souris) est lisible sans autorisation
(`CGEventSource.secondsSinceLastEventType`). Son fonctionnement en bac à sable est à vérifier.

## 3. Décisions de conception

**D1. Deux pistes, deux mesures, jamais additionnées.**
- **Piste Claude** : entrées du membre agent du pilote (D2), mesurées par les hooks.
- **Piste humaine** : mes intervalles d'activité, mesurés par plusieurs signaux (D4).

Pour un projet et une période, on affiche **mon temps**, **le temps de Claude** et la **durée calendaire**
(union des deux). Pendant qu'un agent travaille et que je relis, les deux pistes avancent ensemble.
Mon temps et celui de mon agent sont ceux de **deux membres** : ils ne s'additionnent jamais pour moi. Au
niveau de l'équipe, les rapports les séparent par un filtre « Humains et agents / Humains / Agents ».

**D2. Le temps de Claude est celui d'un membre agent.**
- **Un agent par pilote** : « Claude · Yannick », membre de chaque workspace où le pilote a créé un jeton
  (D5). Ni un membre par session (l'équipe exploserait), ni un « Claude » unique (on perdrait qui pilote).
- Ses entrées sont des `time_entries` ordinaires. Équipe, chronomètres en cours, calendrier, rapports par
  membre, exports, regroupement (plan 08) et factures fonctionnent tels quels. « Claude travaille sur
  Clockifai depuis 12 min » est un chronomètre en cours de l'agent.
- **Tâches en parallèle** : chaque session a son chronomètre, sans limite, et les temps se cumulent. Trois
  sessions pendant une heure font trois heures de Claude, chaque entrée allant à la tâche de sa session (D9).
  La durée calendaire (D1) reste d'une heure.
  - `max_running_timers` ne s'applique pas aux agents : il concerne mes chronomètres. Sans cette exemption,
    le trigger « le plus récent gagne » arrêterait les deux autres.
  - « Un chronomètre par tâche » (`sameTimerTarget`) n'est contrôlé que dans l'app ; le serveur n'en tient
    pas compte.
  - Il faut des sessions distinctes : des sous-agents lancés en parallèle dans une même session ne font
    qu'une entrée.
  - Trois clients différents paient chacun leur heure. Pour un même client, le cumul est facturé tel quel,
    sauf réglage contraire (D16).
- **Écrites par le serveur seulement**, par une fonction SQL qui reprend les gardes (D7.8) : `user_id` =
  agent, `created_by` = pilote, `source = 'agent'`. Personne ne crée d'entrée d'agent depuis l'app (D15).
- **Facturation réglable** (D16). Par défaut, facturable et taux comme pour un humain : selon le projet,
  sinon taux du membre agent. La recherche faite par `kiosk.punch` devient `entry_defaults()`, partagée par
  le kiosque et les agents. Le coût (`cost_rate_cents`) de l'agent suit la dépense IA.
- Alternative écartée : une table `agent_time` à part. Elle évitait un compte technique, mais demandait ses
  propres écrans, sa colonne dans les rapports, et une conversion en entrées pour facturer.

**D3. Mon temps devient des suggestions, puis des entrées.** Il est estimé : une pause de moins de
15 minutes reste du travail. Une suggestion acceptée devient une `time_entry` ordinaire
(`source = 'activity'`), écrite par l'app et soumise aux mêmes gardes : verrouillage, périodes approuvées,
facturation.

**D4. Signaux de mon activité**, dans l'ordre des lots :
1. **Prompts** (hook `UserPromptSubmit`) : écrire un prompt, c'est travailler.
2. **Extension VSCode Clockifai** (§6.2) : elle signale quelle fenêtre a le focus et une interaction
   récente, donc quel projet a mon attention, **y compris quand je relis la réponse de Claude** sans toucher
   à un fichier. S'y ajoutent les modifications de fichiers et les commandes du terminal intégré.
3. **Présence au poste** (app macOS, lot 4) : l'app signale chaque minute si le poste est actif. Elle ne voit
   pas le projet, mais elle **coupe** un intervalle quand on a quitté le poste, au lieu de compter jusqu'à
   15 minutes d'absence.

Hors périmètre : les autres éditeurs (JetBrains…) et le terminal hors VSCode. Pour Claude Code lancé dans un
terminal, seuls les prompts comptent, avec le délai de 15 minutes (D8).

**D5. Jetons d'API personnels**, inspirés des appareils kiosque (`public.kiosk_devices`) :
- le jeton est `clk_` suivi de 32 caractères hexadécimaux. Le préfixe permet de le repérer s'il fuit dans un dépôt ;
- affiché une seule fois, haché en SHA-256, rattaché à **un utilisateur et un workspace**, révocable, avec `last_used_at` ;
- un jeton par machine, utilisé à la fois par les hooks, l'extension VSCode et le MCP ;
- rangés dans `clockifai_private`, contrairement aux appareils kiosque : un jeton personnel ouvre les données
  d'une personne, sa table n'a rien à faire dans l'API ni dans la publication PowerSync ;
- chacun ne voit et ne révoque que ses propres jetons ; un admin peut révoquer ceux des membres de son workspace ;
- **créer un jeton est le seul moment où l'agent du pilote est créé** (D14).

**D6. Événements bruts côté serveur, jamais répliqués.** Ils vont dans `clockifai_private.activity_events`,
hors API et hors PowerSync, et sont purgés après 30 jours. Les données sont réduites au départ :
- **Hooks** : liste blanche dans le script. Jamais `tool_input`, `tool_response` ni `transcript_path`, sauf
  la réponse des outils Clockifai eux-mêmes (`set_current_task`, `describe_current_work`), réduite à l'id de
  tâche ou à la description (D9). Le script lit sur le poste la commande d'un `Bash` pour y repérer une
  opération git qui crée des commits (D13), sans jamais l'envoyer. Des notifications, seules celles de type
  `permission_prompt` partent (`agent_wait`). Lot 7 : le script lit aussi la transcription sur le poste pour
  n'en envoyer que des totaux (modèle, effort, nombres de tokens), jamais son contenu (D17).
- **Extension VSCode** : dépôt, branche, type de signal, état de la fenêtre, éditeur (VSCode, Cursor…) et
  machine. Jamais le chemin ni le contenu des fichiers, ni les commandes du terminal.

**D7. Règles du chronomètre d'agent.** Un seul réglage : `IDLE_TIMEOUT` (10 min).
1. `SessionStart` ne démarre rien, quelle que soit sa `source` : il part aussi sans travail derrière (§2).
2. `UserPromptSubmit` : si la session a une entrée en cours, elle continue, et **l'attente entre deux tours
   compte** ; sinon une entrée démarre à l'heure du prompt.
3. `PostToolUse` (au plus un par minute et par session), `Stop` et `SubagentStop` sont des signes
   d'activité, sous-agents compris.
4. **Fin rétroactive** : un job ferme chaque minute les entrées en cours sans activité depuis `IDLE_TIMEOUT`,
   à l'heure de la dernière activité, pas à l'heure où il constate l'inactivité. Sinon chaque session
   compterait le délai en trop. Dans l'app, le chronomètre tourne en direct, puis sa fin « recule » à la
   clôture.
5. `SessionEnd` ferme l'entrée à l'heure de l'événement.
6. **Commande longue** : `PostToolUse` porte `duration_ms`. Un outil qui finit après le délai mais a commencé
   avant (`fin − durée ≤ dernière activité + délai`) prolonge l'entrée jusqu'à lui, car Claude travaillait.
   Exceptions : une attente d'autorisation (`agent_wait`) reçue entre-temps, ou un outil commencé après le
   délai ; l'outil ouvre alors une nouvelle entrée, à son début. Un `Stop` ne porte pas de durée : après le
   délai, il ne prolonge rien. Un outil sans prompt avant lui (session reprise, plugin installé en cours de
   session) ouvre une entrée ; un `Stop` seul, non.
7. **Recalcul, pas machine à états.** `agent_clock` (fonction pure, testée sans base) recalcule les
   intervalles d'une session à partir de tous ses événements bruts (7 jours au plus). Le serveur applique
   ensuite la différence avec les entrées existantes. Un événement en retard ou en double donne donc le même
   résultat que s'il était arrivé à l'heure. C'est le principe de D8.6.
8. **Ce que le serveur ne touche jamais** :
   - **une entrée qu'un humain a retouchée** : début ou fin changés (arrêt depuis l'app, correction, arrêt
     automatique `auto_stop_long_timers`), ou suppression. Le serveur le voit en comparant avec les valeurs
     qu'il a écrites lui-même (`server_start_at`, `server_end_at`). L'entrée est figée, et sa plage est
     retirée des intervalles recalculés : une entrée supprimée n'est jamais recréée, et l'activité suivante
     ouvre une nouvelle entrée ;
   - **le projet, la tâche ou la description choisis par un humain** (D9, D10). Changer le projet d'une
     entrée en cours ne fige pas sa durée ;
   - **une entrée protégée** : verrouillée, antérieure à `lock_entries_before`, dans une période approuvée ou
     facturée. Le serveur écrit sans JWT, donc sans garde : toutes les écritures d'agent passent par une
     fonction SQL, `agent_entry_write`, qui reprend ces contrôles de `time_entries_guard`. En cas de refus,
     la modification est abandonnée et l'activité ouvre, si elle le peut, une nouvelle entrée.
9. **Concurrence** : le recalcul d'une session se fait sous verrou consultatif (`session_id`). Deux lots de la
   même session arrivés en même temps sont traités l'un après l'autre et n'ouvrent pas deux entrées.
10. **Agent inactif ou retiré** : ses événements sont gardés, mais aucune entrée n'est créée ni modifiée.

L'état de chaque entrée d'agent (session, dépôt, valeurs écrites par le serveur) reste hors réplication, dans
`clockifai_private.agent_entries` (§4).

**D8. Règles de la piste humaine** (fonction pure, testable sans base, appelée par un job) :
1. **Fenêtre VSCode attentive** : l'extension envoie `focus_start` quand la fenêtre devient
   `focused && active`, un signe de vie toutes les 60 s tant qu'elle le reste, et `focus_end` dès qu'elle ne
   l'est plus. Ces signaux donnent des intervalles mesurés directement, sans délai. Sans signe de vie depuis
   2 minutes (VSCode fermé, veille), l'intervalle s'arrête au dernier signal.
2. **Autres signaux** (prompts sans extension, modifications et terminal hors focus) : ils sont regroupés en
   intervalles. Un écart de moins de `HUMAN_TIMEOUT` (15 min) ne coupe pas, et un intervalle va de son premier
   événement au dernier, plus 2 minutes.
3. **Une seule attention** : chaque instant va au projet de mon **dernier** événement. Comme une seule fenêtre
   a le focus à la fois, les intervalles du point 1 ne se chevauchent pas. Mes suggestions ne se chevauchent
   jamais, quel que soit `max_running_timers`. Cette règle ne dépend que du passé : l'attribution d'un instant
   écoulé ne change plus.
4. **Présence** (lot 4) : une période où le poste est inactif plus de `IDLE_CUT` (5 min) coupe l'intervalle.
5. **Plages exclues** : celles que couvre déjà une de mes entrées, quelle qu'elle soit (saisie à la main,
   suggestion acceptée, chronomètre), et celles des suggestions ignorées. La saisie a posteriori reste le
   mode principal : une suggestion ne double jamais une entrée.
6. **Recalcul différentiel** des suggestions en attente. Une suggestion recalculée reprend l'id de la
   suggestion en attente qu'elle chevauche le plus, et garde ce que j'y ai modifié (projet, tâche,
   description). Celles qui disparaissent du calcul sont supprimées logiquement. Le job ne touche que les
   suggestions `pending` : une acceptation faite hors ligne arrive avec son statut et n'est jamais écrasée.
   C'est le même principe que `team_scope` (plan 03, D3).

**D9. Rattachement au projet, commun aux deux pistes.**
- **Clé d'un dépôt** : son `remote_key`, l'URL distante normalisée (`hôte/chemin`), la même que pour les
  forges (plan 09, P3). Sans remote : `local:<nom du dossier racine>`. Les worktrees d'un même dépôt
  partagent la clé, et deux dépôts de même nom ne se confondent pas. Le script de hook et l'extension la
  calculent avec la même normalisation.
- **Règles personnelles** (`activity_rules`) : un `remote_key` ou un préfixe de chemin (`cwd`) mène à un
  projet, et optionnellement à une tâche. Le chemin, plus précis, prime.
- **Règle de workspace** : à défaut de règle personnelle, le projet du dépôt (`code_repositories.project_id`,
  posé par un admin) s'applique.
- Une entrée d'agent ou une suggestion sans projet porte le dépôt dans sa description (D10). Choisir son
  projet propose « toujours rattacher ce dépôt » : Flask crée la règle et réattribue les entrées d'agent sans
  projet et les suggestions en attente du même dépôt. Le dépôt d'une entrée d'agent est dans `agent_entries`,
  hors réplication : c'est pourquoi la règle passe par Flask.
- **Tâche d'une session d'agent**, de la source la plus précise à la moins précise :
  1. la tâche donnée dans la session par l'outil MCP `set_current_task` (commande `/clockifai:tache`), ou
     choisie dans l'app ;
  2. la tâche de la branche : son numéro dans le nom (`clk-42-…`, plan 04 lot 0), ou un lien de branche posé
     dans la fiche de la tâche (plan 09) ;
  3. une règle par chemin : un worktree par tâche donne à chaque session son propre `cwd` ;
  4. une règle par dépôt, puis le projet du dépôt.

  Trois sessions ouvertes dans le même dossier, sur la même branche, ne se distinguent que par le point 1.
- **Le serveur MCP ne connaît pas la session** qui l'appelle, et trois sessions peuvent partager un `cwd`.
  L'outil se contente donc de résoudre et de renvoyer la tâche (ou la description), en JSON structuré
  (`{"task_id": …, "project_id": …}`, `{"description": …}`). Le hook `PostToolUse` de cet outil connaît
  `session_id` : c'est lui qui envoie l'événement `session_task` (ou `session_description`).
- Une nouvelle entrée d'une session reprend le projet et la tâche de l'entrée précédente de la même session,
  sauf changement de branche.
- Le serveur ne change le projet ou la tâche d'une entrée d'agent qu'à sa création, sur un `session_task`, ou
  par une règle quand elle n'a pas de projet. Dans tous les cas, il compare avec les valeurs qu'il a écrites
  (`server_project_id`, `server_task_id`) : un choix fait dans l'app, y compris retirer le projet, n'est
  jamais écrasé.

**D10. Descriptions**, par ordre de priorité :
1. Une description saisie dans l'app n'est jamais écrasée. Une description donnée par Claude
   (`describe_current_work`, commande `/clockifai:decrire`) n'est remplacée que par une description suivante
   de Claude. `agent_entries` garde le dernier texte écrit par le serveur (`server_description`) et son
   origine (`description_source` : `auto` ou `claude`) : si le texte de l'entrée en diffère, il a été saisi
   dans l'app et plus personne n'y touche.
2. Sinon, les **messages des commits** faits pendant la plage (D13), séparés par « ; ». C'est la meilleure
   source automatique.
3. Sinon, en option, un extrait (200 caractères) du prompt ou de `last_assistant_message`, si l'option
   `send_excerpts` du plugin est activée.
4. Sinon, le dépôt et la branche.

Pour une suggestion humaine, les sources 2 et 3 incluent aussi les entrées de mon agent du même projet qui la
chevauchent (« ce que Claude faisait pendant ce temps »).

**D11. Serveur MCP séparé**, sur le même Postgres. Flask (un seul worker synchrone) convient mal au
transport MCP en HTTP.
- Il partage le code de `services/` (`db.py`) et tourne dans un second conteneur construit depuis la même
  image, avec le SDK Python `mcp` (HTTP en flux, sans état), et `JOBS_ENABLED=false` : sinon les jobs
  APScheduler tourneraient deux fois.
- Les écritures s'exécutent **comme l'utilisateur** : `set local role authenticated` et
  `set_config('request.jwt.claims', …, true)`. La RLS et les triggers s'appliquent donc exactement comme
  depuis l'app. Il faut vérifier que `postgres` peut prendre le rôle `authenticated`.

**D12. Connecteur claude.ai (OAuth) en dernier, et conditionnel.**
- Pour Claude Code, un jeton personnel dans l'en-tête suffit.
- Un connecteur claude.ai demande un serveur OAuth : il faut vérifier ce que Supabase Auth propose dans la
  version auto-hébergée épinglée (v1.26.08).
- Comme les hooks n'existent pas hors de Claude Code, le connecteur ne servirait là qu'à consulter et saisir.

**D13. Commits vus en local**, sans forge. Le plan 09 (`09-forges-git.md`) ajoute les forges : GitHub,
GitLab, Gitea/Forgejo…
- **Détection** : deux sources comparent HEAD au dernier HEAD vu, mémorisé **par dossier de travail**
  (racine git, donc un par worktree).
  - Le hook le fait à chaque `PostToolUse` de l'outil `Bash`, et au `Stop`.
  - L'extension VSCode le fait sur `repository.state.onDidChange` de l'API `vscode.git`, ce qui couvre aussi mes commits faits depuis VSCode ou un terminal.
- **Attribution à une session** : plusieurs sessions peuvent travailler dans le même dossier, et le dernier
  HEAD vu leur est commun. Sans précaution, un commit de la session A serait pris par la session B si B
  lançait une commande juste avant la vérification de A. D'où la règle :
  - une session ne revendique que les commits faits **pendant** l'une de ses propres commandes `Bash` qui en
    crée : `git commit`, `merge`, `cherry-pick`, `revert`, `am` ou `rebase`, `git -C …` compris. Le script le
    voit en lisant la commande sur le poste, sans l'envoyer (D6). « Pendant » : date du commit postérieure au
    début de la commande (fin moins `duration_ms`, à 5 s près) ;
  - les nouveaux commits vus par une vérification sont mis de côté, « non revendiqués », dans l'état du
    dossier de travail. Une autre session qui les voit passer ne les envoie pas ;
  - les commits que personne n'a revendiqués au bout de **10 minutes** (faits hors de Claude, alias git non
    reconnu) partent sans session à la vérification suivante. Le serveur les rattache à l'intervalle de focus
    humain qui les couvre (D8), sinon à rien. Dix minutes et non une : une commande `git commit && npm test`
    ne rend la main, et ne revendique son commit, qu'à la fin des tests.
- **Envoi** : un événement `commit` par commit nouveau de `git log <dernier HEAD vu>..HEAD`, dont l'auteur a
  l'e-mail `user.email` (comparaison exacte) et dont la date de commit suit la dernière vérification
  (moins 1 min) ; 20 au plus. Un changement de branche, un `pull` ou un rebase de commits d'autrui ne produit
  donc rien. Un dossier jamais vu fixe son point de départ au `SessionStart` ; une commande qui commite dans un
  dossier jamais vu revendique quand même ses commits.
- **Contenu** : sha, branche, première ligne du message (200 caractères), e-mail de l'auteur, date. Jamais le diff.
- **Idempotence** : la clé est `uuid5(NAMESPACE_URL, "clockifai:commit:<remote_key>:<sha>")`. Le hook et
  l'extension voient le même commit sans le compter deux fois. Le premier arrivé l'emporte : au lot 2, un
  commit d'abord reçu de l'extension (sans session) puis du hook (avec session) devra passer à la session.
- **Côté serveur** :
  - le commit est enregistré dans `code_commits`, avec la session ou la fenêtre d'origine ;
  - il est rattaché à l'entrée d'agent de la session qui l'a produit (commit de Claude), ou à l'intervalle de focus de la fenêtre (mon commit) ;
  - ses messages servent de description (D10) ;
  - le lien « contexte » avec une tâche est calculé par le module de règles commun du plan 09 (§3).
- **Réécritures** : un `commit --amend` ou un rebase crée de nouveaux sha. Les anciens restent marqués
  « local », jamais poussés, et le plan 09 les réconcilie avec la forge.

**D14. Identité de l'agent.**
- **Compte technique** : Flask le crée avec l'API admin GoTrue (`admin/users`), par le helper `_gotrue_admin`
  sorti de `routes/invitations.py` vers `services/gotrue.py`. `app_metadata` vaut
  `{"kind": "agent", "owner_id": <pilote>}`, et `user_metadata` porte aussi `kind: agent` : GoTrue n'écrit les
  `app_metadata` qu'après l'insertion, que voit `handle_new_user` (constaté le 23 octobre 2026). Le compte a un
  e-mail technique non routable, pas de mot de passe et un `ban_duration` très long : aucune connexion possible. Un seul compte par pilote, membre de
  chacun de ses workspaces.
- Avant d'appeler GoTrue, Flask cherche le compte agent du pilote (`app_metadata.owner_id`), sous verrou
  consultatif par pilote : deux créations simultanées ne font pas deux comptes. L'appel HTTP à GoTrue se
  fait hors de la transaction.
- Toutes les clés étrangères vers `auth.users` fonctionnent donc sans changement de schéma.
- `handle_new_user` crée le profil mais **pas d'espace personnel** pour un agent. Flask recopie le fuseau du
  pilote dans ce profil, car `user_local_date` s'en sert pour le verrouillage.
- **Membre** : `workspace_members.kind = 'agent'` et `agent_owner_id` = pilote.
  - Rôle toujours `member`, pas de PIN kiosque, e-mail technique jamais affiché.
  - Nom par défaut « Claude · <pilote> », posé à la création et modifiable par un admin.
  - Créé par le serveur seulement, à la création d'un jeton (D5). `ensure_agent` ne fait que créer : il ne
    réactive ni ne recrée un agent qu'un admin a désactivé ou retiré. Les événements de cet agent sont gardés
    sans produire d'entrée (D7.10), et l'écran Intégrations le signale. Réactiver l'agent reste un geste
    d'admin : « Réactiver » dans le menu de sa fiche, ou, retiré, « Restaurer » sous « Agents retirés » dans
    Équipe (`GET /api/agents/removed`, `POST /api/agents/<id>/restore`, le statut suit le pilote), ajouté le
    24 octobre 2026 après un retrait par erreur. Les membres retirés ne descendant pas vers les appareils,
    c'est Flask qui les liste. Retirer un agent affiche un avertissement propre (pas de recréation, préférer
    « Désactiver »).
  - `kind` et `agent_owner_id` ne changent jamais.
  - **Le retrait suit le pilote, pas le retour** : pilote désactivé ou retiré → agent désactivé ou retiré
    (trigger). Le pilote réactivé, son agent reste à réactiver par un admin.

**D15. Qui voit et corrige le temps de l'agent.**
- **Lecture** : `team_scope_wanted` ajoute les couples (pilote, agent), et (chef du pilote, agent) pour chaque
  chef d'équipe du pilote. `manages()` donne alors la lecture, et le flux `managed_team` amène les entrées de
  l'agent sur les appareils du pilote et de ses chefs. Managers et admins le voient par `team_data`.
- **Modifier et supprimer, jamais créer** : une nouvelle fonction, `pilots_agent(wid, uid)`, s'ajoute aux
  politiques UPDATE et DELETE de `time_entries` et à l'écriture de `time_entry_tags`, mais pas à l'INSERT.
  `can_edit_others_time` ne change pas. Le pilote corrige donc le projet, la tâche, la description, les tags
  ou les heures des entrées de son agent, même si `time_for_others = 'admins'`, sans pouvoir en créer.
- **Garde** (`time_entries_guard`, appels avec JWT) :
  - `user_id` et `workspace_id` d'une entrée ne changent jamais : personne ne s'attribue le temps de son agent,
    ni ne lui donne le sien ;
  - aucune entrée ne se crée pour un agent, admins compris ;
  - pas de redémarrage d'un chronomètre d'agent ; les contrôles existants (verrou, périodes, factures)
    s'appliquent.
- **Dans l'app, le pilote n'est pas chef d'équipe** : `TeamRights` sépare `managed` (les humains encadrés,
  qui font le chef d'équipe : approbations, saisie pour autrui, libellé « Chef d'équipe ») des agents
  visibles (`agentsSeen`). Les lignes de `team_scope` qui visent un agent ne comptent ni dans `managed` ni
  dans `catalog.managersOf`.
- Un agent ne soumet pas de feuille de temps : `submissions_insert` exige `auth.uid()`.

**D16. Facturation du temps des agents, réglable.**
- **Réglage du workspace** (admins), `workspaces.agent_billing` :
  - `like_humans` (défaut) : facturable selon le projet (`billable_default`), au taux du projet, sinon à
    celui de l'agent ;
  - `never` : `billable = false`. Le taux reste posé pour les rapports et le coût, mais l'entrée n'entre
    jamais dans une facture.
- **Exception par projet**, donc de fait par client : `projects.agent_billable`. Nul : comme le workspace.
  Vrai : facturable. Faux : non facturable. Un client accepte qu'on lui facture le travail de Claude, un
  autre non.
- **Application** :
  - côté serveur, quand il crée une entrée d'agent ou lui donne un projet (`entry_defaults()`) ;
  - dans l'app, quand le pilote choisit le projet d'une entrée d'agent (`catalog.billableFor`, à côté de
    `rateFor`).
- Comme pour les humains, le caractère facturable est un **instantané** : changer le réglage ne modifie pas
  les entrées passées, et le pilote peut toujours corriger une entrée à la main.
- **Piste, hors v1** : facturer à un même client la durée calendaire de ses sessions parallèles plutôt que
  leur cumul. Il faudrait répartir les heures au moment de la facture.

**D17. Usage IA : tokens, modèle et effort de chaque entrée d'agent** (lot 7, demandé le 24 octobre 2026).
Le temps ne dit pas tout du travail de Claude : deux heures d'Opus en effort maximal ne coûtent pas deux heures de
Haiku. On remonte donc, par entrée d'agent, le modèle, le niveau d'effort et les tokens consommés, pour suivre le
coût de l'IA par projet et par client, et pouvoir le refacturer.
- **Source** (vérifiée le 24 octobre 2026 sur une transcription de Claude Code 2.1.309) : les hooks ne portent ni
  tokens ni modèle, mais la transcription que Claude Code écrit sur le poste (`transcript_path`, JSONL) les contient.
  Chaque ligne `type = "assistant"` porte `message.model` (`claude-opus-5-5`…), `message.usage`
  (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`) et `effort`
  (`xhigh`…). `PostToolUse` porte aussi `effort` (§2).
- **Lecture sur le poste, envoi de totaux seulement** (D6) : au `Stop`, le script lit la transcription depuis le
  dernier octet lu (position gardée par session dans `~/.cache/clockifai/`), additionne par (modèle, effort) et
  envoie un événement `agent_usage` : `{model, effort, input_tokens, output_tokens, cache_creation_tokens,
  cache_read_tokens, requests}`. Jamais le texte des messages. Les sous-agents écrivent leur propre transcription
  (`agent_transcript_path` de `SubagentStop`), lue de même à leur fin.
- **Pièges connus** :
  - une réponse occupe plusieurs lignes, chacune répétant le même `usage` (1 153 lignes pour 419 appels dans la
    session vérifiée) : on compte une fois par `message.id` ;
  - le format n'est pas documenté et change d'une version à l'autre : lecture tolérante, une ligne inconnue est
    ignorée, et un format méconnaissable ne fait qu'omettre l'usage, jamais échouer le hook ;
  - une session reprise (`resume`) prolonge la même transcription : la position gardée évite de recompter ;
  - idempotence : l'id de l'événement est `uuid5(session, message.id du dernier appel compté, modèle, effort)`.
- **Serveur** : l'usage est rattaché à l'entrée d'agent qui couvre l'heure du `Stop` (comme un commit, D13), puis
  cumulé dans une table répliquée `agent_usage` (`workspace_id`, `time_entry_id`, `user_id` de l'agent, `model`,
  `effort`, les quatre compteurs, `requests`), lisible par ceux qui lisent l'entrée et synchronisée avec elle
  (mêmes flux que `time_entries`).
- **Coût estimé** : une table `ai_model_prices` (prix par million de tokens en entrée, en sortie, en écriture et en
  lecture de cache, par modèle), remplie par défaut avec les tarifs publics et modifiable par un admin. Le coût
  d'une entrée est un instantané, calculé à l'arrivée de l'usage, comme le taux horaire.
- **Dans l'app** : modèle, effort, tokens et coût sur la ligne et dans le détail d'une entrée d'agent ; colonnes
  « Tokens » et « Coût IA » dans les rapports et les exports, par projet, client et membre ; total de la semaine
  sur la carte de l'agent (page Équipe).
- **Facturation**, plus tard : proposer le coût IA comme ligne de facture (au coût, ou avec une marge), à côté
  des heures.

**D18. Claude nomme la tâche de son sujet** (lot 1c, demandé et fait le 24 octobre 2026). Un pilote qui travaille
sur `main` n'a pas de branche pour distinguer ses sujets, et la tâche de D9 ne pouvait être qu'une tâche existante.
- **Qui nomme** : Claude, qui sait sur quoi il travaille. Le hook ne voit que le prompt brut, qu'il n'envoie
  jamais (D6) et qu'il ne saurait pas résumer.
- **Comment** : le plugin fournit un serveur MCP local (`.mcp.json`, `scripts/clockifai_mcp.py`, stdio,
  bibliothèque standard, sans réseau ni jeton) et son outil `set_current_task(name)`, qui renvoie le nom reçu.
  Ses `instructions` demandent à Claude de l'appeler au début de chaque nouveau sujet, avec un nom court (3 à
  6 mots, dans la langue de l'utilisateur), le même nom pour le même sujet, sans nom de personne ni donnée
  confidentielle. Le hook `PostToolUse` reconnaît l'outil (`mcp__plugin_clockifai_*__set_current_task`), hors de
  la limite d'un outil par minute, et envoie `session_task` `{task_name}` (80 caractères). C'est la seule valeur de
  `tool_input` qui quitte le poste. Le serveur MCP ne connaît pas la session : seul le hook la connaît.
- **Côté serveur** (`subject_task`) : dans le projet de l'entrée, la tâche active de ce nom (sans tenir compte de la
  casse), sinon une nouvelle si `workspaces.task_creation = 'everyone'`, sous verrou par projet et par nom (deux
  sessions, une seule tâche). Sans projet ou sans ce droit, le nom devient la description de l'entrée. Une tâche
  choisie à la main n'est jamais remplacée ; dans un projet choisi à la main, la tâche nommée s'ajoute.
- **Découpage** (`agent_clock`) : un nom donné dans les 2 minutes suivant le début de l'entrée, ou son dernier
  prompt, vaut pour toute l'entrée ; un nouveau nom plus tard coupe l'entrée au dernier prompt s'il est récent,
  sinon à l'appel. Une entrée ouverte après une pause n'est pas nommée par l'horloge : elle reprend la tâche de la
  précédente (D9), qu'un nouveau nom remplace.
- **Autorisation** : Claude Code demande d'autoriser l'outil à son premier appel ; un plugin ne peut pas
  s'autoriser lui-même. Règle à poser une fois dans `~/.claude/settings.json` :
  `"permissions": {"allow": ["mcp__plugin_clockifai_clockifai__set_current_task"]}`.
- Vérifié le 24 octobre 2026 avec Claude Code 2.1.309 : `claude mcp list` montre
  `plugin:clockifai:clockifai … Connected`, et une session réelle a nommé et créé « Relecture du README ». Le
  chargement par l'extension VSCode n'est pas décrit par la documentation : à constater sur un poste.
- Le lot 3 garde le service MCP distant (projets, résumé, suggestions) ; `set_current_task` y est déjà fait, en
  local.
- **Préciser = renommer** (24 octobre 2026, après la question « un premier prompt vague crée-t-il plusieurs
  tâches ? ») : la consigne demande un nom dès que Claude sait sur quoi porte le travail, même une vérification
  rapide (pas pour une simple salutation), et de le garder pour préciser le même sujet. Une première version
  (« une fois le sujet clair, pas pour une question rapide ») laissait des sessions sans tâche, contraire au mode
  « une tâche par session » (constaté à l'essai réel) ;
  la première entrée d'une session prend son premier nom en entier, quel que soit le délai ; un nom plus précis
  en début d'entrée renomme la tâche que le serveur a créée pour elle (`clockifai_private.agent_tasks`, 0014),
  ou bascule sur la tâche existante de ce nom en supprimant la tâche vide. Une tâche renommée à la main ou
  utilisée par une autre entrée n'est jamais touchée.
- **Réglage « Tâches de Claude »** de chaque pilote (`profiles.claude_tasks`, 0015 ; Paramètres › Intégrations ›
  Claude Code) : « Une tâche par sujet » (défaut, ci-dessus), « Une tâche par session Claude Code » (toujours une
  nouvelle tâche, datée si le nom est pris, « Export PDF (25 oct.) » ; jamais de coupure ; un nom plus précis la
  renomme ; une reprise y reste) ou « Pas de tâche » (les noms sont ignorés, comme avant D18). Claude appelle
  encore l'outil en mode « Pas de tâche » : le serveur MCP local ne connaît pas le réglage.

## 4. Modèle de données — migrations `0012_activity_private.admin.sql` et `0013_activity.sql`

`postgres` n'a que `usage` sur `clockifai_private` (0008). Les tables privées se créent donc dans
`0012_activity_private.admin.sql`, exécutée en `supabase_admin`, qui les donne ensuite à `postgres` et retire
les droits de `powersync_role`, `anon` et `authenticated`, comme 0008. Le reste va dans `0013_activity.sql`.

| Table | Colonnes | Sync |
|---|---|---|
| `clockifai_private.api_tokens` (0012) | `id`, `workspace_id`, `user_id`, `name`, `token_hash` (unique), `last_used_at`, `created_at`, `revoked_at` | non |
| `clockifai_private.activity_events` (0012) | `id` (clé d'idempotence : `event_id` généré par le hook ou l'extension, `uuid5(remote_key, sha)` pour un commit), `workspace_id`, `user_id`, `token_id`, `actor` (`agent`, `human`), `kind` (`prompt`, `agent_tool`, `agent_stop`, `agent_wait`, `session_start`, `session_end`, `session_task`, `session_description`, `focus_start`, `focus_alive`, `focus_end`, `edit`, `terminal`, `commit`, `presence`), `occurred_at`, `received_at`, `session_id` (hook) ou `window_id` (extension), `remote_key`, `cwd`, `git_branch`, `sha`, `subject`, `author_email`, `authored_at`, `editor`, `machine`, `active` (présence), `payload` (jsonb : tâche ou description relayée), `excerpt` ; index `(user_id, occurred_at)` et `(session_id, occurred_at)` | non |
| `clockifai_private.agent_tasks` (0014, D18) | `task_id` (clé, `on delete cascade`), `workspace_id`, `session_id`, `name` (nom posé par le serveur) ; index `(session_id)` | non |
| `public.profiles` (0015, D18) | `+ claude_tasks` (`subject`, `session`, `off` ; défaut `subject`) | `my_profile` (existant) |
| `clockifai_private.agent_entries` (0012) | `time_entry_id` (clé, `on delete cascade`), `workspace_id`, `agent_user_id`, `session_id`, `remote_key`, `git_branch`, `cwd`, `last_activity_at`, `waiting_since`, `closed_by_idle`, `server_start_at`, `server_end_at`, `server_project_id`, `server_task_id`, `server_description`, `description_source` (`auto`, `claude`), `prompt_count`, `commit_count` ; index `(session_id)` | non |
| `public.code_repositories` | `workspace_id`, `remote_key` (unique par workspace), `name`, `project_id` (facultatif : la règle de workspace de D9), + colonnes standard. Le plan 09 l'étend (forge, URL web, branche par défaut) | non |
| `public.code_commits` | `workspace_id`, `repository_id`, `sha` (unique par dépôt), `branch`, `subject`, `author_email`, `author_user_id`, `authored_at`, `seen_locally_at`, `session_id` ou `window_id`, `time_entry_id` (entrée d'agent, `on delete set null`), + colonnes standard. Le plan 09 l'étend | non : les messages arrivent dans l'app par les descriptions |
| `public.activity_rules` | `workspace_id`, `user_id`, `match_kind` (`repo`, `path_prefix`), `pattern` (`remote_key` ou chemin), `project_id`, `task_id`, + colonnes standard | `my_time_entries` |
| `public.time_suggestions` | `workspace_id`, `user_id`, `project_id`, `task_id`, `description`, `start_at`, `end_at`, `remote_key`, `git_branch`, `signals` (jsonb : minutes de focus, nombre de prompts et de modifications, éditeurs), `status` (`pending`, `accepted`, `dismissed`), `time_entry_id` (`on delete set null`), + colonnes standard | `my_time_entries` |
| `public.workspace_members` | `+ kind text not null default 'human'` (`human`, `agent`), `+ agent_owner_id uuid references auth.users on delete cascade` ; checks `(kind = 'agent') = (agent_owner_id is not null)` et `kind = 'human' or role = 'member'` ; unique `(workspace_id, agent_owner_id) where kind = 'agent' and deleted_at is null`. La migration « touche » les lignes (petite table) | `workspace_core` (existant) |
| `public.workspaces` | `+ agent_billing text not null default 'like_humans'` (`like_humans`, `never`). La migration « touche » les lignes (petite table) | `workspace_core` (existant) |
| `public.projects` | `+ agent_billable boolean` (nul = comme le workspace) | `workspace_core` (existant) |
| `public.time_entries` | `+ source text`, **nullable** : nul = `app`. Pas de « touche » des entrées existantes, donc pas de resynchronisation complète. Check `source in ('app', 'kiosk', 'activity', 'agent')`, plus `fidwork` quand le plan 02 reprendra | existante |

Fonctions et triggers (0013) :

| Objet | Changement |
|---|---|
| `workspace_members_guard` | recréé `before insert or update` (il n'était que `before update`, 0003). Avec un JWT : pas d'insertion `kind = 'agent'` ; `kind` et `agent_owner_id` immuables |
| `workspace_members_agents_follow` (nouveau) | pilote désactivé ou retiré → ses agents aussi ; jamais l'inverse (D14) |
| `time_entries_guard` | avec un JWT : `user_id` et `workspace_id` immuables ; pas d'insertion pour un agent ; `source` limité à nul, `app` ou `activity` à l'insertion, puis immuable |
| `time_entries_running_limit` | sortie immédiate si l'utilisateur est un agent |
| `team_scope_wanted` | + (pilote, agent) et (chef du pilote, agent) |
| `pilots_agent(wid, uid)` (nouveau) | vrai si l'utilisateur connecté est le pilote de l'agent `uid` ; ajouté aux politiques UPDATE et DELETE de `time_entries` et à `time_entry_tags_write` |
| `agent_entry_write(…)` (nouveau, `security definer`, appelé par Flask) | applique une écriture d'agent après les contrôles de `time_entries_guard` : verrou, `lock_entries_before` (`user_local_date`), période approuvée, facture. Refus → rien n'est écrit (D7.8) |
| `handle_new_user` | pas d'espace personnel si `raw_app_meta_data->>'kind' = 'agent'` |

RLS :
- `activity_rules` : lecture et suppression logique de ses propres lignes ; création par Flask, qui
  réattribue les entrées et suggestions concernées (D9).
- `time_suggestions` :
  - lecture de ses lignes ; pas d'insertion côté client ;
  - en mise à jour, le client ne change que `status`, `project_id`, `task_id`, `description` et `time_entry_id`, ce que contrôle un trigger de garde.
- Comme le connecteur envoie `patch` → `update`, aucune politique INSERT n'est nécessaire sur cette table.
- `code_repositories` et `code_commits` : lecture par les membres du workspace, écriture par le serveur seulement.
- Entrées d'agent : les politiques de `time_entries`, avec D15.

**Purge** : `purge_soft_deleted` supprime physiquement des `time_entries`. Les clés vers elles sont donc en
`on delete cascade` (`agent_entries`) ou `set null` (`code_commits.time_entry_id`,
`time_suggestions.time_entry_id`), sans quoi la purge échouerait et s'arrêterait avant les tables suivantes.

**À aligner**, comme toute colonne synchronisée : la migration, `schema.dart`, `database.dart` et
`sync-config.yaml`, puis `make app-gen`. Colonnes : `workspace_members.kind` et `agent_owner_id`,
`workspaces.agent_billing`, `projects.agent_billable`, `time_entries.source` (toutes nullables côté Drift) ;
tables `activity_rules` et `time_suggestions` (flux `my_time_entries`). Ne jamais écrire `Value(null)` dans
une colonne non nulle côté serveur : `put` n'envoie pas les nuls (le défaut serveur s'applique), mais `patch`
envoie ce qu'on écrit.

## 5. Services Flask

- `POST /api/tokens` `{workspace_id, name}` → `{id, token}`, `GET /api/tokens?workspace_id=…` et
  `DELETE /api/tokens/<id>` (JWT utilisateur, `require_workspace`). La liste et la révocation portent sur
  ses propres jetons (`user_id = g.user`) ; un admin voit et révoque ceux de son workspace. La création
  appelle `ensure_agent`.
- `services/agents.py` : `ensure_agent(conn, workspace_id, pilot_id)`. Il ne fait que créer, sous verrou
  consultatif par pilote : le compte technique s'il n'existe pas (D14), puis le membre agent du workspace
  s'il n'y a aucune ligne pour lui. Il ne réactive rien.
- `services/entry_defaults.py` : `entry_defaults(conn, workspace_id, user_id, project_id)` → facturable et
  taux, extrait de `kiosk.punch` et utilisé par le kiosque et les agents. Pour un agent, il applique D16.
- Décorateur `require_user_or_token` : JWT Supabase (l'app) ou `Authorization: Bearer clk_…` (hooks,
  extension, MCP) → `g.user`, `g.workspace_id`. Pour un jeton, il contrôle que l'utilisateur est toujours
  membre actif du workspace et met à jour `last_used_at`. Les routes `/api/activity/*` l'utilisent.
- `POST /api/activity/events` (hooks et extension) : lot d'événements (≤ 200), insertion
  `on conflict (id) do nothing`. Puis, pour chaque session touchée, recalcul D7 sous verrou et écriture par
  `agent_entry_write`. Réponse 202. Les événements datés de plus de 5 minutes dans le futur ou de plus de
  7 jours sont rejetés.
- `GET /api/activity/today` : mon temps, celui de Claude (entrées de mon agent) et la durée calendaire, par
  projet, avec les sessions en cours. Il sert à la barre d'état de l'extension et au MCP.
- `GET /api/activity/projects` : projets et tâches du workspace, pour le choix du projet dans l'extension.
- `POST /api/activity/rules` `{remote_key | path_prefix | time_entry_id, project_id, task_id?}` : crée une
  règle de rattachement depuis l'extension ou l'app (D9) et réattribue. Avec `time_entry_id`, le dépôt est lu
  dans `agent_entries`.
- `POST /api/activity/presence` (lot 4, JWT de l'app macOS) : signal de présence (D4.3).
- **Marketplace de l'instance** (publique, sans jeton : le plugin ne contient aucun secret) :
  - `GET /api/claude/marketplace.json` : la marketplace `clockifai`, qui référence l'archive ci-dessous ;
  - `GET /api/claude/clockifai-plugin.zip` : l'archive de `integrations/claude-code/` (manifeste, hooks,
    script), avec l'adresse de l'instance posée comme valeur par défaut de `userConfig.url`. L'adresse est
    celle de la requête (hôte et `X-Forwarded-Proto` transmis par Caddy). Le zip est reproductible (dates et
    droits fixes) et construit à la première demande depuis les fichiers embarqués dans l'image `services` :
    le contexte de build étant `services/`, `docker-compose.yml` lui ajoute `integrations/` par
    `additional_contexts`.
  - Claude Code n'accepte qu'un **zip** servi en **HTTPS**, hors `localhost` (vérifié avec
    `claude plugin validate`, v2.1.309). L'entrée de la marketplace porte le `sha256` du zip et le plugin n'a
    pas de `version` : l'empreinte en tient lieu, donc un plugin modifié par une mise à jour de l'instance est
    proposé aux postes.
  - En local, la marketplace `clockifai-dev` est le dossier `integrations/` du dépôt
    (`integrations/.claude-plugin/marketplace.json`), car l'archive servie en `http://localhost` est refusée.

  Chaque instance auto-hébergée distribue ainsi la version du plugin qui correspond à son API, sans GitHub.
- `routes/kiosk.py` : `state` exclut les agents ; `punch` écrit `source = 'kiosk'` et utilise
  `entry_defaults()`.
- `services/exporters.py` : colonne « Type » (humain ou agent) dans le détail, après l'utilisateur, en CSV,
  Excel et PDF, et dans le CSV hors ligne de l'app (`human` / `agent`). Fait le 24 octobre 2026.
- Jobs :
  - `close_idle_agent_entries` toutes les minutes (D7.4) ;
  - `aggregate_human_activity` toutes les 5 minutes (D8) ;
  - `purge_activity_events` chaque nuit (30 jours) ;
  - `auto_stop_long_timers` (existant) reste un filet de sécurité, agents compris. Une entrée qu'il arrête
    est figée (D7.8).

## 6. Clients : plugin Claude Code et extension VSCode

### 6.1 Plugin Claude Code — `integrations/claude-code/`

**Connexion d'un poste**, une fois par poste :
1. Dans l'app, Réglages › Intégrations › « Connecter Claude Code ». On nomme le poste ; l'app affiche le
   jeton `clk_…` une seule fois, avec deux commandes à lancer **dans un terminal** (`/plugin` n'existe pas
   dans l'extension VSCode, §2) :
   ```
   claude plugin marketplace add https://clockifai.kysoe.com/api/claude/marketplace.json
   claude plugin install clockifai@clockifai
   ```
   Il faut la commande `claude` à jour sur le poste : le binaire embarqué par l'extension VSCode n'est pas sur
   le `PATH`. L'écran commence donc par `claude --version` et, à défaut, la commande d'installation officielle
   (`curl -fsSL https://claude.ai/install.sh | bash`, ou `irm https://claude.ai/install.ps1 | iex` sous Windows),
   ajoutée le 24 octobre 2026. Dans Claude Code en terminal, `/plugin marketplace add …` et `/plugin install …` font la même
   chose.
2. `claude plugin install` **ne demande rien** (vérifié le 23 octobre 2026, v2.1.309) : il signale l'option
   requise manquante. L'URL a une valeur par défaut dans l'archive, mais Claude Code la montre « not set » et
   ne la transmet pas au hook (constaté le 24 octobre 2026 : un poste configuré avec son seul jeton n'envoyait
   rien). Le presse-papiers porte donc `{"url": …, "token": …}`, et le script relit la valeur par défaut dans
   `plugin.json` si l'adresse manque, en notant tout réglage manquant dans `hook.log`. Le jeton se donne par
   `claude plugin configure clockifai@clockifai --values-stdin` (v2.1.285 et plus), qui lit un objet JSON sur
   l'entrée standard et le range dans le magasin sécurisé du système. L'écran Intégrations copie donc une
   commande qui lit le presse-papiers, par exemple
   `pbpaste | claude plugin configure clockifai@clockifai --values-stdin` avec `{"url": "https://…", "token": "clk_…"}` copié,
   ce qui garde le jeton hors de l'historique du shell, contrairement à `--config token=…`. Copier la
   commande remplace le presse-papiers : l'écran fait donc coller la commande sans la lancer, puis copier le
   jeton, puis appuyer sur Entrée (`pbpaste` lit au lancement). Dans Claude Code
   en terminal, `/plugin configure` ouvre la même saisie. L'installation au niveau utilisateur couvre
   tous les projets du poste, dans le terminal, VSCode et l'app desktop ; le plugin se charge à la session
   suivante.
3. Au prompt suivant, l'agent démarre un chronomètre. Intégrations affiche « dernier événement reçu il y a
   3 s » (`last_used_at`).

Un poste, un jeton. En équipe, un dépôt peut proposer le plugin dans son `.claude/settings.json` ; chacun
l'installe et saisit son propre jeton.

**Selon l'endroit où l'on utilise Claude** :

| Où | Branchement | Temps compté automatiquement |
|---|---|---|
| Claude Code sur le poste (terminal, VSCode, app desktop) | plugin, niveau utilisateur | oui |
| Plusieurs sessions sur le même projet | rien de plus : un chronomètre par session (D7), tâche par session (D9), commits par session (D13) | oui |
| Un autre poste | même plugin, un jeton par poste | oui |
| Claude Code sur le web (sessions cloud) | hook dans le dépôt, réseau et secret de l'environnement (§6.3) | pas pour l'instant (lot 6) |
| claude.ai, chat de l'app desktop, mobile | aucun hook | non : connecteur MCP (lot 5) pour consulter et saisir |

```
integrations/claude-code/              servi par l'instance (§5), pas par GitHub
├─ .claude-plugin/plugin.json          userConfig : url (défaut : l'instance), token (sensitive) ; send_excerpts au lot 4
├─ hooks/hooks.json                    UserPromptSubmit, PostToolUse, Stop, SubagentStop,
│                                        Notification (matcher permission_prompt), SessionStart, SessionEnd → async
├─ scripts/clockifai_hook.py           Python 3.9 (celui de macOS), bibliothèque standard uniquement
├─ .mcp.json                           lot 3 : {"clockifai": {"type": "http", "url": "${user_config.url}/mcp",
│                                        "headers": {"Authorization": "Bearer ${user_config.token}"}}}
└─ commands/                           lot 3 : aujourdhui.md, decrire.md, tache.md, valider.md
```

Le script `clockifai_hook.py` :
- lit l'URL et le jeton dans `CLAUDE_PLUGIN_OPTION_URL` et `CLAUDE_PLUGIN_OPTION_TOKEN` ;
- lit stdin et garde la liste blanche de D6 ;
- ajoute `remote_key` (normalisation de `git remote get-url origin`, sinon `local:<dossier racine>`),
  `git branch --show-current` et `cwd` ;
- génère `event_id` (uuid4) et `occurred_at` (UTC) ;
- **n'écrit rien sur stdout**, et termine toujours avec le code 0 ;
- limite `PostToolUse` à un événement par minute et par session (horodatage dans `~/.cache/clockifai/`),
  sauf pour un outil d'une minute ou plus, qui peut prolonger l'entrée (D7.6) ;
- détecte les commits nouveaux après chaque `PostToolUse` de `Bash` et au `Stop`, et ne revendique pour sa
  session que ceux qui suivent l'une de ses commandes git qui crée des commits (D13). Le dernier HEAD vu par
  dossier de travail est conservé dans `~/.cache/clockifai/`. Cette vérification n'est pas soumise à la
  limite d'un événement par minute ;
- (lot 3) reconnaît les outils Clockifai par leur suffixe (`…__set_current_task`, `…__describe_current_work`), quel
  que soit le préfixe que Claude Code donne au serveur d'un plugin, et envoie `session_task` ou
  `session_description` avec leur réponse JSON (D9) ;
- en cas d'échec réseau ou d'erreur 5xx (délai de 2 s), ajoute l'événement à `~/.cache/clockifai/spool.jsonl`,
  renvoyé au prochain appel réussi (au-delà de 6 jours et demi, il est abandonné : le serveur le refuserait).
  Un refus (401 d'un jeton révoqué, 400) n'est pas réessayé. Les échecs sont notés, sans le contenu des
  événements, dans `~/.cache/clockifai/hook.log`.

Les commandes :
- `/clockifai:aujourdhui` : mon temps et celui de Claude aujourd'hui (MCP `get_summary`).
- `/clockifai:decrire` : Claude résume en une ligne le travail de la session et appelle `describe_current_work`.
- `/clockifai:tache` : Claude cherche la tâche (`list_projects`) d'après l'argument ou le travail en cours,
  la fait confirmer, puis appelle `set_current_task`.
- `/clockifai:valider` : liste mes suggestions en attente et les accepte ou les ignore après confirmation.

### 6.2 Extension VSCode — `integrations/vscode/`

- TypeScript, compilée avec `esbuild`. Elle fonctionne aussi dans Cursor, Windsurf et VSCodium.
- **Connexion** :
  - réglage `clockifai.url` ;
  - jeton dans `SecretStorage`, saisi par la commande « Clockifai : se connecter », qui vérifie le jeton par `GET /api/activity/today`.
- **Clé du dépôt** : `remote_key`, même normalisation que le hook, via l'extension `vscode.git` ou
  `git remote get-url`. En multi-racine, le dossier de l'éditeur actif prime.
- **Signaux** (D8) :
  - `focus_start` / `focus_alive` (60 s) / `focus_end` selon `window.state.focused && window.state.active` ;
  - `edit` (au plus un par minute) ;
  - `terminal` (début d'une commande dans le terminal intégré, sans la commande elle-même) ;
  - `commit` (D13), sur `repository.state.onDidChange` de l'API `vscode.git`.
- **Plusieurs fenêtres** : chaque fenêtre a son instance avec un `window_id` aléatoire. Seule la fenêtre qui a
  le focus envoie des signaux `focus_*`, ce qui respecte la règle « une seule attention ».
- **Envoi** par lots toutes les 60 s et à la perte du focus. En cas d'échec, une file locale dans
  `globalStorageUri` est renvoyée au lot suivant.
- **Barre d'état** :
  - `◷ 3h10 · Claude 5h40 · 2 sessions` (via `GET /api/activity/today`, rafraîchi toutes les 60 s) ;
  - un clic ouvre un menu : projet de ce dossier, rattacher à un autre projet, ouvrir Clockifai.
- **Commandes** :
  - se connecter, se déconnecter ;
  - rattacher ce dossier à un projet : QuickPick sur `GET /api/activity/projects`, puis `POST /api/activity/rules` ;
  - ouvrir Clockifai.
- **Diffusion** : un `.vsix` joint aux releases du dépôt d'abord, puis Open VSX et VS Marketplace.

### 6.3 Sessions cloud (Claude Code sur le web) — lot 6, plus tard

Les plugins n'y sont pas chargés ; seuls les hooks du `.claude/settings.json` du dépôt s'exécutent (§2).
- **Hook de dépôt** : un hook `command`, déclaré dans chaque dépôt suivi, qui n'agit que si
  `CLAUDE_CODE_REMOTE=true`. En local, c'est le plugin qui compte : pas de double comptage. Il poste
  l'événement brut (`curl`, délai de 2 s) vers `POST /api/activity/events/raw`.
- **Environnement cloud** :
  - réseau « Custom », avec l'hôte de l'instance ajouté à la liste autorisée ;
  - jeton déclaré en **secret réseau** : le proxy ajoute l'en-tête `Authorization`, le jeton n'entre jamais
    dans la machine.
- **Serveur** :
  - il applique la liste blanche de D6 à l'arrivée, et non sur le poste. C'est une exception à D6 : le
    prompt et le contenu des outils transitent, mais ne sont jamais enregistrés ;
  - il déduit le dépôt du nom du dossier (`cwd`). Pas de branche, pas de commits vus en local : la forge
    (plan 09) prend le relais.
- Sessions à plusieurs dépôts : non suivies, faute de hooks.

## 7. Serveur MCP — service `mcp` dans `deploy/`

- Conteneur `clockifai-mcp`, même image que `services`, avec une autre commande et `JOBS_ENABLED=false`
  (D11). Caddy route `/mcp` sur le domaine de l'app (`https://clockifai.kysoe.com/mcp`) : le domaine Supabase
  route déjà son propre `/mcp` vers Kong.
- Authentification : jeton personnel (D5) ; OAuth plus tard (D12).
- Outils (réponses en JSON structuré) :

| Outil | Rôle |
|---|---|
| `list_projects(query?)` | projets et tâches du workspace |
| `get_summary(period, group_by)` | mon temps (saisi et suggéré), celui de Claude et la durée calendaire, par projet, tâche ou jour |
| `list_suggestions(day?)` | mes suggestions en attente |
| `accept_suggestions(ids, project_id?, task_id?, description?)` | crée les entrées et marque les suggestions acceptées, dans une transaction |
| `dismiss_suggestions(ids)` | ignore les suggestions |
| `describe_current_work(description)` | valide la description et la renvoie ; le hook l'applique à l'entrée de sa session (D9) |
| `set_current_task(task_id or query)` | résout la tâche (et son projet) et la renvoie ; le hook l'applique à l'entrée de sa session et aux suivantes (D9) |
| `add_time_entry(project_id, start, end, description, task_id?)` | saisie manuelle (`source = 'app'`) |
| `map_repository(remote_key or path, project_id, task_id?)` | crée une `activity_rule` et réattribue les entrées d'agent sans projet et les suggestions en attente |

## 8. Application Flutter

- **Paramètres → Intégrations → Claude Code** (fait le 24 octobre 2026, `features/integrations/claude_code.dart`) :
  - créer un jeton (nom du poste), affiché une seule fois avec les étapes : commande `claude` (`claude --version`, sinon son installation), installation du plugin (marketplace
    de l'instance, ou `clockifai-dev` pour une instance en http), « Copier le jeton » qui met
    `{"token": "clk_…"}` dans le presse-papiers, et `pbpaste | claude plugin configure … --values-stdin`
    (`Get-Clipboard` sous Windows, `wl-paste` sous Linux) ;
  - lister (tous ceux du workspace pour un admin) et révoquer les jetons, avec le dernier événement reçu ;
  - « Reconnecter » sur ses propres postes : nouveau jeton du même nom, révocation de l'ancien, étapes affichées
    (le jeton n'est jamais réaffiché) ; « Afficher les commandes d'installation » montre les étapes sans jeton,
    l'étape 3 renvoyant à « Reconnecter » (24 octobre 2026) ;
  - « Votre agent : Claude · Yannick » dans le texte d'introduction, et un avertissement quand un admin l'a
    désactivé ou retiré (`agent_id` nul dans `GET /api/activity/today`, D7.10). « Voir sa fiche dans
    l'équipe » ouvre `/team?member=<agent>`, qui amène la fiche à l'écran et la met en évidence (fait le
    24 octobre 2026) ;
  - lot 2 : le bloc de l'extension VSCode (jeton à coller dans « Clockifai : se connecter »).
- **Paramètres du workspace** (admins) : « Temps des agents Claude : facturable comme le temps des personnes /
  jamais facturable » (D16). Fait le 24 octobre 2026, toujours affiché, pour régler avant de connecter un poste.
- **Fiche projet** : « Temps des agents Claude : comme le réglage du workspace / facturable / non facturable »
  (D16). Fait le 24 octobre 2026, affiché quand le workspace compte un agent ou que le projet a une exception.
- **Droits** (`core/catalog.dart`, `core/team_rights.dart`), faits le 24 octobre 2026 :
  - getters `humans`, `agents` et `agentsOf(pilote)` ;
  - `billableFor(projet, membre)` à côté de `rateFor` : D16 pour un agent, `billable_default` sinon. Il est
    recalculé quand le pilote choisit un autre projet pour une entrée d'agent (`entry_dialog.dart`), et reste
    modifiable à la main ;
  - `managed` et `catalog.managersOf` ignorent les agents ; `agentsSeen` donne les agents du périmètre, que
    `visibleMembers` inclut (D15) ;
  - `canEditTimeOf` (modifier, supprimer) inclut le pilote de l'agent ;
  - `canCreateTimeFor` (créer) exclut toujours les agents. Il sert à `editableMembers` (saisie pour autrui,
    `team_entry_page.dart`, `entry_dialog.dart`) et à la création depuis `TeammateBar`, la feuille de temps
    et le calendrier.
- **Équipe** (`features/team/team_page.dart`), fait le 24 octobre 2026 :
  - section « Agents » : icône robot, pilote, chronomètres en cours, total de la semaine ; e-mail technique masqué ;
  - menu admin limité aux taux, au nom, à la désactivation ou réactivation et au retrait (ni rôle, ni chef d'équipe, ni PIN) ;
  - agents exclus des choix de chef d'équipe et de groupe (D15 les rattache par leur pilote).
- **Absences et planning** (faits) : agents exclus des droits à congés (`time_off_page.dart`) et des lignes du
  planning (`schedule_page.dart`). La feuille de temps d'un agent est en lecture seule, sans bandeau de soumission ;
  son calendrier ne crée pas d'entrée ; « Dupliquer » n'est pas proposé sur ses entrées.
- **Page des entrées du jour** :
  - bandeau « Claude travaille » = entrées en cours de mes agents (`AgentsWorkingBanner`, `watchRunningOf`), fait le
    24 octobre 2026 : une ligne par session (description, projet, durée qui tourne), qui ouvre le dialogue de l'entrée
    (projet, « toujours rattacher ») ; absent sans session en cours ; un manager n'y voit que ses propres agents ;
  - un bandeau « N suggestions » qui mène à la liste des suggestions.
- **Temps de Claude** : il se consulte et se corrige comme celui d'un collaborateur encadré. On passe par le
  sélecteur de personne (`TeammateBar`) de la feuille de temps et du calendrier, puis par les rapports.
  Quand un projet est choisi pour une entrée d'agent sans projet, l'app propose « toujours rattacher ce
  dépôt » (`POST /api/activity/rules` avec `time_entry_id`, en ligne) : fait le 24 octobre 2026, case cochée par
  défaut dans le dialogue de l'entrée, pour le pilote seulement. Le dialogue n'écrit plus les heures qu'il n'a
  pas changées (`changedTime`) : il ne saisit pas les secondes, et réécrire une fin inchangée figeait l'entrée
  d'agent (D7.8). Une entrée d'agent n'affiche pas « saisi par » son pilote.
  La règle créée par l'app ne retient que le projet (24 octobre 2026) : avec la tâche, toutes les sessions
  suivantes du dépôt seraient allées dans la tâche d'une seule. « Nouvelle tâche », sous le projet dans le
  dialogue de l'entrée, crée la tâche et la sélectionne (même aide que le « + » du sélecteur,
  `promptNewTask`) ; une session reprise après la pause garde ce projet et cette tâche, sauf changement de
  branche (D9, testé par `test_resumed_session_keeps_the_task_chosen_in_the_app`). Un pilote qui travaille sur
  `main` donne ainsi une tâche à chaque sujet, sans attendre le lot 3.
- **Suggestions** :
  - chaque ligne montre le projet (ou le dépôt inconnu → choix du projet et règle), la plage, la durée, le temps de Claude sur la même plage et une description modifiable ;
  - actions : accepter, ignorer, tout accepter ;
  - l'acceptation crée l'entrée (`source = 'activity'`, taux et facturable selon les règles actuelles) et met à jour la suggestion, en une transaction locale.
- **Rapports** : filtre « Humains et agents / Humains / Agents » (défaut : les deux) à côté du filtre par membre,
  affiché dès qu'un agent est visible ; il restreint aussi la liste des personnes et passe `member_kind` à l'export
  serveur (`/api/exports/report`). Le regroupement par membre montre l'agent comme une personne. Fait le
  24 octobre 2026.
- **Calendrier** (lot 4) : les entrées de mon agent dans une voie à part, à côté des miennes ; les
  suggestions en blocs en pointillés.
- **Barre de menus macOS** (lot 4) : nombre de sessions en cours, et signal de présence (D4.3).
- **Entrées** : petite étiquette « Activité » quand `source = 'activity'`.
- ARB FR/EN pour tous les libellés.

## 9. Tests

- `services/tests/` (unitaires, sans base) :
  - D7 :
    - pas de chronomètre au `SessionStart`, ouverture au premier prompt ;
    - prompt sous `IDLE_TIMEOUT` : l'entrée continue ;
    - fin rétroactive à la dernière activité ;
    - `SessionEnd` ;
    - commande longue prolongée, attente d'autorisation qui ouvre une nouvelle entrée ;
    - deux sessions simultanées ;
    - recalcul : événements en retard ou en double, même résultat qu'à l'heure ;
    - entrées figées : arrêt manuel, arrêt automatique, fin corrigée, suppression. Elles ne sont pas
      modifiées, et leur plage n'est pas recréée ;
    - projet changé dans l'app : la durée continue, le projet n'est pas écrasé ;
  - D8 :
    - intervalles de focus : début, signes de vie, fin, fin implicite après 2 minutes sans signe de vie ;
    - regroupement à 15 min des autres signaux ;
    - une seule attention entre deux fenêtres et deux projets ;
    - coupure par la présence ;
    - plages déjà couvertes par une entrée saisie à la main exclues ;
    - recalcul différentiel : une suggestion garde son id et mes modifications quand son début bouge ;
  - D9 : normalisation de `remote_key` (ssh, https, port, sous-groupes) ; deux worktrees, une clé ; deux
    dépôts de même nom, deux clés ; priorité règle de chemin, règle de dépôt, projet du dépôt ; priorité des
    sources de la tâche ; trois sessions dans le même dossier, chacune avec son `session_task` ; une nouvelle
    entrée reprend la tâche de la précédente, sauf changement de branche ; un choix fait dans l'app n'est pas
    écrasé ;
  - `entry_defaults` : taux du projet, sinon du membre ; facturable selon le projet ; pour un agent, D16
    (`like_humans`, `never`, exception du projet dans les deux sens) ;
  - D10 : description saisie jamais écrasée ; description de Claude remplacée par la suivante seulement ;
  - D13 côté serveur : commit rattaché à l'entrée d'agent de sa session ou à l'intervalle de focus de sa
    fenêtre, descriptions tirées des messages.
- `services/tests/integration/` :
  - migrations depuis une base vide : les tables privées sont créées par `0012_activity_private.admin.sql` ;
  - jetons : création, révocation, jeton d'un ancien membre refusé, un membre ne voit ni ne révoque les
    jetons d'un autre ;
  - marketplace : `marketplace.json` référence l'archive et son empreinte, et le `plugin.json` de l'archive
    porte l'URL de l'instance (`services/tests/test_claude_plugin.py`) ; installation réelle contre la prod,
    l'archive en `http://localhost` étant refusée ;
  - le script du plugin lancé comme par Claude Code, avec le python3 de macOS, jusqu'à l'entrée de l'agent
    décrite par le message du commit et au commit rattaché (`test_hook_script_end_to_end`) ;
  - agents (D14, D15) :
    - `ensure_agent` : deux créations de jeton simultanées → un seul compte ; l'agent ne peut pas se
      connecter ; pas d'espace personnel ;
    - le pilote lit, modifie et supprime les entrées de son agent avec `time_for_others = 'admins'`, un
      autre membre non ; le chef d'équipe du pilote les lit ;
    - le pilote ne peut ni créer une entrée pour son agent, ni changer `user_id` d'une entrée ; un admin ne
      peut pas créer d'entrée d'agent ;
    - trois sessions = trois chronomètres, même avec `max_running_timers = 1`, y compris sur la même tâche ;
    - pilote désactivé → agent désactivé ; pilote réactivé → agent toujours désactivé ; agent retiré par un
      admin → un nouveau jeton ne le recrée pas, ses événements ne produisent rien ;
    - un admin ne peut ni insérer un membre `kind = 'agent'` ni changer `kind` ;
    - `kiosk/state` sans agents ; facture créée avec les entrées facturables de l'agent, et sans elles quand
      `agent_billing = 'never'` ou `agent_billable = false` sur le projet ; `agent_billable` du projet l'emporte
      sur le réglage du workspace, dans les deux sens ;
  - `agent_entry_write` refuse une écriture dans une entrée verrouillée, avant `lock_entries_before`, dans une
    période approuvée ou facturée ;
  - envoi d'événements idempotent ; deux lots simultanés d'une même session → une seule entrée ; entrée
    d'agent ouverte puis fermée par le job ;
  - purge de nuit avec entrées d'agent, commits et suggestions liés : aucune erreur de clé étrangère ;
  - le job crée et met à jour les suggestions ;
  - RLS : pas d'accès aux suggestions et règles d'autrui ; `source` imposé par un client refusé ;
  - MCP : une écriture dans une période verrouillée est rejetée par la garde ; le conteneur ne lance pas
    les jobs.
- `app/test/` : acceptation d'une suggestion, application d'une règle, totaux par piste,
  `TeamRights` (le pilote modifie mais ne crée pas, n'est pas chef d'équipe, voit son agent),
  `catalog.humans` / `agents`, `catalog.billableFor`, filtre des rapports.
- Plugin : le script avec un stdin factice et un serveur HTTP local.
  - stdout vide ;
  - `tool_input` jamais envoyé ;
  - file locale remplie quand le serveur est coupé, puis vidée ;
  - outils Clockifai reconnus par leur suffixe, avec ou sans préfixe de plugin ;
  - notifications autres que `permission_prompt` ignorées ;
  - commits, dans un dépôt git temporaire :
    - un nouveau commit → un événement ;
    - trois commits dans une même commande → trois événements ;
    - changement de branche ou `pull` de commits d'autrui → aucun événement ;
    - `commit --amend` → un nouveau sha ;
    - deux sessions dans le même dossier : A commite, B lance une commande avant la vérification de A → le
      commit va à A ;
    - commit fait hors de Claude → envoyé sans session au `Stop` suivant ;
    - deux worktrees du même dépôt → un dernier HEAD vu pour chacun ;
  - URL et jeton lus dans `CLAUDE_PLUGIN_OPTION_*`.
- Extension (`@vscode/test-electron`) :
  - changement d'état de fenêtre simulé → `focus_start` puis `focus_end` ;
  - aucun chemin de fichier dans les événements ;
  - file locale remplie quand le serveur est coupé, puis vidée ;
  - un commit vu à la fois par le hook et par l'extension ne crée qu'une ligne `code_commits`.
- Bout à bout, contre la pile locale : deux fenêtres VSCode sur deux dépôts, on alterne. Les signaux `focus_*`
  ne viennent que de la fenêtre active, et les suggestions ne se chevauchent pas.

## 10. Lots

| Lot | Contenu | Taille | État |
|---|---|---|---|
| 1 Temps de Claude | Migrations 0012 (tables privées) et 0013 (membres agents, `source`, `code_repositories`, `code_commits`, règles, gardes, `pilots_agent`, `agent_entry_write`, D15, D16), Flask (jetons, `ensure_agent`, `entry_defaults`, `require_user_or_token`, `events` avec recalcul D7, règles, jobs `close_idle_agent_entries` et `purge_activity_events`, marketplace de l'instance), plugin minimal (hooks seuls, commits de Claude D13 avec attribution par session), descriptions tirées des commits, app (fait : écran des jetons, droits D15, exclusions, section Agents, « toujours rattacher », bandeau « Claude travaille », filtre des rapports, colonne « Type » des exports, réglages de facturation des agents, lien de l'écran Intégrations vers la fiche de l'agent) ; hooks vérifiés dans l'extension VSCode | M/L | fait |
| 1c Tâche nommée par Claude (D18) | Serveur MCP local du plugin (`set_current_task`), relais `session_task` `{task_name}` par le hook, `subject_task` et découpage des entrées par sujet (`agent_clock`), « préciser = renommer » (`agent_tasks`, 0014), réglage « Tâches de Claude » par pilote (`profiles.claude_tasks`, 0015), tests unitaires, du plugin et d'intégration, essai réel avec Claude Code | S/M | fait |
| 2 Mon temps | Extension VSCode (signaux, commits, barre d'état, rattachement), prompts comme signal humain, `time_suggestions`, job D8, écran Suggestions | L | validé |
| 3 MCP | Service `mcp`, outils (`set_current_task` déjà fait en local, lot 1c), `.mcp.json`, commandes du plugin et relais `session_description` par le hook | M | validé |
| 4 Confort | Calendrier, barre de menus macOS, signal de présence (`/api/activity/presence`), extraits de prompt | M | validé |
| 5 Connecteur claude.ai | OAuth (selon Supabase Auth auto-hébergé), publication du connecteur | M, conditionnel | envisagé |
| 6 Sessions cloud | Hook de dépôt, `POST /api/activity/events/raw` avec filtrage à l'arrivée, guide de réglage de l'environnement (réseau, secret réseau) | S, plus tard (§12) | envisagé |
| 7 Usage IA (D17) | Lecture de la transcription au `Stop` et `SubagentStop` (totaux par modèle et effort, dédoublonnés par `message.id`), événement `agent_usage`, table répliquée `agent_usage` et ses flux, prix `ai_model_prices`, coût estimé, affichage (entrée, rapports, exports, carte de l'agent) | M | validé |

Documentation : section « Le temps de Claude Code » du guide (page Membre) et vidéo 6, « Alex et son agent
Claude » (`demo/videos/6-claude-code.mjs`, 26 octobre 2026). Son historique et sa session en direct passent par
`POST /api/tokens` et `POST /api/activity/events`, comme le plugin.

## 11. Points d'attention

- **Horloge client** : `occurred_at` est fourni par le poste et `received_at` est conservé ; on rejette les écarts aberrants (§5).
- **Confidentialité** : les événements bruts ne sont visibles de personne dans l'app. Les suggestions sont personnelles. Le temps de Claude est visible des managers comme celui de tout membre.
- **E-mail technique de l'agent** : vérifié, GoTrue v1.26.08 accepte `agent-<pilote>@agents.clockifai.invalid`
  en création admin. Il pose `app_metadata` après l'insertion : `handle_new_user` lit aussi `user_metadata.kind`
  (D14).
- **Installation du plugin depuis VSCode** : faute de `/plugin` dans l'extension, elle passe par un terminal.
  L'écran Intégrations doit le dire clairement, et le guide utilisateur aussi.
- **Factures** : `createInvoiceFromTime` regroupe les lignes par (projet, taux). Les heures de Claude se
  mêlent donc à celles des humains au même taux. « Détailler par tâche » les sépare quand Claude a nommé ses
  tâches (plan 12). Un taux « IA » par projet, distinct du taux du projet, serait un ajout ultérieur.
- **Sessions parallèles pour un même client** : le cumul est facturé (D2). Pour l'éviter : D16 (non
  facturable), ou la piste de la durée calendaire.
- **Approbations** : l'approbation de la période du pilote ne verrouille pas les entrées de son agent.
  Acceptable en v1 ; à revoir si l'on facture sur périodes approuvées.
- **Fuseau du pilote** : copié dans le profil de l'agent à la création. Le fuseau n'est pas encore
  modifiable dans l'app (plan 01) ; quand il le sera, le changement devra suivre.
- **Renommage du pilote** : le nom de l'agent n'est pas recalculé.
- **Archive du plugin** : zip en HTTPS seulement (§5) ; reste à vérifier sur un poste que le changement
  d'empreinte propose bien la mise à jour (`claude plugin update`).
- **python3 sur le poste** : les hooks lancent `python3`. Sur un Mac sans outils de développement,
  `/usr/bin/python3` propose leur installation au lieu de s'exécuter : Clockifai vise les développeurs, qui
  les ont, mais l'écran Intégrations doit le dire.
- **Alias git** : un commit lancé par un alias (`git ci`) n'est pas reconnu comme venant de la session. Il
  part sans session (D13).
- **Délai de `window.state.active`** : la durée avant de passer inactif n'est pas documentée. Il faut la mesurer au lot 2. Si elle est trop courte pour une lecture, prolonger le focus de quelques minutes après `focus_end`, tant que la fenêtre garde le focus.
- **Fenêtre sans dossier** : elle n'est rattachée à rien et ne produit pas de suggestion.
- **Sous-agents en arrière-plan** : ils continuent après `Stop`. Leurs `PostToolUse` prolongent l'entrée (D7.3, D7.6). À vérifier en conditions réelles.
- **Plusieurs workspaces** : un jeton est lié à un seul workspace. Les dépôts de l'autre workspace ont besoin d'un autre jeton ou d'un réglage de dossier, qui reste à concevoir.

## 12. Questions

Tranchées (octobre 2026) :
1. Temps de Claude : **membre agent**, un par pilote, avec de vraies entrées (D2). La table `agent_time` est
   écartée.
2. Facturation : **réglable** (D16). Par défaut, les entrées d'agent sont facturables comme celles d'un
   humain, au taux du projet, sinon à celui de l'agent. Le workspace peut les rendre non facturables, et
   chaque projet peut faire exception.
3. Tâches en parallèle : les temps des sessions simultanées **se cumulent** (D2), chacune sur sa tâche (D9).
4. L'attente entre deux tours compte pour l'agent tant qu'elle reste sous `IDLE_TIMEOUT` (D7.2).
5. Périmètre : Claude Code dans VSCode. Le plugin couvre aussi le terminal et l'app desktop sans effort de
   plus. Les sessions cloud ne sont pas suivies pour l'instant : le lot 6 reste une piste.
6. Le numéro de tâche (`CLK-42`) est un lot préalable (plan 04, lot 0) : il donne la tâche d'une branche (D9).

Ouvertes :
1. Valeurs par défaut : `IDLE_TIMEOUT` 10 min, `HUMAN_TIMEOUT` 15 min, `IDLE_CUT` 5 min ; réglables par utilisateur ?
2. `send_excerpts` désactivé par défaut (proposé) ?
3. Règles de workspace : le projet du dépôt (`code_repositories.project_id`, D9) suffit-il, ou faut-il aussi
   des règles par chemin posées par un admin ?
4. Usage IA (D17) : qui voit les tokens et le coût (le pilote et les managers, ou les managers seulement) ? Prix
   par défaut intégrés et mis à jour avec Clockifai, ou saisis par chaque installation ?
