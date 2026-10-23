# Interfaçage Fidwork ↔ Clockifai — plan

> Statut : **en attente** (23 octobre 2026). Les autres plans ne doivent pas en dépendre : ce qu'ils
> partagent avec lui (`time_entries.source`, `external_source` / `external_id`, `identity_links`) est créé
> par le premier lot livré qui en a besoin.
>
> Objectif : que les échafaudeurs et calorifugeurs saisissent leur temps de travail
> **sur les interventions Fidwork**, que ce temps soit tenu dans Clockifai (feuilles de
> temps, rapports, approbations, export paie / facturation), et que Fidwork récupère en
> retour les heures réellement passées par intervention.

## 1. Constat de départ (état de Fidwork, octobre 2026)

| Sujet | Ce qui existe dans Fidwork | Conséquence pour l'interfaçage |
|---|---|---|
| Base | MySQL 8 managé OVH, API Flask (gunicorn :4998), pas de file de messages | Intégration **par HTTP uniquement**, jamais d'accès croisé aux bases |
| Identité | Utilisateur global (email unique), JWT maison (`sub` seul), SSO Azure côté web, magic link mobile | Rapprochement des comptes **par email** ; pas de fournisseur OIDC réutilisable |
| Métier | Pas de colonne « métier » : `échafaudeur` / `calorifugeur` sont des **rôles par site** ; entreprise = `users.company_id` | Le rôle par site décide qui est invité dans Clockifai |
| Travail | `sites → places → interventions_values` ; type (échafaudage, calorifuge, nucléaire) ; `contractor_user_id` ; statuts et transitions par type | Intervention = unité de pointage naturelle |
| Temps | **Aucune donnée de pointage individuelle.** Seulement des totaux d'équipe en texte libre dans les formulaires nucléaires (`montage_nombre_heures_effectives_montage`, `pose_nb_heuresu_effectif_equipe_total`…) | Clockifai devient la **source de vérité du temps** ; Fidwork reçoit des agrégats |
| Événements | Table `events` (géolocalisée, idempotente par `event_on_site_uuid`), file hors ligne côté app ; **l'heure client est ignorée** (seul `time_created` serveur est gardé, et l'app formate en `hh` 12 h) | À corriger avant de s'en servir pour pointer hors ligne |
| Sortie vers partenaires | Framework d'outbox `partner_calls` (retries, cron `partner-calls-run` toutes les 2 min), activable par site via `dict_of_settings` (1er partenaire : Mob2e) | **Réutilisé tel quel** pour pousser vers Clockifai |
| App mobile | Hive + fichiers JSON, file d'événements `uploadevents/`, page `InterventionPage`, page `QRCodePage` (tuiles : contrôle journalier, FEB, demande de démontage…) | Le bouton de pointage se place sur ces deux pages |

## 2. Principes

1. **Clockifai = registre du temps**, Fidwork = registre des interventions. Chacun reste maître de ses données.
2. **Le terrain n'utilise qu'une application** : les compagnons pointent depuis l'app Fidwork qu'ils ont déjà (scan du QR code de l'échafaudage ou page intervention). L'app Clockifai reste disponible pour ceux qui le souhaitent et pour l'encadrement.
3. **Couplage faible et rejouable** : flux idempotents (identifiants stables), outbox côté Fidwork, boîte de réception (inbox) côté Clockifai, réconciliation périodique.
4. **Hors ligne de bout en bout** : un pointage fait sans réseau garde son heure réelle.

## 3. Correspondance des modèles

| Fidwork | Clockifai | Règle |
|---|---|---|
| Tenant (organisation cliente de Fidwork) | **Workspace** | 1 lien de configuration par tenant (table `integration_links`) ; plusieurs tenants possibles |
| Site | **Client** | `external_id = site.id` |
| Site × type d'intervention (échafaudage, calorifuge…) | **Projet** | ex. « Site de Gravelines — Échafaudage » ; couleur par type |
| Intervention (`interventions_values`) | **Tâche** du projet | nom = n° de registre + repère (place) ; tâche « terminée » quand le statut Fidwork est final (démonté, réceptionné, annulé) → disparaît des sélecteurs |
| Phase (montage, démontage, modification, visite, pose, dépose, réception) | **Tag** | permet de remplir séparément « heures montage » et « heures démontage » |
| Utilisateur avec rôle `échafaudeur` / `calorifugeur` sur un site lié | **Membre** (rôle `member`) | rapprochement par email ; invitation automatique si absent |
| Coordinateur, chef de chantier, responsable organisation | **Manager** | liste de rôles configurable par lien |
| Entreprise (`companies`) | Groupe d'utilisateurs (filtre de rapport) | groupes du plan [03-saisie-pour-autrui.md](03-saisie-pour-autrui.md), livrés (`user_groups`) |

## 4. Architecture des flux

```
 App Fidwork (terrain)                API Fidwork (MySQL)                     Clockifai (Postgres)
 ─────────────────────                ───────────────────                     ────────────────────
 Scan QR / page intervention
   └─ événement work_start/stop ──▶  events (+ occurred_at client)
      (file hors ligne existante)       └─ partner_calls « clockifai » ──▶  POST /api/integrations/fidwork/events
                                                                              └─ inbox (idempotente) → time_entries
 Création / changement de statut
 d'intervention, rôles sur site  ──▶  partner_calls « clockifai » ───────▶  POST /api/integrations/fidwork/sync
                                                                              └─ clients / projets / tâches / membres
                                     ◀── réconciliation (pull, 1×/h) ───────  job APScheduler (compte de service Fidwork)
 Page intervention (en ligne)    ──▶  GET labour (proxy) ────────────────▶  GET /api/integrations/fidwork/interventions/<id>/labour
                                                                              (heures par phase, par personne, nb compagnons)
```

### 4.1 Référentiel : Fidwork → Clockifai (lot F1)
- **Déclencheurs** côté Fidwork : création d'intervention, changement de statut, changement de rôles sur un site, activation du lien. Ajout d'un partenaire `clockifai` dans `service_dir/partners/` qui sérialise un lot `{sites, interventions, users}` et l'empile dans `partner_calls` (l'enqueue existe déjà sur `status changed` ; à ajouter sur la création d'intervention et sur `POST/DELETE /site/<id>/user`).
- **Réception** côté Clockifai : `POST /api/integrations/fidwork/sync`, authentifié par une **clé d'intégration** propre au workspace (stockée hachée, envoyée en `Authorization: Bearer`), upsert idempotent par `(workspace_id, external_source, external_id)`.
- **Réconciliation** : un job Clockifai relit toutes les heures les interventions modifiées via l'API Fidwork existante (`GET /site/<id>/type_intervention/<t>/intervention_values?from_date=…`) avec un compte de service Fidwork, pour rattraper tout appel perdu.

### 4.2 Pointage : Fidwork → Clockifai (lot F2)
- **App Fidwork** :
  - tuile « Démarrer / arrêter mon pointage » sur `QRCodePage` (le compagnon scanne l'échafaudage en arrivant et en repartant) ;
  - bouton équivalent dans `InterventionPage`, avec choix de la phase (tag) ;
  - **pointage d'équipe** : le chef d'équipe coche les compagnons présents → un événement par personne ;
  - état « en cours » affiché localement (dernier `work_start` sans `work_stop`).
- **API Fidwork** :
  - nouvelles actions client `work_start`, `work_stop` dans `CLIENT_EVENT_ACTIONS` (`event_rules.py`) ;
  - **stocker l'heure réelle** : nouvelle colonne `events.occurred_at` (UTC) alimentée par l'app, et correction du format `hh` → `HH` dans `model_event.dart` ;
  - `process_event` empile un `partner_call` « clockifai » (même mécanisme que Mob2e).
- **Clockifai** : `POST /api/integrations/fidwork/events` écrit d'abord dans une **inbox** (`integration_inbox`, unique sur l'id d'événement Fidwork), puis :
  - `work_start` → entrée de temps en cours, id déterministe `uuid5(event_on_site_uuid)`, tâche = intervention, tag = phase, `source = 'fidwork'`, géolocalisation de début ;
  - `work_stop` → clôt l'entrée démarrée référencée (`start_event_id`) ou, à défaut, l'entrée en cours de la personne de source `fidwork` (plusieurs chronomètres peuvent tourner, migration 0011) ;
  - événements arrivés dans le désordre : traités selon `occurred_at` ; l'arbitrage du nombre de chronomètres en cours est déjà assuré par le trigger serveur (migrations 0004 puis 0011) ;
  - anomalies (arrêt sans départ, pointage > 14 h, intervention inconnue) → liste « pointages à vérifier » pour les managers.
- Les entrées apparaissent ensuite dans l'app Clockifai de chacun via PowerSync, éditables selon les règles habituelles (verrouillage, approbation).

### 4.3 Retour d'information : Clockifai → Fidwork (lot F3)
- **Consultation en ligne** : `GET /api/integrations/fidwork/interventions/<id>/labour` renvoie heures totales, heures par phase, par personne et nombre de compagnons distincts. Fidwork l'expose via un petit proxy (`GET /api/v1/intervention_values/<id>/labour`) pour ne pas diffuser la clé d'intégration aux apps.
- **Pré-remplissage des formulaires nucléaires** : bouton « Reprendre les heures pointées » à côté de `montage_nombre_heures_effectives_montage`, `demontage_nombre_heures_effectives_equipe_demontage`, `pose_nb_heuresu_effectif_equipe_total`, et des champs « nombre de personnes effectives ». Proposition seulement : le formulaire reste signé par l'utilisateur.
- **Indicateurs compliance** (optionnel) : push nocturne d'un résumé par intervention dans une table Fidwork `intervention_labour_summary` pour les tableaux de bord `app_compliance` (heures par échafaudage, par site, par entreprise).

### 4.4 Connexion unique (lot F4, optionnel)
Pour l'encadrement qui utilise aussi l'app Clockifai : bouton « Continuer avec Fidwork ».
L'app envoie son jeton Fidwork à `POST /api/integrations/fidwork/session` ; Clockifai le valide en appelant `GET /api/v1/user/me` chez Fidwork (aucun secret partagé), retrouve le compte lié par email, puis ouvre une vraie session Supabase (lien magique généré par l'API admin GoTrue et vérifié côté serveur), avec jeton de rafraîchissement.

## 5. Modifications à prévoir

### Clockifai
| Élément | Détail | Taille |
|---|---|---|
| Migration `integration_links` | workspace, source `fidwork`, `fidwork_tenant_id`, URL de l'API, hash de la clé, compte de service (Vault/env), correspondance rôles → rôles, sites activés | S |
| Colonnes de rapprochement | `external_source`, `external_id`, `external_meta jsonb` sur `clients`, `projects`, `tasks` (+ index unique) ; `identity_links(workspace_id, source, external_user_id, user_id)` | S |
| Entrées de temps | `source` (créée par le plan 10 ; valeur `fidwork` à ajouter), `external_id` unique, `start_lat/lng/accuracy`, `stop_lat/lng/accuracy` (voir §9 : pas dans `time_entries`) | S |
| Inbox | `integration_inbox(source, external_event_id unique, payload, received_at, processed_at, error)` | S |
| Flask : blueprint `integrations/fidwork` | `sync`, `events`, `labour`, `session` ; auth par clé d'intégration ; tests d'intégration | M |
| Jobs | réconciliation horaire, traitement de l'inbox en échec, relance des invitations | S |
| App | affichage de la source « Fidwork » et de l'adresse/repère sur les entrées ; liste « pointages à vérifier » (managers) | S |

### Fidwork
| Élément | Détail | Taille |
|---|---|---|
| Heure réelle des événements | colonne `events.occurred_at`, lecture de `created_date_utc` corrigé (`HH`) | S |
| Actions `work_start` / `work_stop` | `event_rules.py`, `process_event`, payload : intervention, phase, géoloc, `start_event_id`, liste des compagnons (pointage d'équipe) | M |
| Partenaire `clockifai` | adaptateur dans `service_dir/partners/`, enqueue sur création/statut/rôles, réglage par site dans `dict_of_settings` | M |
| App terrain | tuile QR + bouton intervention + sélection d'équipe + état en cours | M |
| Retour d'heures | proxy `labour`, affichage dans `InterventionPage`, bouton de pré-remplissage des champs nucléaires | M |

## 6. Lots et ordre de livraison

| Lot | Résultat visible | Prérequis |
|---|---|---|
| **F0** Cadrage | Choix du tenant pilote, liste des phases, rôles → managers, information des salariés (géolocalisation) | — |
| **F1** Référentiel | Les interventions d'un site pilote apparaissent comme tâches dans Clockifai ; les compagnons sont invités et peuvent déjà pointer depuis l'app Clockifai | Clockifai lot 3 (invitations) : fait |
| **F2** Pointage terrain | Scan QR → départ/arrêt du pointage dans Fidwork, y compris hors ligne et en équipe | F1 + correctif heure des événements |
| **F3** Retour Fidwork | Heures par intervention visibles dans Fidwork, pré-remplissage des formulaires nucléaires | F2 |
| **F4** SSO | « Continuer avec Fidwork » dans l'app Clockifai | facultatif |

## 7. Points d'attention

- **RGPD / droit du travail** : un pointage géolocalisé est une donnée personnelle de salarié. Ne capter la position qu'au départ et à l'arrêt (pas de suivi continu), informer les salariés et le CSE, fixer une durée de conservation, permettre la consultation par l'intéressé (déjà le cas dans Clockifai).
- **Qui possède le workspace ?** Le temps des compagnons relève de leur **employeur** (l'entreprise d'échafaudage), alors que le tenant Fidwork peut être le donneur d'ordre. Si les deux diffèrent, prévoir un workspace par entreprise et ne renvoyer au donneur d'ordre que les agrégats par intervention (pas le détail nominatif).
- **Besoins paie BTP** non couverts par un clone de Clockify : heures supplémentaires, paniers, indemnités de trajet, intempéries. À traiter en lot dédié (champs personnalisés sur l'entrée ou export vers l'outil de paie) si confirmé.
- **Charge** : quelques centaines de compagnons × 2 événements/jour reste négligeable pour l'outbox Fidwork (cron 2 min) et pour Clockifai.
- **Disponibilité** : si Clockifai est indisponible, l'outbox Fidwork accumule et rejoue ; aucun pointage n'est perdu.

## 8. Questions à trancher

1. Le workspace Clockifai appartient-il à l'entreprise d'échafaudage / calorifugeage ou au donneur d'ordre ?
2. Les compagnons doivent-ils pointer **uniquement** depuis Fidwork (recommandé) ou aussi depuis l'app Clockifai ?
3. Granularité souhaitée : par intervention (recommandé), ou aussi par phase et par repère ?
4. Le pointage d'équipe par le chef d'équipe est-il la règle, ou chacun pointe-t-il pour lui-même ? (Côté Clockifai, voir [03-saisie-pour-autrui.md](03-saisie-pour-autrui.md).)
5. Faut-il remplir automatiquement les champs d'heures des formulaires nucléaires, ou seulement les proposer ?

## 9. À reprendre avant la relance (revue du 23 octobre 2026)

Points bloquants relevés depuis, à traiter quand le plan reprendra :
1. **Gardes contournées** : sans JWT, `time_entries_guard` ne contrôle rien (0009). Un pointage rejoué ou en
   retard peut atterrir dans une période verrouillée, approuvée ou facturée. Écrire par une fonction qui
   reprend les contrôles, comme `agent_entry_write` du plan 10, et envoyer les refus dans « pointages à
   vérifier ».
2. **Limite de chronomètres** : avec `max_running_timers = 1` (défaut), un `work_start` arrête le chronomètre
   de l'app ou du kiosque ; un `work_start` en retard est enregistré déjà clos (0011), puis `work_stop`
   écraserait cette fin. La sortie du kiosque arrête aussi les pointages Fidwork. Ne jamais prolonger une
   entrée déjà close, et décider comment les pointages Fidwork se combinent à la limite et au kiosque.
3. **Identifiant déterministe** : un pointage d'équipe porte la liste des compagnons, donc
   `uuid5(event_on_site_uuid)` donnerait le même `id` à N entrées. Utiliser
   `uuid5(lien, event_uuid:fidwork_user_id)`.
4. **Compagnons sans compte** : ils ne se connectent jamais, la production n'a pas de SMTP, et chaque compte
   créé reçoit un espace personnel. S'inspirer des comptes techniques des agents (plan 10, D14) et de
   `identity_links` (créée par le plan 09, lot 3).
5. **Secrets et données personnelles** : `integration_links`, `integration_inbox` et `identity_links` vont dans
   `clockifai_private` (migration `*.admin.sql`) ; toute table de `public` est publiée vers PowerSync.
6. **Géolocalisation** : sur `time_entries`, elle partirait vers tous les managers par les flux `SELECT *`,
   contrairement à §7. Table séparée, non synchronisée, lisible par l'intéressé et les admins, avec une durée
   de conservation.
7. **Rejeux** : la purge supprime les entrées effacées après 30 jours. Garder l'inbox plus longtemps que la
   fenêtre de rejeu de Fidwork, sinon un rejeu recrée un pointage supprimé.
