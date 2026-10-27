# Plans

Un plan décrit une évolution : le besoin, les décisions et leurs raisons, puis l'avancement. L'état actuel du
logiciel, lui, est décrit dans `docs/`.

## Statuts

Chaque plan porte son statut en tête (`> Statut : **…** (date)`), et ses lots dans une colonne « État » quand il
en a. Le statut d'un plan découle de celui de ses lots.

| Statut | Sens |
|---|---|
| `envisagé` | Réflexion, rien n'est décidé |
| `validé` | Décidé, pas encore commencé |
| `en cours` | Au moins un lot commencé ou livré |
| `fait` | Tous les lots prévus sont livrés ; il peut rester des pistes |
| `en attente` | Suspendu |
| `remplacé` | Repris par un autre plan, qui est cité |

Commencer ou livrer un lot met à jour le statut du plan et cet index, dans le même commit. `make docs-check`
vérifie que chaque plan a un statut connu et le même ici.

Les numéros ne sont jamais réutilisés ni changés, sauf pour lever un doublon : `06-suivi-claude-code.md` est
devenu `10-suivi-claude-code.md` le 23 octobre 2026. Les plans 05 et 06 gardent chacun deux fichiers, déjà
livrés : on les cite par leur nom de fichier.

## Index

| Plan | Objet | Statut | Dépend de |
|---|---|---|---|
| [01-plan-clockifai.md](01-plan-clockifai.md) | Le clone de Clockify : architecture, données, sync, app, déploiement | fait | — |
| [02-integration-fidwork.md](02-integration-fidwork.md) | Temps des échafaudeurs et calorifugeurs saisi depuis Fidwork | en attente | — |
| [03-saisie-pour-autrui.md](03-saisie-pour-autrui.md) | Chefs d'équipe : groupes, périmètre, saisie pour autrui, pointage d'équipe | fait | — |
| [04-tickets.md](04-tickets.md) | Tâches comme tickets ; lot 0 : numéro de tâche `CLK-42` | validé (lot 0), envisagé (reste) | — |
| [05-chronometres-paralleles.md](05-chronometres-paralleles.md) | Plusieurs chronomètres en même temps, limite par workspace | fait | — |
| [05-hebergement-maison.md](05-hebergement-maison.md) | Production à la maison, `clockifai.kysoe.com` | fait | — |
| [06-macos-barre-de-menus.md](06-macos-barre-de-menus.md) | Version macOS et icône de la barre de menus | fait | — |
| [07-ios-android.md](07-ios-android.md) | Versions iOS et Android, TestFlight, Google Play | fait | — |
| [08-regroupement-entrees.md](08-regroupement-entrees.md) | Regroupement des entrées similaires | fait | 05-chronometres |
| [09-forges-git.md](09-forges-git.md) | Branches, commits et demandes de fusion rattachés aux tâches | envisagé | 04 lot 0, 10 lot 1 |
| [10-suivi-claude-code.md](10-suivi-claude-code.md) | Temps de Claude (agents membres de l'équipe), mon temps (suggestions) et usage IA (tokens, modèle, effort) | en cours | — |
| [11-documentation.md](11-documentation.md) | Documentation tenue à jour : architecture, API, guide, exploitation | fait | — |
| [12-taux-et-factures-par-tache.md](12-taux-et-factures-par-tache.md) | Taux des entrées saisies sans taux, nouveau taux appliqué aux entrées non facturées, factures détaillées par tâche | fait | — |
| [13-ux-moderne.md](13-ux-moderne.md) | UX repensée : journal du jour, saisie express, ⌘K, semaine pré-remplie, édition en place, rapports par questions, téléphone pour le chantier | fait | — |
| [14-coller-aux-maquettes.md](14-coller-aux-maquettes.md) | Allure des maquettes : menu de 7 rubriques, chronomètre en pastille, Geist, Aujourd'hui, invitations | en cours | 13 |
| [15-ecarts-avec-clockify.md](15-ecarts-avec-clockify.md) | Ce qui manque par rapport à Clockify : import, rappels, coût et marge, dépenses, API, sécurité | en cours | 01 |
| [16-sous-taches.md](16-sous-taches.md) | Sous-tâches : Projet › Tâche › Sous-tâche, cumul dans les rapports ; Claude range l'objectif en tâche et l'étape en sous-tâche | fait | 10, 12 |
| [17-revue-du-code.md](17-revue-du-code.md) | Revue du code après les plans 13, 14 et 16 : règles de la base, sessions Claude, exports, bugs et nettoyage de l'app | en cours | 13, 14, 16 |
| [18-rapports-presence-alertes-partage.md](18-rapports-presence-alertes-partage.md) | Rapports : présence et heures sup, alertes de budget, lien public, envoi planifié par email | fait | 15 |
