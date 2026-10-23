# Tickets à la Jira — plan

> Statut : **validé** pour le lot 0, numéro de tâche (23 octobre 2026) ; **envisagé** pour le reste
> (11 octobre 2026).
>
> Objectif : savoir si les **tâches** de Clockifai peuvent servir de tickets à la Jira,
> et jusqu'où aller.
>
> Plans qui en dépendent : `10-suivi-claude-code.md` (D9 : tâche d'une branche) et `09-forges-git.md`
> (§3 : références, nom de branche proposé).

## 1. Constat : une tâche est déjà un ticket minimal

| Sujet | État | Où |
|---|---|---|
| Table | `tasks` : projet, nom, `estimate_seconds`, statut `active` / `done`, soft delete | `0001_core.sql` |
| Temps passé par tâche | Déjà là : `time_entries.task_id`, donc temps passé et estimation sont comparables | `0001_core.sql` |
| Droits | Lecture par les membres ; création par tous si `task_creation = 'everyone'` (défaut). Le créateur peut renommer (`tasks_update_creator`) ; déplacer, estimer, clore ou supprimer reste aux **managers** (`tasks_guard`) | `0003_rls.sql`, `0010_task_creation.sql` |
| Statut dans l'app | Les sélecteurs ne montrent que les tâches `active` (`catalog.tasksOf`) ; la page Projets bascule `active` / `done` | `core/catalog.dart`, `features/projects/projects_page.dart` |
| Numérotation existante | Factures : compteur par workspace et par an dans `clockifai_private.invoice_counters`, posé par trigger quand le client n'envoie pas de numéro | `0008_private_schema.admin.sql` (`invoices_before_write`) |
| Synchronisation | Flux `workspace_core`, envoyé à tous les membres actifs | `powersync/sync-config.yaml` |
| UI | Liste sous chaque projet (créer, renommer, terminer, supprimer) | `features/projects/projects_page.dart` |
| Fidwork | Interventions importées comme tâches (plan 02, en attente) | `plans/02-integration-fidwork.md` |

## 2. Ce qui manque, classé par coût

| Coût | Ajout | Mise en œuvre | État |
|---|---|---|---|
| **XS — lot 0** | Numéro lisible `CLK-42` | §3 | validé |
| **S** | Description, personne assignée, priorité, échéance, étape `todo` / `in_progress` / `done` | Colonnes sur `tasks` ; l'étape est une colonne **à part** (`stage`), le statut `active` / `done` reste tel quel (§4) | envisagé |
| **M** | Tableau kanban, liste « mes tickets », commentaires, historique d'activité | Table `task_comments` synchronisée, trigger d'historique, deux écrans Flutter. La fiche de tâche elle-même est créée par le plan 09 (lot 1) ; ce lot y ajoute commentaires et historique | envisagé |
| **L+ (à éviter)** | Pièces jointes hors connexion, notifications, sprints / backlog, workflows personnalisables, épopées et liens entre tickets, recherche avancée façon JQL | Ce qui fait la taille de Jira ; hors du métier d'un outil de temps | — |

## 3. Lot 0 — numéro de tâche

**Format** : `<préfixe>-<n>`, par exemple `CLK-42`.
- Préfixe **par workspace** (`workspaces.task_key_prefix`, défaut `CLK`, 2 à 10 lettres ou chiffres
  commençant par une lettre), modifiable par un admin. Une branche nommée avec l'ancien préfixe n'est plus
  reconnue.
- Numéro **par workspace**, pas par projet : une tâche déplacée d'un projet à l'autre garde sa clé.

**Attribution, toujours par le serveur** :
- trigger `before insert` sur `tasks` : le numéro vient d'un compteur `clockifai_private.task_counters`
  (`workspace_id`, `last_value`), sur le modèle de `invoice_counters`. Une valeur envoyée par le client est
  ignorée ;
- un upsert rejoué par PowerSync déclenche aussi le `before insert` : si une tâche de même `id` existe déjà,
  le trigger reprend son numéro au lieu d'en consommer un nouveau. Pas de trou dans la suite ;
- le numéro ne change jamais ensuite, pour personne : contrôle ajouté à `tasks_guard`, avant la sortie
  anticipée des managers ;
- une tâche créée hors ligne n'a pas de numéro avant son envoi. L'app affiche la clé dès qu'elle revient, et
  désactive d'ici là le bouton « créer une branche » (plan 09).

**Reconnaissance** : un seul analyseur, partagé par les plans 09 et 10.
- Côté serveur : `services/app/task_keys.py` ; côté app : son équivalent Dart, pour proposer le nom de branche.
- Insensible à la casse, borné : `(?<![A-Za-z0-9])<préfixe>-(\d+)(?!\d)`. Il reconnaît `CLK-42` dans un message
  de commit ou un titre de demande de fusion, et `clk-42-ajout-export` dans un nom de branche.
- Nom de branche proposé : `clk-42-<titre en minuscules, sans accents, mots séparés par des tirets>`, calculé
  dans l'app (hors ligne).

**Données** :

| Changement | Détail | Sync |
|---|---|---|
| `clockifai_private.task_counters` | `workspace_id` (clé), `last_value`. Dans une migration `*.admin.sql`, comme toute table privée (`postgres` n'a que `usage` sur ce schéma) | non |
| `public.workspaces` | `+ task_key_prefix text not null default 'CLK'` ; la migration « touche » les lignes (petite table) | `workspace_core` (existant) |
| `public.tasks` | `+ number integer`, unique `(workspace_id, number)`. La migration numérote les tâches existantes par ordre de création, workspace par workspace, ce qui les resynchronise une fois | `workspace_core` (existant) |

Comme toujours : migration, `schema.dart`, `database.dart` (colonnes nullables côté Drift), `make app-gen`.

**Tests** : numéro attribué à l'insertion, même si le client en envoie un ; upsert rejoué → même numéro,
compteur inchangé ; numéro immuable, managers compris ; tâche déplacée → même clé ; analyseur : casse, bornes
(`XCLK-42`, `CLK-420` contre `CLK-42`), nom de branche ; tâche créée hors ligne puis synchronisée.

**Taille** : XS/S. À livrer avant le lot 1 du plan 09.

## 4. Points d'attention (lots S et M)

- **Enrichir `tasks`, pas créer une table `tickets`** : les entrées de temps, les rapports
  par tâche et les imports continuent de fonctionner sans changement.
- **Étape plutôt que nouveaux statuts** : ajouter `todo` / `in_progress` au statut casserait la contrainte
  `status in ('active', 'done')` (0001), `tasks_guard`, qui refuse une création par un membre si le statut
  n'est pas `active` (0010), et les sélecteurs, qui filtrent sur `active`. Une colonne `stage` séparée évite
  tout cela.
- **Droits** : la décision « tout membre crée et commente » (§6) suppose aussi que les membres changent
  l'étape, la personne assignée et la description de n'importe quelle tâche. Il faudra une politique de mise
  à jour pour les membres (aujourd'hui, seul le créateur met à jour, `tasks_update_creator`), et une liste
  explicite des colonnes autorisées dans `tasks_guard`.
- **Les trois endroits à aligner** pour chaque colonne : migration SQL, `schema.dart`
  et la table Drift `database.dart` (voir CLAUDE.md).
- **Volume synchronisé** : quelques milliers de tickets dans `workspace_core`, ça passe.
  Les commentaires doivent être limités aux tickets ouverts ou chargés en ligne.
- **Tâches externes** (issues de forge, plan 09 lot 4 ; plus tard Jira ; Fidwork si le plan 02 reprend) :
  en lecture seule dans l'app, le système d'origine fait foi.

## 5. Alternative : importer plutôt que gérer

Clockify ne gère pas de tickets, il se branche sur Jira. L'import d'issues comme tâches
(`external_source` / `external_id` sur `tasks`) est porté par le plan 09, lot 4, maintenant que le plan 02
est en attente. Le même mécanisme permettrait d'importer des tickets Jira ou Linear, sans gestion de tickets
dans Clockifai.

## 6. Décisions

- 11 octobre 2026 : réflexion seulement. Si on y va : **tout membre peut créer un ticket** et le commenter.
  Seuls les managers suppriment un ticket ou changent son estimation. Périmètre visé le cas échéant : S + M
  (« tickets légers ») ; L+ exclu.
- 23 octobre 2026 : le **lot 0** (numéro de tâche) est engagé, parce que les plans 09 et 10 s'en servent pour
  relier branches, commits et sessions de Claude à une tâche. Les lots S et M restent en réflexion.
