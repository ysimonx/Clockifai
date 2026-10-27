# Plan 15 — Ce qui manque par rapport à Clockify

> Statut : **envisagé** (27 octobre 2026) : inventaire et ordre proposé, rien n'est décidé (§6).
>
> Objectif : faire de Clockifai une vraie alternative pour une équipe qui quitte Clockify. Lister les fonctions
> de Clockify absentes de Clockifai, les classer par intérêt et par coût, et les découper en lots.
>
> Reprend le « Reste à faire » de `01-plan-clockifai.md`. Renvoie aux plans 04 (tickets), 09 (forges git) et 10
> (suivi de Claude Code) pour ce qu'ils couvrent déjà.

## 1. Constat

**Déjà couvert** (plan 01, lots 0 à 4c ; plans 03, 05, 08, 12, 13, 14) : chronomètre, plusieurs en parallèle ;
saisie a posteriori, feuille de temps, calendrier ; projets, clients, tâches, tags, budgets et estimations
saisis ; rapports résumé et détaillé hors ligne, exports CSV / XLSX / PDF ; équipe, rôles, chefs d'équipe,
invitations ; verrouillage, approbation des feuilles de temps ; kiosque à PIN ; absences et jours fériés ;
planning ; factures PDF ; arrondi (rapports et factures), projet et description obligatoires, arrêt automatique
des chronomètres.
Clockifai a en plus ce que Clockify n'a pas : le hors connexion, les agents Claude, le journal du jour et
l'assistant.

**Côté Clockify** : d'après son offre publique connue en octobre 2026, toutes formules confondues. À relire sur
clockify.me avant de valider un lot.

| Écart | Clockify | Clockifai aujourd'hui | Où |
|---|---|---|---|
| Import | CSV d'entrées, de clients, de projets, de tâches, de tags | Rien | — |
| Rappels par email | Saisie, soumission, approbation ; verrouillage automatique | Relances manuelles dans l'app (`reminders`). `mailer.py` envoie déjà les invitations. Jobs existants : arrêt automatique, purges, clôture des entrées d'agent | `0019_reminders.sql`, `services/app/services/mailer.py`, `services/app/jobs/` |
| Fuseau horaire | Réglage du profil | `profiles.timezone` (Europe/Paris), lu par Flask (`activity`, `assistant`, exports depuis le plan 17 : `profiles.user_tz`) et le récapitulatif du jour, sans écran pour le changer | `0001_core.sql`, `features/today/day_recap.dart` |
| Connexion Google / Microsoft | Oui | Prête côté GoTrue (`GOOGLE_*`, `AZURE_*` commentés dans `deploy/.env.example`), rien dans l'app | `deploy/.env.example`, `supabase/docker/docker-compose.yml` |
| Coût et marge | Taux de coût par membre ; coût de main-d'œuvre et profit dans les rapports | `workspace_members.cost_rate_cents` se saisit dans Équipe, mais rien ne le lit. Seul le coût IA est calculé | `features/team/team_page.dart`, `features/reports/report_model.dart` |
| Confidentialité des taux | Taux et coûts montrés seulement aux rôles qui y ont droit | `workspace_members` est lisible par tout membre (`members_select` : `is_member`) et part en entier dans `workspace_core` : **chacun reçoit le taux et le coût horaires des autres** | `0003_rls.sql`, `powersync/sync-config.yaml` |
| Taux par tâche, assignation | Oui | Taux du projet, sinon du membre (plan 12, D1), posé par le serveur hors managers (`time_entries_rate`, 0023, plan 17) ; assignation : plan 04, lot S | `12-taux-et-factures-par-tache.md`, `04-tickets.md` |
| Rapports | Lien public, envoi planifié par email, présence (arrivée, départ, heures sup), alertes de budget et d'estimation | Rien de tout cela | `features/reports/`, `projects.budget_*`, `tasks.estimate_seconds` |
| Dépenses | Par projet, catégories, justificatifs, approbation, facturation | Rien | — |
| Factures | Envoi par email, paiements partiels, dépenses facturées | PDF (`GET /api/invoices/<id>/pdf`), statuts `draft` / `sent` / `paid` / `void`, taxe, remise, durées arrondies au pas du workspace (plan 17) ; pas d'email sur `clients` | `0007_modules.sql`, `routes/invoices.py` |
| Pauses | Entrée de type « pause », bouton au kiosque | Pause déjeuner de la journée type seulement | `0017_profile_day.sql`, `features/kiosk/` |
| Planning | Jalons, capacité, publication avec notification | Affectations : personne, projet, dates, heures par jour | `schedule_assignments` (0007), `features/schedule/` |
| API et webhooks | API REST publique par clé, webhooks | PostgREST avec le JWT de l'app ; jetons `clk_…` réservés aux hooks et au MCP de Claude Code ; pas de webhooks | `routes/tokens.py`, `auth.py` |
| Champs personnalisés, modèles de projet, favoris | Oui | Non. « Comme hier », la semaine pré-remplie et « Dupliquer vers… » couvrent une partie des favoris | `13-ux-moderne.md` |
| Intégrations | Extension navigateur (bouton dans Jira, Trello, GitHub…), agendas Google / Outlook | Claude Code ; agenda iCal lu dans le journal du jour (`traces`) ; forges git au plan 09 | `routes/traces.py`, `09-forges-git.md` |
| Suivi automatique | Applications et sites, inactivité, Pomodoro, captures d'écran, GPS | Présence chantier, position gardée sur le téléphone ; activité personnelle en attente (plan 10, lot 2) | `features/presence/`, `10-suivi-claude-code.md` |
| Sécurité | Double authentification, SSO SAML, journal d'audit | `created_by` / `updated_by` posés par trigger sur les entrées, rien d'autre | `0009_team_managers.sql` |

## 2. Principes

- **P1. Ce qui sert une équipe qui migre**, pas la parité pour elle-même. L'import passe donc en premier.
- **P2. La position et l'activité ne quittent pas le poste.** Captures d'écran, GPS envoyé au serveur et suivi
  des applications sont écartés, comme pour la présence chantier (plan 13, lot 13) et la liste blanche du
  plan 10 (D6).
- **P3. Où se fait le travail** : règles critiques dans des triggers ; gros volumes (import) et emails dans
  Flask ; le reste par la base locale, comme d'habitude.
- **P4. Règles du dépôt** pour toute table nouvelle : `workspace_id`, soft delete, RLS avec les helpers, trois
  endroits alignés (migration, `schema.dart`, `database.dart`), flux PowerSync.

## 3. Lots proposés

Dans l'ordre recommandé.

| Lot | Contenu | Taille | État |
|---|---|---|---|
| 1 Import depuis Clockify | CSV du rapport détaillé : aperçu, puis import rejouable (§4.1) | M | envisagé |
| 2 Fuseau horaire et rappels | Écran du fuseau ; rappels de saisie, de soumission, d'approbation ; verrouillage automatique (§4.2) | M | envisagé |
| 3 Connexion Google et Microsoft | GoTrue, boutons de connexion, règle 4.8 de l'App Store (§4.3) | S | envisagé |
| 4 Coût, marge, confidentialité des taux | Taux hors de `workspace_members`, coût daté, colonnes Coût et Marge, taux par tâche (§4.4) | M | envisagé |
| 5 Factures : envoi et paiements | Email du client, envoi du PDF, paiements partiels, impayés (§4.5) | S/M | envisagé |
| 6 Rapports | Lien public, envoi planifié, présence, alertes de budget (§4.6) | M/L | envisagé |
| 7 Dépenses | Catégories, dépenses, justificatifs, approbation, facturation (§4.7) | L | envisagé |
| 8 API publique et webhooks | Échange de jeton vers PostgREST, webhooks signés (§4.8) | M/L | envisagé |
| 9 Pauses et planning | Entrées de pause ; jalons, capacité, publication (§4.9) | M | envisagé |
| 10 Sécurité | Double authentification, journal d'audit ; SSO SAML sur demande (§4.10) | M | envisagé |

## 4. Contenu des lots

### 4.1 Import depuis Clockify

- **Source** : l'export CSV du rapport détaillé de Clockify, une ligne par entrée (projet, client, description,
  tâche, utilisateur, email, tags, facturable, début, fin, durée, taux, montant). Les intitulés exacts sont à
  relever sur un export réel : ils changent avec la langue et la devise.
- **Dans Flask, pas dans l'app** : des milliers de lignes, des entrées d'autres personnes (que la RLS refuserait
  à un client), une seule transaction. `POST /api/imports/clockify` (multipart, admin du workspace), en deux
  temps :
  - `dry_run=true` renvoie un bilan : clients, projets, tâches et tags à créer ; personnes reconnues ou non ;
    entrées ; doublons ; lignes rejetées, avec leur raison ;
  - sans `dry_run`, l'import lui-même.
- **Correspondance par nom**, sans tenir compte de la casse : client, projet dans son client, tâche dans son
  projet, tag. Ce qui manque est créé. Les personnes sont reconnues par leur email parmi les membres (Q1 pour
  les autres).
- **Dates** : le CSV donne l'heure locale du compte qui a exporté, sans fuseau. L'import demande ce fuseau (par
  défaut, celui du profil) et écrit en UTC. Format de date et 12 h / 24 h détectés, à vérifier sur l'aperçu.
- **Taux** : celui du CSV devient le `hourly_rate_cents` de l'entrée, comme un instantané (plan 12). L'import écrit
  avec `bypass_guard` : `time_entries_rate` (0023) ne le remplace pas.
- **Rejouable** : l'empreinte de chaque ligne (personne, début, fin, projet, description) est gardée dans
  `clockifai_private.import_rows` ; réimporter le même fichier ne crée rien. Les entrées importées passent la
  garde (`bypass_guard`), même antérieures à `lock_entries_before`.
- Les données redescendent par la réplication, comme toute écriture du serveur.
- **Écran** : Paramètres du workspace → « Importer depuis Clockify » (fichier, fuseau, aperçu, Importer).
- **Tests** : bilan d'un fichier type, création du référentiel, fuseau, réimport sans doublon, entrées
  verrouillées, refus pour un non-admin.

### 4.2 Fuseau horaire et rappels par email

- **Fuseau** : choix dans les Paramètres du profil, proposé d'après l'appareil à la première ouverture.
  C'est un prérequis : un rappel « à 17 h » se calcule dans le fuseau de chacun. Recopié dans le profil des
  agents (plan 10).
- **Jobs Flask** (APScheduler, toutes les 15 minutes, chacun à son heure locale) :
  - rappel de saisie : un jour ouvré sans temps, ou sous un seuil, à l'heure de fin de journée
    (`profiles.day_end`, sinon réglage du workspace). Absences et jours fériés exclus ;
  - rappel de soumission : semaine passée non soumise, le lundi matin. Il crée aussi la ligne `reminders`,
    donc le bandeau de l'app, comme une relance manuelle ;
  - rappel d'approbation : aux approbateurs (managers, chefs d'équipe selon `manages()`), pour les feuilles en
    attente depuis N jours ;
  - verrouillage automatique : un réglage du workspace (`off`, chaque semaine, chaque mois, après N jours)
    avance `lock_entries_before`.
- **Réglages** : par workspace (rappels actifs, seuils), désinscription personnelle dans `profiles`. Journal des
  envois `clockifai_private.mail_log`, pour ne jamais envoyer deux fois le même rappel.
- Sans SMTP, rien ne part et l'app garde ses bandeaux. En production, il faut configurer le SMTP
  (`docs/exploitation.md`).
- **Tests** : heure locale et changement d'heure, jours fériés et absences, pas de doublon, désinscription,
  avancée du verrouillage.

### 4.3 Connexion Google et Microsoft

- `supabase/docker/` ne se modifie pas : les variables `GOTRUE_EXTERNAL_GOOGLE_*` et `GOTRUE_EXTERNAL_AZURE_*`
  du service `auth` passent par un fichier de surcharge dans `deploy/`, inclus avec la pile Supabase (`include`
  accepte une liste de fichiers à fusionner ; à vérifier sur la version de Compose demandée).
- App : boutons sur l'écran de connexion (`signInWithOAuth`), retour par le lien existant
  `clockifai://login-callback` (iOS, Android, macOS) et `/auth/callback` (web). Un compte existant est rattaché
  par son email confirmé.
- **App Store, règle 4.8** : vérifier si proposer Google oblige à proposer aussi « Se connecter avec Apple ».

### 4.4 Coût, marge et confidentialité des taux

- **D'abord la confidentialité.** Les taux sortent de `workspace_members` et vont dans une table
  `member_rates`. Lecture : chacun le sien, les managers tous, les chefs d'équipe selon Q3. Synchronisation :
  la sienne dans `my_profile`, les autres dans `team_data` et `managed_team`. Depuis le plan 17 (0023), le
  serveur pose le taux des entrées hors managers : un membre n'a plus besoin d'aucun taux pour saisir, seulement
  du sien pour afficher ses montants.
- **Transition** : les versions de l'app déjà installées (TestFlight, Google Play) lisent
  `workspace_members.hourly_rate_cents`. On garde ces colonnes le temps d'une version, puis on les vide.
- **Coût daté** plutôt qu'un instantané par entrée (Q4) : `member_rates` porte un `valid_from`. Le coût d'une
  entrée se calcule à la lecture, d'après sa date, pour ceux qui ont le droit de le voir. Rien n'est recopié
  dans `time_entries`, et un nouveau coût ne réécrit pas le passé.
- **Rapports et exports** (Flask) : colonnes Coût et Marge (montant facturable − coût de main-d'œuvre − coût IA
  estimé), pour les managers seulement.
- **Taux par tâche** : `tasks.hourly_rate_cents`. La chaîne devient tâche, puis projet, puis membre (plan 12, D1
  étendu), avec la même proposition d'appliquer le nouveau taux aux entrées non facturées (D2). La chaîne est
  calculée à trois endroits, à changer ensemble : `time_entries_rate` (trigger, 0023), `entry_defaults.py` (agents)
  et `CatalogController.rateFor` (app).
- **Tests** : un membre ne reçoit ni ne lit le taux d'un autre (RLS et flux), coût à cheval sur deux taux,
  marge, chaîne de taux.

### 4.5 Factures : envoi et paiements

- `clients.billing_email` ; `POST /api/invoices/<id>/send` envoie le PDF en pièce jointe (`send_mail` apprend
  les pièces jointes) et passe la facture à `sent`.
- `invoice_payments` (date, montant, note) ; un trigger tient le solde et passe la facture à `paid` quand elle
  est réglée en entier. Liste des impayés (échéance dépassée) dans Factures.

### 4.6 Rapports

- **Lien public** en lecture seule : un filtre enregistré et un jeton (`clockifai_private.shared_reports`). Flask
  rend une page HTML, sans l'app. Révocable.
- **Envoi planifié** : le même filtre, en PDF par email, chaque semaine ou chaque mois.
- **Présence** : par personne et par jour, première arrivée, dernier départ, temps saisi, trous, écart avec la
  journée type (`profiles.day_*`), donc heures sup. Calculé dans l'app, comme les autres rapports.
- **Alertes de budget** : job quotidien sur les projets et les tâches à 80 % et 100 % de leur budget (heures ou
  montant) ou de leur estimation. Email et bandeau aux managers, une seule fois par seuil.
- Découpable : présence et alertes d'abord, lien public et envoi planifié ensuite.

### 4.7 Dépenses

- `expense_categories` : nom, prix unitaire facultatif (par exemple « km » à 0,60 €). `expenses` : personne,
  projet, catégorie, date, quantité ou montant, facturable, note, justificatif, `locked`, `invoice_id`.
- Droits comme `time_entries` : soi, chef d'équipe selon `can_edit_others_time()`, managers. Flux :
  `my_time_entries`, `managed_team`, `team_data`.
- **Justificatifs** : premier usage de Supabase Storage. Une photo prise hors connexion demande une file d'envoi
  des pièces jointes (Q5).
- **Approbation** avec la feuille de temps de la semaine, comme Clockify : la soumission approuvée verrouille
  aussi les dépenses de la période (`timesheet_submissions_apply`).
- **Factures** : lignes de dépenses facturables et pas encore facturées. Rapports et exports : un onglet
  Dépenses.

### 4.8 API publique et webhooks

- **Échange de jeton** : `POST /api/tokens/exchange` donne, contre un jeton `clk_…`, un JWT Supabase de courte
  durée (rôle `authenticated`, `sub` = la personne). PostgREST devient l'API publique : la RLS reste la barrière
  et il n'y a rien à recopier. Des jetons en lecture seule demanderaient un claim lu par les politiques ou un
  rôle Postgres dédié : à étudier.
- **Webhooks** : table `webhooks` (URL, événements, secret) et outbox `clockifai_private.webhook_outbox`,
  remplie par trigger (entrée créée, modifiée ou supprimée ; feuille soumise ou approuvée ; facture émise).
  Un job Flask envoie, signe en HMAC, réessaie avec un délai croissant et désactive le webhook après N échecs.
- Prérequis d'une éventuelle extension navigateur (§5).

### 4.9 Pauses et planning

- **Pauses** : `time_entries.entry_type` (`work` / `break`), à distinguer de `source` (plan 10). Bouton « Pause »
  au kiosque et dans le chronomètre. Une pause n'est jamais facturable ni comptée dans le temps de travail ; le
  rapport de présence (§4.6) s'en sert.
- **Planning** : jalons par projet (`project_milestones`), capacité (heures planifiées par jour face à la journée
  type), brouillon puis publication avec notification (bandeau, et email si le lot 2 est livré).

### 4.10 Sécurité

- **Double authentification** : le TOTP de GoTrue. Activation dans les Paramètres, code demandé à la connexion.
  Un admin peut l'exiger pour le workspace, et la RLS vérifie alors `aal2` dans le JWT : c'est elle la barrière,
  pas l'écran.
- **Journal d'audit** : trigger générique sur les tables métier vers `clockifai_private.audit_log` (qui, quand,
  table, ligne, avant et après), consultable par les admins via Flask, purgé après N mois.
- **SSO SAML** : GoTrue le propose, à vérifier sur la version épinglée. Seulement si une équipe le demande.

## 5. Écarté ou renvoyé ailleurs

- Captures d'écran, GPS envoyé au serveur, suivi des applications et des sites : contraires à P2.
- Détection d'inactivité, Pomodoro : relèvent du plan 10, lot 2 (en attente).
- Extension navigateur pour Jira, Trello… : à reconsidérer après l'API (lot 8), qui en est le prérequis. Les
  forges git sont au plan 09.
- Envoi vers Google ou Outlook Agenda : la lecture iCal du journal du jour suffit pour l'instant.
- Champs personnalisés : coûteux (schéma PowerSync fixe, donc une colonne JSON en texte, et des filtres de
  rapport) pour un usage incertain.
- Modèles de projet et entrées favorites : petits, à faire au fil de l'eau si quelqu'un les demande.
- Assignation des tâches : plan 04, lot S.

## 6. Questions ouvertes

- **Q1.** Import : que faire d'une personne du CSV inconnue du workspace ? L'inviter, rattacher ses entrées à un
  membre choisi, ou rejeter ses lignes ?
- **Q2.** Import : le CSV seul, ou aussi l'API de Clockify (clé `X-Api-Key`), qui donne en plus les membres, les
  groupes, les taux et les absences ?
- **Q3.** Les chefs d'équipe voient-ils les taux et les coûts de leur équipe ? Un membre voit-il son propre coût ?
- **Q4.** Coût daté (`valid_from`) ou instantané par entrée, comme le taux facturable ?
- **Q5.** Dépenses : justificatifs hors connexion dès le lot 7, ou en ligne seulement au début ?
- **Q6.** Faut-il avancer la double authentification (lot 10) puisque la production est exposée sur Internet ?
  Et la confidentialité des taux (début du lot 4), qui touche des données déjà en place ?

## 7. Décisions

- 27 octobre 2026 : inventaire et ordre proposé. Rien n'est validé.
- 27 octobre 2026 : constat mis à jour après la revue du code (plan 17) : taux des entrées posé par le serveur,
  arrondi des factures, fuseau du profil dans les exports.
