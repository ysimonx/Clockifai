# Plan 18 — Rapports : présence, alertes de budget, lien public, envoi planifié

> Statut : **fait** (27 octobre 2026), validé et livré le 27 octobre. Reprend le lot 6 du plan 15 (« Rapports »), choisi
> par Yannick comme prochain écart avec Clockify à combler.

## Décisions (27 octobre 2026)

1. **Heures sup** : comptées par rapport à la capacité journalière du membre (`workspace_members.capacity_hours_per_day`,
   7 h par défaut), moins les jours fériés et les absences approuvées. Elle n'avait pas de champ dans l'app : le
   lot 1 l'ajoute dans Équipe (« Taux et capacité », administrateurs).
2. **Lien public** : au choix à la création. Totaux par projet et tâche par défaut ; une case « avec le détail des
   entrées » montre aussi les descriptions.
3. **Envoi planifié** : vers toute adresse (membres ou externes : client, comptable), réservé aux managers.
4. **Alertes de budget** : heures du projet, montant du projet et estimation des tâches. Les deux derniers champs
   existent dans la base (`projects.budget_amount_cents`, `tasks.estimate_seconds`) mais pas dans l'app.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Présence | Vue « Présence » des rapports, calculée dans l'app (hors ligne), export CSV | fait |
| 2 Alertes de budget | Champs montant et estimation, jauges, « À surveiller », job horaire et email | fait |
| 3 Lien public | Rapports enregistrés (Flask), page HTML et PDF publics, révocation | fait |
| 4 Envoi planifié | Fréquence, destinataires, PDF en pièce jointe | fait |

## Lot 1 — Présence

- **Où** : Rapports, troisième vue à côté de Résumé et Détaillé. Même période et même filtre de personne que le
  rapport ; humains seulement (les agents Claude n'ont pas d'horaires).
- **Par personne et par jour** :
  - Arrivée : début de la première entrée ; Départ : fin de la dernière (une entrée en cours compte jusqu'à
    maintenant). Une entrée appartient au jour où elle commence, comme dans les autres rapports ;
  - Travaillé : union des intervalles (deux chronomètres en parallèle ne comptent pas double) ;
  - Pauses : de l'arrivée au départ, le temps sans entrée ;
  - Prévu : la capacité les jours ouvrés (lundi à vendredi, comme les absences), rien le week-end ni un jour férié,
    moins les absences approuvées (jour entier, demi-journée, ou, pour une politique en heures, les heures
    réparties sur les jours ouvrés de la demande) ;
  - Écart : travaillé − prévu.
- **Par personne sur la période** : travaillé, prévu, heures sup (écart positif) ou manquantes (négatif). Un jour
  prévu sans aucune entrée apparaît, vide : c'est ce qu'on cherche.
- **Droits** : ceux du rapport (soi ; son équipe pour un chef d'équipe ; tout le monde pour un manager). Les
  données sont déjà sur l'appareil par les flux, rien à ajouter côté serveur.
- **Export CSV** fait dans l'app, hors ligne : une ligne par personne et par jour.
- **Affichage** : une personne seule montre ses jours d'emblée ; une équipe, une ligne repliable par personne
  (travaillé, prévu, heures sup ou manque). Question toute faite « Heures sup du mois ».
- **Code** : `features/reports/attendance.dart` (calcul pur `attendanceOf`, testé, et la vue). Tests :
  `app/test/attendance_test.dart` (union des intervalles, entrée sur deux jours, jours fériés, demi-journée, absence
  en heures, week-end, jour sans entrée).

## Lot 2 — Alertes de budget

- **Champs** : projet, « Budget (montant) » à côté du budget en heures ; tâche, « Estimation » (`tasks_guard` la
  réserve déjà aux managers).
- **Consommé**, depuis le début du projet : heures de toutes les entrées non supprimées (d'une tâche : avec ses
  sous-tâches) ; montant des entrées facturables au taux de l'entrée (`coalesce(entrée, projet, membre)`),
  durées brutes.
- **App** : jauges (projet : heures et montant ; tâche : estimation) ; en tête de Projets, pour les managers, une
  section « À surveiller » : projets et tâches à 80 % et plus, orange à 80 %, rouge à 100 %. Calcul local.
- **Serveur** : job Flask toutes les heures. À chaque franchissement de 80 % puis de 100 %, un email aux managers
  actifs (propriétaires, admins, managers ; humains), dans leur langue (`profiles.locale`). Journal privé
  `clockifai_private.budget_alerts` (cible, seuil, valeur du budget) : une seule alerte par seuil, un budget relevé
  réarme. Sans SMTP, rien ne part mais l'alerte est notée (pas de rafale le jour où le SMTP est configuré).
- **Tests** : intégration (seuils, une seule fois, réarmement, managers seulement), app (jauges, « À surveiller »).
- **Livré** : `app/lib/features/projects/budget_watch.dart` (calcul et carte), `watchBudgetUsage` (dépôt des
  entrées), fiche « Modifier la tâche » (nom et estimation) ; `services/app/services/budget_alerts.py`, job
  `budget_alerts` (chaque heure, contexte Flask pour l'envoi), migration `0024_budget_alerts.admin.sql`. Un email
  par manager et par passage du job, regroupant les alertes de son workspace.

## Lot 3 — Rapports enregistrés et lien public

- **Rapport enregistré** (managers) : nom ; période relative (cette semaine, semaine dernière, ce mois, mois
  dernier, cette année) ou dates fixes ; filtres du rapport (client, projet, personne, facturable, humains ou
  agents) ; options : montants affichés, détail des entrées, arrondi.
- **Stockage** : `clockifai_private.saved_reports` (migration `.admin.sql`, hors API et hors réplication), géré par
  Flask, donc en ligne seulement : `GET/POST/PATCH/DELETE /api/reports/saved`.
- **Lien public** : jeton aléatoire de 32 octets. `GET /api/public/reports/<jeton>` rend une page HTML autonome,
  `?format=pdf` le PDF. Période relative calculée à l'ouverture, dans le fuseau du créateur. Révocable (nouveau
  jeton, ou suppression). `X-Robots-Tag: noindex`, pas de cache.
- La page et le PDF ont le même HTML (`services/shared_reports.py`, rendu par WeasyPrint pour le PDF) ; la requête
  des lignes est partagée avec les exports (`services/report_rows.py`).
- **App** : dans Rapports, « Enregistrer et partager » reprend les filtres affichés ; liste des rapports
  enregistrés (copier le lien, révoquer, supprimer).
- **Tests** : droits (managers seulement), jeton révoqué → 404, période relative, sans détail aucune description
  dans la page ni le PDF.
- **Livré** : migration `0025_saved_reports.admin.sql`, `routes/reports.py`, `services/shared_reports.py` ; dans
  l'app, bouton « Rapports partagés » de Rapports (`features/reports/saved_reports.dart`). Le lien est le chemin
  renvoyé par Flask complété par l'adresse de l'instance que l'app connaît. Un lien meurt avec les droits de son
  auteur (plus manager, désactivé ou retiré).

## Lot 4 — Envoi planifié

- Sur un rapport enregistré : chaque lundi (semaine passée) ou chaque 1er du mois (mois passé), à 8 h dans le
  fuseau du créateur ; destinataires : adresses libres.
- Job Flask toutes les 15 minutes ; la dernière période envoyée est notée : jamais deux fois la même.
- Email : résumé en texte (total, montant), PDF en pièce jointe (`send_mail` apprend les pièces jointes), lien
  public si le rapport en a un ; langue du créateur ; « envoyé à la demande de … » en pied.
- Sans SMTP : réglage grisé, avec la raison.
- **Tests** : échéance dans le fuseau, pas de double envoi, pièce jointe.
- **Livré** : migration `0026_report_schedule.admin.sql` ; `shared_reports.send_due_reports` (job
  `send_scheduled_reports` à 2, 17, 32 et 47 minutes de chaque heure) ; `send_mail` accepte des pièces jointes ;
  dans l'app, « Envoi par email » dans le formulaire de partage et dans le menu d'un rapport partagé. Une période
  n'est envoyée que si elle suit la dernière envoyée (`last_sent_period`), et une fréquence nouvellement réglée
  compte la dernière période terminée comme envoyée.
