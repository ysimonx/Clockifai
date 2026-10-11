# Tickets à la Jira — plan (réflexion, non planifié)

> Objectif : savoir si les **tâches** de Clockifai peuvent servir de tickets à la Jira,
> et jusqu'où aller. Statut : **réflexion** (11 octobre 2026), aucun lot engagé.

## 1. Constat : une tâche est déjà un ticket minimal

| Sujet | État | Où |
|---|---|---|
| Table | `tasks` : projet, nom, `estimate_seconds`, statut `active` / `done`, soft delete | `0001_core.sql` |
| Temps passé par tâche | Déjà là : `time_entries.task_id`, donc temps passé et estimation sont comparables | `0001_core.sql` |
| Droits | Lecture par les membres ; création par tous si `task_creation = 'everyone'` (défaut), le créateur peut renommer ; le reste aux **managers** | `0003_rls.sql`, `0010_task_creation.sql` |
| Synchronisation | Flux `workspace_core`, envoyé à tous les membres actifs | `powersync/sync-config.yaml` |
| UI | Liste sous chaque projet (créer, renommer, terminer, supprimer) | `features/projects/projects_page.dart` |
| Fidwork | Interventions importées comme tâches (plan 02) | `plans/02-integration-fidwork.md` |

## 2. Ce qui manque, classé par coût

| Coût | Ajout | Mise en œuvre |
|---|---|---|
| **S** | Numéro lisible `CLK-42`, description, personne assignée, priorité, échéance, statuts `todo` / `in_progress` / `done` | Colonnes sur `tasks`. Numéro posé par trigger serveur, comme la numérotation des factures. Création par les membres : faite (0010). |
| **M** | Tableau kanban, liste « mes tickets », commentaires, historique d'activité | Table `task_comments` synchronisée, trigger d'historique, deux écrans Flutter |
| **L+ (à éviter)** | Pièces jointes hors connexion, notifications, sprints / backlog, workflows personnalisables, épopées et liens entre tickets, recherche avancée façon JQL | Ce qui fait la taille de Jira ; hors du métier d'un outil de temps |

## 3. Points d'attention

- **Enrichir `tasks`, pas créer une table `tickets`** : les entrées de temps, les rapports
  par tâche et l'import Fidwork continuent de fonctionner sans changement.
- **Les trois endroits à aligner** pour chaque colonne : migration SQL, `schema.dart`
  et la table Drift `database.dart` (voir CLAUDE.md).
- **Volume synchronisé** : quelques milliers de tickets dans `workspace_core`, ça passe.
  Les commentaires doivent être limités aux tickets ouverts ou chargés en ligne.
- **Tâches externes** (Fidwork, ou plus tard Jira / GitHub) : en lecture seule dans l'app,
  le système d'origine fait foi.

## 4. Alternative : importer plutôt que gérer

Clockify ne gère pas de tickets, il se branche sur Jira. Le plan 02 prévoit déjà
`external_source` / `external_id` sur `tasks`. Le même mécanisme permettrait d'importer
des tickets Jira, GitHub ou Linear comme tâches, sans gestion de tickets dans Clockifai.

## 5. Décisions (11 octobre 2026)

- Réflexion seulement : aucun lot engagé.
- Si on y va : **tout membre peut créer un ticket** et le commenter. Seuls les managers
  suppriment un ticket ou changent son estimation.
- Périmètre visé le cas échéant : S + M (« tickets légers ») ; L+ exclu.
