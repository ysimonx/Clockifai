# Chronomètres simultanés — plan

> Statut : **fait** (22 octobre 2026). Pistes : §6 « Plus tard ».
>
> Objectif : pouvoir faire tourner **plusieurs chronomètres en même temps**. Avec des agents IA,
> on mène souvent plusieurs chantiers en parallèle, sur plusieurs ordinateurs ou dans plusieurs sessions,
> et chacun mérite son propre chronomètre.

## 1. Décision

| Sujet | Choix |
|---|---|
| Modèle | **Limite par workspace** `workspaces.max_running_timers` (réglage admin) : 1, 2, 3, 5 ou illimité (`0`). Inspiré de Kimai (`active_entries.hard_limit`) |
| Défaut | **1** : comportement d'origine, rien ne change pour une entreprise qui pointe la présence |
| Limite atteinte | Le **plus ancien** s'arrête au début du nouveau : la règle « le plus récent gagne » (0004) généralisée |
| Même tâche (22 octobre 2026) | **Un seul chronomètre en cours par tâche** : une tâche joue le rôle d'un ticket (plan 04), la description dit ce qu'on y fait. Sans tâche : même projet (ou aucun) et même description. Démarrer ou relancer une tâche qui tourne déjà est refusé (« Un chronomètre tourne déjà sur cette tâche ») ; dans la liste, ▶ devient ■ Arrêter. Contrôle **côté app** (`sameTimerTarget`, filet dans `TimeEntryRepository.start()`) : deux appareils hors ligne pourraient encore lancer la même tâche, cas accepté |
| Écartés | Un chronomètre **par appareil** : il faudrait identifier les appareils, deux sessions sur la même machine resteraient impossibles, et le téléphone ne pourrait pas arrêter le chronomètre d'un autre poste. Opt-in **par membre** : un réglage de plus, sans besoin identifié |

Le temps cumulé peut dépasser le temps réel, puisque deux projets comptent chacun leur heure. C'est voulu, et c'est pour cela que la limite reste à 1 par défaut.

## 2. Serveur : migration 0011 (`0011_parallel_timers.sql`)

- Nouvelle colonne `workspaces.max_running_timers smallint not null default 1 check (>= 0)`. Les lignes sont « touchées » pour que la colonne soit répliquée.
- L'index unique `time_entries_one_running_idx` est supprimé, car un index ne peut pas dépendre d'un réglage. Un index non unique sur les mêmes colonnes le remplace.
- Le trigger `time_entries_a_single_running` est remplacé par `time_entries_a_running_limit` (fonction `time_entries_running_limit()`) :
  - La fonction lit la limite du workspace et sort tout de suite si elle vaut 0 (illimité).
  - Un verrou consultatif par `(workspace, user)` (`pg_advisory_xact_lock`) sérialise les démarrages concurrents : il remplace la garantie de l'index unique.
  - Les chronomètres en cours sont classés du plus récent au plus ancien, et le nouveau y prend sa place selon son début. Les `lim` premiers continuent de tourner. Les autres sont arrêtés au début du nouveau.
  - Si le nouveau est plus ancien que les `lim` chronomètres en cours (il arrive en retard, créé hors ligne), il est enregistré déjà terminé, au début du plus ancien de ceux qui restent.
  - Avec `lim = 1`, le comportement est strictement celui de 0004.
- La modification du réglage reste réservée aux admins par la politique `workspaces_update` (`is_admin`).

## 3. App

- **Données** :
  - `max_running_timers` est ajoutée dans `schema.dart` et dans la table Drift (nullable, lue `?? 1` par `SessionController.runningTimersLimit`).
  - `TimeEntryRepository.watchRunningAll()` liste les chronomètres en cours, les plus récents d'abord.
  - `start(maxRunning:)` arrête localement les plus anciens au-delà de la limite, comme le fait le trigger.
- **Barre du chronomètre** :
  - Avec une limite de 1, elle est inchangée.
  - Sinon, elle reste un formulaire de démarrage, et chaque chronomètre en cours a sa ligne (`RunningTimerRow`) : description, projet, durée, arrêt, modification, abandon.
  - Sur mobile, au-delà de deux chronomètres, les lignes sont repliées sous « N chronomètres en cours ».
  - Un message signale quand la limite a arrêté le plus ancien.
- **Notification mobile** : elle montre le chronomètre le plus récent, avec « + N autres ».
- **Équipe** : le badge du membre affiche le nombre de chronomètres, avec une ligne d'activité pour chacun.
- **Calendrier** : les blocs qui se chevauchent sont posés côte à côte. Cela vaut aussi pour les saisies manuelles superposées, qui se masquaient jusqu'ici.
- **Réglages** : nouvelle option « Chronomètres simultanés », à côté de l'arrêt automatique.

## 4. Kiosque (Flask)

- `/state` ne renvoie que le chronomètre le plus récent de chaque membre (`left join lateral`). Sans cela, un membre avec deux chronomètres apparaîtrait deux fois.
- `/punch` : la sortie arrête **tous** les chronomètres en cours du membre, car le kiosque pointe la présence.

## 5. Tests

- Flutter (`time_entry_repository_test.dart`) : limite 2, limite atteinte, limite illimitée.
- Intégration :
  - `test_parallel_timers_limit` : limite 2, chronomètre arrivé en retard, limite illimitée, réglage refusé à un simple membre ;
  - kiosque avec deux chronomètres en cours ;
  - la règle d'origine (`test_running_timer_conflict_latest_wins`) passe telle quelle.
- Vérifié à la main : 12 démarrages concurrents donnent exactement `lim` chronomètres en cours, sans erreur.

## 6. Plus tard

- **Chronomètres pilotés par les agents IA** : repris et remplacé par le plan 10 (`10-suivi-claude-code.md`). Les agents y sont des membres de l'équipe, avec leurs propres chronomètres, hors de la limite `max_running_timers`.
- Étiquette d'appareil ou de source sur chaque entrée : la colonne `source` est créée par le plan 10.
- Rapports : distinguer temps de présence (union des intervalles) et temps cumulé.
