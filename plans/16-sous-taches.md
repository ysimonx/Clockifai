# Plan 16 — Sous-tâches

> Statut : **fait** (27 octobre 2026), validé et livré le 27 octobre. Demandé par Yannick : voir le sujet global d'un travail (un plan, une
> fonctionnalité) plutôt qu'une tâche par étape, sans perdre le détail.

## Constat

Depuis D18 (plan 10), Claude nomme une tâche à chaque changement de sujet. Un plan mené sur plusieurs sessions
(« Écarts avec les maquettes », « Version 0.2.4 sur les stores », « Invitations »…) laisse une tâche par étape :
les rapports détaillés en sont pleins, et le sujet d'ensemble ne se voit nulle part. Le réglage « Une tâche par
session » n'y change rien : un plan s'étale sur plusieurs sessions.

Les humains ont le même besoin : un chantier « Unité 4 » découpé en « Montage », « Niveau 3 »…

## Proposition

Un niveau de plus, et un seul : **Projet › Tâche › Sous-tâche**. Une entrée se range sur une tâche ou sur une
sous-tâche ; partout où l'on totalise par tâche, une tâche compte aussi le temps de ses sous-tâches, qu'on déplie
pour le détail.

Pour Claude : la **tâche** porte l'objectif (le titre du plan s'il y en a un : « Plan 14 · Coller aux maquettes »),
stable d'une session et d'un jour à l'autre ; la **sous-tâche** porte l'étape (« Version 0.2.4 sur les stores »).

## Décisions à valider

1. Un seul niveau de sous-tâches (une sous-tâche n'a pas d'enfant).
2. On peut saisir du temps sur une tâche qui a des sous-tâches (le travail général sur le plan).
3. Créer une sous-tâche suit la règle de création des tâches de l'entreprise (`workspaces.task_creation`).
4. Supprimer une tâche supprime ses sous-tâches ; les entrées gardent leur sous-tâche (suppression douce).
5. Rapports : « Grouper par tâche » cumule les sous-tâches, dépliables ; le filtre sur une tâche prend ses
   sous-tâches.
6. Claude : `set_current_task` reçoit l'objectif (`name`, obligatoire) et l'étape (`step`, facultative) ; une
   nouvelle étape crée ou reprend une sous-tâche sans changer de tâche ; un nouvel objectif seulement quand le sujet
   change vraiment. Un plugin plus ancien, qui n'envoie que `name`, garde son comportement.

## Données

- Migration `0021_subtasks.sql` : `tasks.parent_id uuid null references public.tasks(id)` ; trigger : le parent
  appartient au même projet et au même workspace, n'a pas lui-même de parent, et une tâche qui a des sous-tâches
  ne peut pas en devenir une ; la suppression douce d'une tâche s'étend à ses sous-tâches. Index `(parent_id)`.
  RLS inchangée ; `can_create_task` vaut pour les sous-tâches.
- Règle des trois endroits : `schema.dart` (`Column.text('parent_id')`), Drift (`TextColumn get parentId`,
  nullable), `make app-gen`. `workspace_core` envoie déjà `tasks` en entier.
- `CatalogController` : `subtasksOf(taskId)`, `taskPath(taskId)` (« Tâche › Sous-tâche »), `rootTaskOf(taskId)`.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Données | Migration 0021 et trigger, schéma client, catalogue ; tests d'intégration (règles du trigger, RLS, suppression) | fait |
| 2 Saisie | Sélecteur de projet sur trois niveaux (recherche, ↳ « Ajouter une sous-tâche ») ; libellés « Projet : Tâche › Sous-tâche » ; pastilles des sous-tâches sous la tâche choisie (saisie, feuille « + ») ; page Projets : sous-tâches, ajout ; saisie express (recherche dans les sous-tâches) | fait (pas de déplacement d'une tâche sous une autre dans l'app) |
| 3 Rapports et factures | « Grouper par tâche » (cumul, dépliable), rapport détaillé « Tâche › Sous-tâche » ; exports Flask : colonne « Sous-tâche » (OpenAPI) ; assistant : par tâche, sous-tâches comprises ; facture détaillée par tâche : une ligne par sous-tâche, libellée « Tâche › Sous-tâche » | fait (sans filtre par tâche, qui n'existe pas encore ; sans budget par tâche) |
| 4 Claude | Outil `set_current_task(name, step)` et consigne ; hook : l'étape relayée (`session_task {task_name, step_name}`, liste blanche D6) ; serveur : objectif → tâche, étape → sous-tâche, entrées coupées par étape, `agent_tasks` pour les deux ; tests du plugin et d'intégration ; plugin à mettre à jour sur les postes | fait |
| 5 Historique | Regroupement des tâches déjà créées par Claude sous leur objectif : liste proposée à Yannick, puis appliquée (script SQL ponctuel, sauvegarde avant) | fait (28 tâches de Clockifai rangées sous 8 objectifs, entrées marquées comme choix humain) |
| 6 Documentation | Guide (membre, manager), `docs/architecture/donnees.md`, `openapi.yaml`, plan 10 (D18, objectif et étape), CHANGELOG | fait |

Ordre : 1, 2 et 4 d'abord (la saisie et Claude), puis 3 et 5.
