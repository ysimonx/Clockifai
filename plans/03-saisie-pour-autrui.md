# Saisie du temps pour autrui (chef d'équipe) — plan

> Objectif : qu'un **chef d'équipe** puisse saisir, corriger et pointer le temps des
> collaborateurs qu'il encadre, comme le « Team Manager » de Clockify, avec en plus un
> **pointage d'équipe** (cocher les présents → une entrée par personne) pour les chantiers.

## 1. Référence Clockify

| Clockify | Comportement |
|---|---|
| Rôle **Team Manager** | Attribué par un admin depuis la page Équipe, sur des **utilisateurs ou des groupes** ; ne voit que son équipe |
| Paramètre du workspace *Who can edit time and expenses for others* | `Admins` ou `Admins and team managers` ; sans lui, le Team Manager voit et approuve, mais ne modifie pas |
| Points d'entrée | Feuille de temps et calendrier (sélecteur **Teammates**), rapport détaillé (bouton **Add time for others**) |
| Limites | Entrée approuvée verrouillée pour tous ; le Project Manager ne saisit pas pour autrui ; pas de chronomètre pour un autre |
| Approbations | Le Team Manager approuve les feuilles de son équipe |

Sources : [Add time for others](https://clockify.me/help/track-time-and-expenses/add-time-for-others),
[Managers](https://clockify.me/help/administration/user-roles-and-permissions/manager-role),
[I can't edit team member's time](https://clockify.me/help/troubleshooting/optimize-tracking/cant-edit-team-time).

## 2. Constat dans Clockifai (octobre 2026)

| Sujet | État | Où |
|---|---|---|
| Rôles | `owner`, `admin`, `manager`, `member` ; `manager` voit **tout** le workspace | `0001_core.sql` (`workspace_members.role`), `session.dart` (`isManager`) |
| Groupes / équipes | Aucun | — |
| Droits d'écriture sur `time_entries` | Soi-même, ou **admin** pour tout le monde | `0003_rls.sql` (`time_entries_insert/update/delete`, `time_entry_tags_write`) |
| Garde serveur | Verrou, période verrouillée, période approuvée **de la personne visée**, entrée facturée ; admins exemptés | `0007_modules.sql` (`time_entries_guard`) |
| Auteur de la saisie | Non tracé (pas de `created_by`) | `time_entries` |
| Sync des entrées d'autrui | Flux `team_data`, tout le workspace, réservé à `role != 'member'` | `powersync/sync-config.yaml` |
| UI | Création toujours pour soi ; un admin peut modifier ou dupliquer l'entrée existante d'un autre | `entry_dialog.dart` (`_save`), `timesheet_page.dart`, `calendar_page.dart` |
| Rejet serveur | Codes `23xxx` / `42501` abandonnés et remontés via `onRejected` | `connector.dart` |

## 3. Décisions de conception

**D1. « Chef d'équipe » est un périmètre, pas un nouveau rôle** *(validé)*. N'importe quel membre (y compris `member`)
peut être chef d'équipe d'utilisateurs ou de groupes. Le rôle `manager` actuel garde sa portée
« tout le workspace » (il équivaut à un chef d'équipe de tout le monde). Aucun comportement
existant ne change pour les comptes en place.

**D2. Groupes d'utilisateurs.** Tables `user_groups` et `user_group_members`. Ils servent aussi aux
filtres de rapport et à la correspondance « entreprise » du plan Fidwork (§3 de `02-integration-fidwork.md`).

**D3. Périmètre matérialisé `team_scope`.** Une ligne `(workspace_id, manager_id, user_id)` par
collaborateur encadré, recalculée par trigger à partir des affectations directes et des groupes.
Raisons :
- la RLS fait une simple recherche indexée ;
- les Sync Streams n'acceptent qu'une sous-requête simple (`user_id IN (SELECT user_id FROM team_scope WHERE manager_id = auth.user_id())`) ;
- l'app s'en sert telle quelle pour remplir le sélecteur de collaborateurs.

Recalcul **différentiel** (supprimer les lignes en trop, insérer les manquantes) pour ne pas changer
les `id` et éviter de resynchroniser toute la table à chaque modification de groupe.

**D4. Paramètre du workspace `time_for_others`** : `'admins'` (défaut, comme Clockify) ou
`'admins_and_team_managers'`. La lecture du temps de l'équipe ne dépend pas du paramètre,
seule l'écriture en dépend *(validé)*.

**D5. Pas de chronomètre pour autrui.** Une entrée dont `user_id <> auth.uid()` doit avoir `end_at`
renseigné, contrôlé dans la garde **avant** l'exemption admin. Le kiosque et l'intégration Fidwork
passent par la connexion de service (`auth.uid()` nul) et ne sont pas concernés.

**D6. Traçabilité.** Colonnes `created_by` et `updated_by` sur `time_entries`, posées par trigger
depuis `auth.uid()` (la valeur envoyée par le client est ignorée ; `created_by` est conservé sur
`UPDATE`, ce qui couvre l'upsert du connecteur). Pas de rétro-remplissage : `NULL` = saisi par la
personne elle-même (évite de resynchroniser toutes les entrées).

**D7. Règles existantes inchangées.** Verrou, période verrouillée, période approuvée de la personne
visée, entrée facturée, `require_project` / `require_description`, taux = `rateFor(projet, personne visée)`.
Le collaborateur garde la main sur une entrée saisie par son chef (c'est la sienne) *(validé)*.

## 4. Modèle de données — migration `0009_team_managers.sql`

```sql
alter table public.workspaces
  add column time_for_others text not null default 'admins'
    check (time_for_others in ('admins', 'admins_and_team_managers'));

create table public.user_groups (            -- soft delete, métier
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  created_at, updated_at, deleted_at …
);
create table public.user_group_members (     -- suppression physique, comme time_entry_tags
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null, group_id uuid not null references public.user_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at, updated_at, unique (group_id, user_id)
);
create table public.team_manager_assignments ( -- suppression physique
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null, manager_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  group_id uuid references public.user_groups(id) on delete cascade,
  created_at, updated_at,
  check (num_nonnulls(user_id, group_id) = 1)
);
create table public.team_scope (             -- dérivée, écrite uniquement par trigger
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null, manager_id uuid not null, user_id uuid not null,
  unique (workspace_id, manager_id, user_id)
);

alter table public.time_entries
  add column created_by uuid references auth.users(id) on delete set null,
  add column updated_by uuid references auth.users(id) on delete set null;
```

Fonctions (`security definer`, mêmes droits d'exécution que `is_manager`) :
- `manages(wid, uid)` : `is_admin(wid)` **ou** rôle `manager` **ou** ligne `team_scope (wid, auth.uid(), uid)`.
- `can_edit_time_of(wid, uid)` : `uid = auth.uid() and is_member(wid)`
  **ou** `is_admin(wid)`
  **ou** (`workspaces.time_for_others = 'admins_and_team_managers'` **et** `manages(wid, uid)` **et** `uid` membre actif).
- `refresh_team_scope(wid)` : recalcul différentiel, appelé par les triggers de
  `team_manager_assignments`, `user_group_members`, `user_groups` (soft delete) et `workspace_members` (désactivation, suppression).

RLS :
- `time_entries` et `time_entry_tags` : SELECT `user_id = auth.uid() or is_manager(wid) or manages(wid, user_id)` ;
  INSERT / UPDATE / DELETE `can_edit_time_of(workspace_id, user_id)` (USING sur l'ancienne ligne, WITH CHECK sur la nouvelle :
  impossible de « déplacer » une entrée vers quelqu'un hors périmètre).
- `user_groups`, `user_group_members`, `team_manager_assignments` : lecture `is_member`, écriture `is_admin`.
- `team_scope` : lecture `is_member`, aucune écriture client.
- `time_entries_guard` : ajout de la règle D5. Les autres contrôles s'appliquent déjà à la personne visée.
- `time_entries_before_write` : pose `created_by` / `updated_by` (D6).

Alignement obligatoire (CLAUDE.md) : migration, `app/lib/data/powersync/schema.dart`,
`app/lib/data/drift/database.dart` (puis `make app-gen`), `powersync/sync-config.yaml`.
La publication `powersync` couvre déjà tout le schéma `public`.

## 5. Synchronisation

- `workspace_core` : ajouter `user_groups`, `user_group_members`, `team_manager_assignments`, `team_scope`.
- Nouveau flux **`managed_team`** (auto, priorité 3) : `time_entries` et `time_entry_tags` (et `timesheet_submissions`
  au lot 5) où `user_id IN (SELECT user_id FROM team_scope WHERE manager_id = auth.user_id())`.
  Un `manager` reçoit aussi `team_data` ; les doublons sont fusionnés par `id`.
- Redémarrer PowerSync après modification (`docker compose … restart powersync`).

## 6. Application

**Session et référentiel**
- `CatalogController` : groupes, affectations, périmètre.
- `SessionController` : `managedUserIds`, `isTeamManager`, `canEditTimeOf(userId)`, qui reproduit la règle serveur.
  Ce n'est qu'un affichage : la RLS reste la barrière.

**Administration (admin)**
- Paramètres du workspace, section Permissions : « Qui peut saisir le temps des autres ».
- Page Équipe : onglet **Groupes** (création, membres) et, sur un membre, « Chef d'équipe de… » (utilisateurs ou groupes).

**Saisie**
1. Fenêtre d'entrée : champ **Collaborateur** à la création, visible si l'utilisateur peut saisir pour autrui (défaut : soi).
   Pas de bouton chronomètre quand la personne visée n'est pas soi.
2. Feuille de temps et calendrier : sélecteur **Collègues** en tête (équivalent de *Teammates*) et bandeau
   « Vous saisissez pour X ». La grille lit et écrit pour la personne choisie.
3. Liste des entrées et rapport détaillé : bouton **Ajouter du temps pour d'autres** (choix multiple, une entrée par
   personne) ; menu Modifier / Dupliquer / Supprimer conditionné à `canEditTimeOf`.
4. Ligne d'entrée : mention « saisi par X » quand `createdBy` diffère de `userId`.
5. Contrôles préalables côté client (période approuvée ou verrouillée de la personne visée) pour éviter un rejet
   silencieux hors ligne ; les rejets restants passent par `onRejected` comme aujourd'hui.

**Pointage d'équipe** (au-delà de Clockify, pour les chantiers)
- Écran dédié : date, projet / tâche, tags (phase), horaires ou durée, liste des membres du périmètre à cocher,
  ajustement individuel (arrivée ou départ différent). Crée N entrées, hors ligne compris, une transaction locale par personne (un refus du serveur n'emporte que l'entrée concernée).
- Cohérent avec la priorité à la saisie a posteriori et avec la question 4 du plan Fidwork (pointage d'équipe).

**Rapports et équipe**
- `reports_page.dart` : un chef d'équipe filtre parmi son périmètre (et lui-même), au lieu de « soi seulement ».
- Page Équipe : activité de la semaine visible pour les membres du périmètre.

Tous les libellés passent par l'ARB (FR modèle, EN).

## 7. Services Flask

- `exports.export_report` : un chef d'équipe (hors `manager` / `admin`) est limité à `team_scope` ∪ lui-même,
  via la même règle que `manages()`.

## 8. Tests

- **Intégration** (`services/tests/integration/`) :
  - matrice de droits : membre → autrui refusé ; chef avec `admins` → lecture oui, écriture non ;
    chef avec `admins_and_team_managers` → écriture dans le périmètre oui, hors périmètre non ; `manager` → tout le monde ;
  - chronomètre pour autrui refusé, y compris pour un admin ;
  - période approuvée ou facturée de la personne visée refusée ;
  - `created_by` forcé à `auth.uid()` même si le client envoie autre chose ; conservé lors de l'upsert du connecteur ;
  - `team_scope` : ajout ou retrait d'un membre de groupe, affectation, suppression de groupe, désactivation d'un membre.
- **App** (`app/test/`) : création multiple dans le dépôt des entrées, `canEditTimeOf`.
- **Parcours navigateur** : chef d'équipe hors ligne qui pointe 3 compagnons, reconnexion, vérification en base (`user_id`, `created_by`).

## 9. Lots

| Lot | Contenu | Taille |
|---|---|---|
| 1 Serveur | Migration 0009 (groupes, affectations, `team_scope`, paramètre, `created_by`, RLS, garde), flux `managed_team`, tests d'intégration | M |
| 2 Administration | Groupes, affectation des chefs d'équipe, paramètre Permissions | M |
| 3 Saisie pour autrui | Champ Collaborateur, sélecteur Collègues (feuille de temps, calendrier), « saisi par », droits des menus, rapports limités au périmètre | M |
| 4 Pointage d'équipe | Écran de saisie groupée | M |
| 5 Approbations et exports | Le chef d'équipe approuve les feuilles de son périmètre (`timesheet_submissions` : RLS, garde, flux, écran) et les absences si la politique le prévoit (`time_off_policies.approvers`) ; export Flask limité au périmètre | M |

Chaque lot se termine par un état déployable.

## 10. Décisions (11 octobre 2026)

1. **Validé** : le rôle `manager` garde la portée « tout le workspace » (D1).
2. **Validé** : paramètre `time_for_others` à `admins` par défaut, comme Clockify (D4).
3. **Validé** : le chef d'équipe approuve les feuilles de temps de son périmètre (jamais la sienne) ; chaque politique
   d'absence choisit ses approbateurs, `managers` (défaut, comportement actuel) ou `managers_and_team_managers`.
   Approbateurs nominatifs, approbation multiniveau et notifications : plus tard. Ce que fait Clockify :
   - feuilles de temps : approuvées par les admins **et** les Team Managers (pour leur équipe seulement), ou les
     Project Managers (pour leurs projets) selon le paramètre *Permissions* ; approbation multiniveau en option
     (niveau 1 : managers, niveau 2 : jusqu'à deux approbateurs désignés ; les admins peuvent passer outre) ;
   - absences : chaque politique « avec approbation » désigne ses approbateurs : *Admins*, *Team managers*
     (pour leur équipe) ou *membres précis* ;
   - notifications : envoyées au Team Manager, ou au propriétaire du workspace si personne n'encadre l'utilisateur.
   Sources : [Approve time & expenses](https://clockify.me/help/track-time-and-expenses/approval),
   [Multi-level approval](https://clockify.me/help/track-time-and-expenses/multi-level-approval),
   [Create & manage time off policy](https://clockify.me/help/track-time-and-expenses/create-manage-time-off-policy).
4. **Validé** : le collaborateur peut modifier ou supprimer une entrée saisie par son chef (D7).

## 11. État d'avancement (11 octobre 2026)

| Lot | État | Vérification |
|---|---|---|
| 1 Serveur | Fait : migration `0009_team_managers.sql`, flux `managed_team`, export Flask limité au périmètre | 12 tests d'intégration (`test_team_managers.py`), dont la suppression du compte d'un chef d'équipe |
| 2 Administration | Fait : page Équipe (onglets Membres / Groupes, « Chef d'équipe de… »), réglage « Saisie du temps pour autrui » | Tests `TeamRepository` ; parcours navigateur |
| 3 Saisie pour autrui | Fait : champ Collaborateurs (création multiple), bandeau Collaborateur (feuille de temps, calendrier), « saisi par », menus selon les droits, rapports et bouton « Ajouter du temps pour d'autres » | Tests `TeamRights` ; parcours navigateur |
| 4 Pointage d'équipe | Fait : écran `/team-entry` (présents cochés, horaires ajustables par personne) | Parcours navigateur : 2 entrées créées, `created_by` = chef en base |
| 5 Approbations | Fait : feuilles du périmètre, absences selon `approvers`, écran Approbations ouvert aux chefs d'équipe | Tests d'intégration |

Ajustements décidés pendant la réalisation :
- `workspaces.time_for_others` et `time_off_policies.approvers` : la migration « touche » les lignes existantes pour
  que PowerSync les réplique ; côté client, les colonnes Drift sont nullables (valeur par défaut appliquée par l'app).
- Flux `managed_team` en abonnement automatique, par jointure `team_scope` sur `(workspace_id, user_id)` :
  aucune entrée d'un autre workspace du collaborateur ne fuit.
- La garde refuse un chronomètre démarré pour autrui **avant** l'exemption admin ; le kiosque et les intégrations
  (`auth.uid()` nul) ne sont pas concernés et peuvent renseigner `created_by` eux-mêmes.
- Supprimer un groupe retire aussi ses membres et les affectations qui le visent (côté client, dans la même transaction).
- Contrôle préalable côté client des périodes approuvées de la personne visée (`ModulesRepository.isDayApproved`).
- Saisie groupée : une transaction locale **par personne**. Le connecteur abandonne la fin d'une transaction dès
  qu'une écriture est refusée ; une seule transaction pour N personnes aurait fait perdre les suivantes.
- `refresh_team_scope` prend un verrou consultatif par workspace : deux modifications simultanées ne laissent
  pas de ligne périmée dans `team_scope`.
- Sans JWT (cascade `on delete set null` à la suppression d'un compte, kiosque, intégrations), le trigger laisse
  `created_by` / `updated_by` tels qu'écrits : supprimer le compte d'un chef d'équipe conserve les entrées
  qu'il a saisies, avec un auteur vide (test d'intégration dédié).

Reste à faire (hors périmètre) : approbateurs nominatifs, approbation multiniveau, notifications au chef d'équipe,
rôle Project Manager.
