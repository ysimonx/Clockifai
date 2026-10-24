# API de Clockifai

Clockifai expose deux API, toutes deux authentifiées par le **JWT de la session Supabase** :

| API | Où | Pour quoi | Description |
|---|---|---|---|
| Données | `https://<SUPABASE_DOMAIN>/rest/v1/` (Kong → PostgREST) | Écritures de la file d'envoi PowerSync, RPC | Générée par PostgREST (voir plus bas) |
| Services | `https://<APP_DOMAIN>/api/` (Caddy → Flask) | Exports, factures PDF, invitations, kiosque, tâches planifiées | [`openapi.yaml`](openapi.yaml) |

L'app **ne lit jamais les données par une API** : elle lit sa base locale, que PowerSync
(`https://<SYNC_DOMAIN>`) alimente selon les Sync Streams de `powersync/sync-config.yaml`. Les écritures
locales remontent par PostgREST ([écriture hors ligne](sequences/ecriture-hors-ligne.md)).

## Authentification

- **Utilisateur** : `Authorization: Bearer <access_token>` émis par GoTrue (`/auth/v1/`). Le même jeton sert
  pour PostgREST (avec l'en-tête `apikey` = clé anon, ajouté par le SDK Supabase), pour PowerSync et pour Flask.
  Flask vérifie la signature (`SUPABASE_JWT_SECRET`, ou le JWKS de GoTrue s'il est vide), `exp`, `sub` et
  `aud = authenticated`, puis l'appartenance active au workspace et le rôle (`services/app/auth.py`).
- **Kiosque** : `X-Kiosk-Token: kio_…`, jeton d'appareil créé par un admin ; la tablette n'a pas de compte.
- **Jeton personnel** : `Authorization: Bearer clk_…`, créé par un membre pour un poste ; utilisé par les hooks
  Claude Code, l'extension VSCode et le MCP (`/api/activity/*`).
- **Rôle service** : la clé `SERVICE_ROLE_KEY` sert à Flask pour l'API admin de GoTrue (invitations). Elle ne
  doit jamais quitter le serveur.

## Conventions

- **`workspace_id`** : obligatoire sur toutes les routes Flask liées à un workspace, en paramètre de requête
  (ou dans le corps JSON pour un `POST`). Flask se connecte à Postgres hors RLS : ce contrôle est la barrière.
- **Erreurs Flask** : `{"error": "<message>"}` avec 400, 401, 403, 404, 429 ou 502. Messages en anglais, pour le
  journal ; l'app affiche son propre texte quand elle connaît le cas (jeton de kiosque invalide…). Une erreur
  500 renvoie la page HTML par défaut de Flask.
- **Erreurs PostgREST** : codes Postgres. Le connecteur PowerSync abandonne l'opération sur `22xxx`
  (donnée invalide), `23xxx` (contrainte) et `42501` (RLS ou garde d'un trigger), affiche le refus et laisse
  la synchronisation suivante rétablir l'état du serveur ; il réessaie sur toute autre erreur.
- **Dates** : instants en UTC (ISO 8601) ; jours sans heure (`period_start`, `start_date`…) en `yyyy-MM-dd`.
  Les dates « du jour » d'un utilisateur se calculent dans son fuseau (`profiles.timezone`, Europe/Paris par
  défaut, `user_local_date()`).
- **Suppressions** : soft delete (`deleted_at`) ; une ligne supprimée sort des flux de synchronisation. Une
  tâche planifiée la supprime physiquement après `JOB_PURGE_DELETED_AFTER_DAYS` jours (30 par défaut ; entrées,
  tâches, projets, clients, tags, adhésions, workspaces).
- **CORS** : en production l'app web et `/api` partagent l'origine (Caddy), CORS est inutile. En développement
  (app sur :3000, Flask sur :5050), Flask autorise les origines de `CORS_ORIGINS`.

## Données : PostgREST

La description des tables et des fonctions exposées est générée par PostgREST (Swagger 2.0) :
`GET https://<SUPABASE_DOMAIN>/rest/v1/` avec `apikey: <SERVICE_ROLE_KEY>` (Kong réserve cette route au rôle
admin), ou l'onglet API Docs de Supabase Studio. Elle n'est pas recopiée ici ; le schéma et les droits sont
résumés dans `docs/architecture/donnees.md`.

### RPC appelées par l'app

| Fonction | Appelée depuis | Effet |
|---|---|---|
| `set_kiosk_pin(p_workspace_id uuid, p_pin text)` | Paramètres, PIN du kiosque | Enregistre le PIN (4 à 8 chiffres, sinon `22023`) haché en bcrypt dans `clockifai_private.member_pins` ; membre du workspace seulement (`42501`). |

Les fonctions de droits (`is_member`, `is_manager`, `is_admin`, `manages`, `can_edit_others_time`,
`can_decide_time_off`, `can_create_task`) et `has_kiosk_pin` sont exécutables par un utilisateur connecté,
mais l'app ne les appelle pas : elles servent aux politiques RLS et aux triggers. `TeamRights`
(`app/lib/core/team_rights.dart`) reproduit leurs règles pour l'affichage.

### Règles imposées par la base

Ce que l'app doit savoir parce que le serveur peut modifier ou refuser ce qu'elle envoie :

| Table | Trigger | Règle |
|---|---|---|
| `auth.users` | `on_auth_user_created` → `handle_new_user` | Crée le profil et un workspace « Espace de … » ; `workspaces_after_insert` en fait l'auteur owner. |
| `profiles` | `profiles_after_update` | Recopie nom affiché et email dans ses adhésions. |
| `time_entries` | `time_entries_a_running_limit` | Limite de chronomètres simultanés (`workspaces.max_running_timers`, 0 = illimité) : les plus anciens sont arrêtés ; un chronomètre plus ancien arrivé en retard est enregistré déjà terminé. |
| `time_entries` | `time_entries_before_write` | Calcule `duration_seconds` et `updated_at` ; `created_by` et `updated_by` viennent du JWT, jamais du client. |
| `time_entries` | `time_entries_guard` | Refuse (`42501`) : chronomètre démarré pour quelqu'un d'autre (`timer_for_others`, admins compris) ; hors admin, entrée verrouillée (`locked_entry`), verrouillage par un non-admin, période antérieure à `lock_entries_before` (`locked_period`), période approuvée (`approved_period`), entrée facturée (`invoiced_entry`). |
| `workspace_members` | `workspace_members_guard` | Seul un admin change rôle, statut, taux ou adhésion ; le dernier owner ne peut pas être rétrogradé (`23514`). |
| `tasks` | `tasks_guard` + RLS `can_create_task` | Hors manager+ : création d'une tâche active sans estimation, si `workspaces.task_creation = everyone`, puis renommage seulement. |
| `timesheet_submissions` | `timesheet_submissions_guard` | Une soumission commence en `submitted` ; seul manager+ ou le chef d'équipe de la personne approuve, refuse ou rouvre ; période et propriétaire immuables ; `decided_by` et `decided_at` posés. |
| `timesheet_submissions` | `timesheet_submissions_apply` | Approuver verrouille les entrées de la période, rouvrir les déverrouille (contourne la garde par `clockifai.bypass_guard`). |
| `time_off_requests` | `time_off_requests_guard` | Une demande commence en `pending`, ou passe directement en `approved` si la politique n'exige pas d'approbation ; décision par `can_decide_time_off()`. |
| `invoices`, `invoice_items` | `invoices_before_write`, `invoice_items_before_write`, `invoice_items_after_write` | Numéro `PRÉFIXE-année-0001`, échéance, montants, sous-total, remise, TVA et total calculés par la base. |
| `team_manager_assignments`, `user_group_members`, `user_groups`, `workspace_members` | `refresh_team_scope` | Recalcule `team_scope`, le périmètre des chefs d'équipe. |

Les écritures client passent par **upsert** : la politique SELECT doit accepter la nouvelle ligne
(migration 0005).

## Parcours (diagrammes de séquence)

| Parcours | Fichier |
|---|---|
| Connexion, inscription, choix du workspace | [connexion.md](sequences/connexion.md) |
| Écriture hors ligne, envoi, réplication | [ecriture-hors-ligne.md](sequences/ecriture-hors-ligne.md) |
| Chronomètres simultanés | [chronometres.md](sequences/chronometres.md) |
| Soumission et approbation d'une feuille de temps | [feuille-de-temps.md](sequences/feuille-de-temps.md) |
| Demande et décision d'absence | [absences.md](sequences/absences.md) |
| Invitation (avec ou sans SMTP) | [invitation.md](sequences/invitation.md) |
| Kiosque : appareil, PIN, pointage | [kiosque.md](sequences/kiosque.md) |
| Export d'un rapport | [export.md](sequences/export.md) |
| Facture et PDF | [facture-pdf.md](sequences/facture-pdf.md) |
| Barre de menus macOS | [barre-de-menus-macos.md](sequences/barre-de-menus-macos.md) |
| Suivi de Claude Code : jeton, hooks, entrées de l'agent | [claude-code.md](sequences/claude-code.md) |
| Fidwork (prévu, non implémenté) | [fidwork.md](sequences/fidwork.md) |

## Tenir à jour

`services/tests/test_openapi.py` (lancé par `make services-test`) échoue dès qu'une route Flask manque dans
`openapi.yaml` ou qu'une route documentée n'existe plus. Le contenu (paramètres, réponses) et les séquences se
relisent à la main avec le code, dans le même commit.
