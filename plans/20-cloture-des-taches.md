# Plan 20 — Clôture automatique des tâches de Claude

> Statut : **fait** (31 octobre 2026). Demandé par Yannick : « la liste des tâches et des sous-tâches s'allonge…
> et je n'ai pas envie de les marquer comme finies manuellement ».

## Constat

Depuis le plan 16, chaque session de Claude Code nomme un objectif (une tâche) et ses étapes (des sous-tâches). Les
listes de tâches de Projets et clients, du sélecteur et des rapports s'allongent sans fin :

- **Fastidieux** : les terminer à la main demande de passer sur chaque tâche.
- **Inutile** : une tâche terminée restait affichée, barrée, au milieu des autres dans Projets et clients.
- **Doublons** : quand Claude reprenait le nom d'une tâche terminée, le serveur en créait une seconde, car
  `_task_named` ne cherchait que les tâches actives. Un humain qui retapait ce nom dans le sélecteur faisait de même.

## Décisions (validées le 31 octobre 2026)

1. **Inactivité.** Un job de nuit (`close_idle_agent_tasks`, 04:00 UTC) termine une tâche ou une sous-tâche sans temps
   depuis 7 jours (`JOB_CLOSE_IDLE_TASKS_AFTER_DAYS`, 0 = jamais).
   - Le temps d'une tâche compte celui de ses sous-tâches.
   - Une entrée en cours la garde ouverte.
   - Le délai est celui du recalcul des sessions (`MAX_AGE`, 7 jours) : une tâche terminée par le job n'a plus
     d'entrée que le recalcul puisse toucher.
2. **Périmètre.** Seules les tâches créées par le serveur pour un agent se terminent seules, c'est-à-dire celles de
   `clockifai_private.agent_tasks`, tâches de ticket comprises. Celles des humains, comme « Unité 4 › Montage », ne
   bougent pas.
3. **Reprendre, c'est rouvrir.**
   - `_task_named` (objectif, étape) et `_ticket_row` (ticket) trouvent aussi les tâches terminées, les actives
     d'abord.
   - `reopen_task` rouvre la tâche de l'entrée, avec sa tâche si c'est une sous-tâche. `process_session` ne l'appelle
     que pour l'entrée en cours ou qui vient de finir (`IDLE_TIMEOUT`), et jamais pour les entrées plus anciennes que
     le recalcul rejoue : une tâche terminée à la main ne se rouvre pas parce qu'une vieille entrée de la même session
     est recalculée.
   - Dans l'app, retaper le nom d'une tâche terminée, ou coller son ticket, la reprend et la rouvre.
4. **Affichage.** Dans Projets et clients, les tâches terminées sont repliées sous la ligne « Terminées (N) » en bas
   du projet. On y trouve :
   - une tâche terminée, avec toutes ses sous-tâches ;
   - une sous-tâche terminée d'une tâche ouverte, sous son chemin « Tâche › Sous-tâche ».

   Rouvrir une sous-tâche rouvre aussi sa tâche (`reopenTask`), sinon elle resterait cachée sous une tâche terminée.
5. **Membres.** `tasks_guard` réserve aux managers le changement de statut. La reprise d'une tâche terminée dans le
   sélecteur est donc réservée aux managers ; un membre garde l'ancien comportement : seules les tâches actives sont
   proposées. Claude, côté serveur, rouvre pour tout le monde.

## Pistes écartées pour l'instant

- **Étape suivante** : clore la sous-tâche précédente quand Claude passe à une nouvelle étape. Le job y suffit, et
  Claude revient souvent sur une étape.
- **Claude déclare la fin** : un outil MCP pour clore l'objectif au merge ou au « c'est fini ». Cela dépend du
  jugement de Claude, et la réouverture rend le job sans risque.
- **Ticket fermé chez le client** (Jira, Linear, GitHub) : cela demande un accès à leur API (plan 09).

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Serveur | Job `close_idle_agent_tasks` et réglage ; `_task_named` et `_ticket_row` sur les terminées ; `reopen_task` dans `process_session` ; test d'intégration (clôture, tâche humaine et tâche récente épargnées, reprise de l'objectif, de l'étape et du ticket sans doublon) | fait |
| 2 App | Projets et clients : « Terminées (N) » replié, Rouvrir (`reopenTask`, tâche parente comprise) ; sélecteur : reprise d'une tâche terminée par son nom ou son ticket (managers) ; tests de la page et du sélecteur | fait |
| 3 Documentation | Guide (membre, manager), `composants.md`, séquence Claude Code, CHANGELOG, CLAUDE.md | fait |
