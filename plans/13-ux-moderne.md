# Plan 13 — UX repensée : saisir sans effort, revoir en un coup d'œil

> Statut : **envisagé** (26 octobre 2026). Maquettes : canevas « Clockifai, UX repensée »
> (https://claude.ai/artifact/U6KHyAhd2xoKwYDnzggnRT, privé), dix écrans dont cinq interactifs.

## Constat

Clockifai reprend fidèlement l'interface de Clockify : une barre de chronomètre en haut (« Sur quoi travaillez-vous ? »),
une liste d'entrées par jour, une feuille de temps et un calendrier séparés, des boîtes de dialogue pour modifier,
des confirmations pour supprimer. Sur les comptes de démo, le 26 octobre :

- la page d'accueil est chronomètre d'abord, alors que la saisie après coup est la façon de travailler privilégiée ;
- la feuille de temps et le calendrier de la semaine en cours partent vides, rien ne propose la semaine précédente
  ni le planning ;
- les heures non saisies ne se voient nulle part : une journée à 6 h ressemble à une journée à 7 h 30 ;
- les durées s'affichent à la seconde (« 3:00:00 ») pour du temps saisi au quart d'heure ;
- le temps de Claude est dans une autre page que le sien ;
- sur téléphone, c'est l'écran web en plus petit, chronomètre en tête.

Les avis publiés sur Clockify (Capterra) disent la même chose : saisie à la main fastidieuse, édition peu commode,
pas d'actions groupées, chronomètre rigide quand on est interrompu, descriptions perdues faute d'enregistrement
automatique, appli mobile en retrait.

## Principes

1. **Après coup d'abord.** On reconstitue sa journée ; le chronomètre reste, en second.
2. **Les trous se voient et se comblent.** Une journée incomplète est visible, avec des pistes pour la compléter.
3. **Une ligne suffit.** « 1h20 point hebdo interne » crée l'entrée : durée, plage, jour, projet, tâche, sans formulaire.
4. **Clavier partout, ⌘K pour le reste.** Aucune action courante ne demande la souris.
5. **Annuler plutôt que confirmer.** Pas de « Êtes-vous sûr ? » : l'action se fait, un bandeau propose Annuler.
6. **Corriger sur place, par lots.** Pas de boîte de dialogue pour changer un projet ; sélection multiple.
7. **Vous et Claude côte à côte.** Le temps de l'agent est une piste du journal, avec son coût.
8. **Le téléphone pour le chantier.** « Comme hier » en un geste, au pouce, hors ligne assumé.

## Propositions (une par écran du canevas)

| Écran | Ce qui change |
|---|---|
| **Aujourd'hui** (journal du jour) | Remplace « Suivi du temps » et « Calendrier » en vue jour : deux pistes horaires (Vous, Claude), les blocs colorés par projet, Claude en trame hachurée avec son coût ; les trous (« 1 h 20 à saisir ») avec un bouton Remplir ; la pause habituelle n'est pas un trou ; bilan du jour contre l'objectif ; chronomètre en cours en pastille. |
| **Saisie express** | Une ligne en langage courant, analysée à la frappe en étiquettes (durée, projet, tâche, description, jour, plage, facturable) ; sans plage, l'entrée se place dans le premier trou assez grand ; Entrée enregistre, Tab corrige un champ ; exemples cliquables pour découvrir. |
| **Pistes pour compléter** | Sources : agenda, travail de Claude (fin de session, commits relus), habitudes (« chaque lundi à 10:30 »), planning ; « Tout accepter » quand les pistes se complètent sans se chevaucher. |
| **⌘K** | Palette : démarrer, saisir sur un projet, reprendre hier, copier la semaine, aller à, factures prêtes ; recherche sans accents ; raccourcis à une touche (N, S, D, E, J/K, ⌘Z). |
| **Fin de journée** (barre de menus macOS, notification mobile) | « Il manque 1 h 20 » avec les pistes à cocher, détection des chevauchements, ajout en un geste, rappel le lendemain. |
| **Semaine** | Une page, trois vues (grille, liste, calendrier) ; « Copier la semaine précédente », « Remplir depuis le planning » ; suggestions en pointillé dans la grille ; total du jour avec jauge et écart ; liste « Avant de soumettre » avec la correction proposée ; saisie « 3.5 », « 3:30 », « 3h30 ». |
| **Édition** | Description modifiable sur place, sélecteur de projet et tâche en surimpression avec recherche floue et récents ; sélection multiple et barre d'actions (projet, tâche, facturable, dupliquer vers, supprimer) ; Annuler (⌘Z). |
| **Rapports par questions** | « Où part mon temps ? », « Prêt à facturer » (montant en attente sur l'onglet), « Rentabilité », « Claude et moi », « Ma question » ; comparaison à la période précédente ; tableau par client avec Vous, Claude, montant, coût IA, pas encore facturé ; facture détaillée par tâche en un clic, avec l'usage IA au coût en option. |
| **Équipe** (manager) | Compteurs (à approuver, incomplètes, sans saisie) ; une ligne par personne avec ses cinq jours ; relance par notification (une par jour, avec « reprendre jeudi ») ; approbation avec l'écart au planning et les entrées saisies par le chef d'équipe. |
| **Téléphone** | « Comme vendredi ? » en un bouton ; durée au pouce (±15 min, préréglages, matin ou après-midi), tâches en pastilles, dictée ; glisser pour dupliquer ou supprimer ; badge hors ligne ; pointage d'équipe : présents cochés, exceptions (« parti à 15:00 »), absences validées exclues. |

Identité visuelle des maquettes, à confirmer : Geist (interface) et Geist Mono (heures, raccourcis), fond neutre
froid, encre presque noire pour les actions principales, couleurs de projet de la palette catégorielle validée
(contraste et daltonisme), Claude repéré par une trame et une étoile violette plutôt que par une couleur de plus.

## Lots

| Lot | Contenu | Taille | État |
|---|---|---|---|
| 1 Petits gains | Annuler au lieu des confirmations ; durées sans secondes ; description et projet modifiables sur place ; sélection multiple et barre d'actions ; raccourcis à une touche ; ⌘K (navigation et actions) | M | envisagé |
| 2 Journal du jour | Page « Aujourd'hui » (pistes Vous et Claude, trous, pause habituelle dans le profil, bilan du jour) ; remplace la vue jour de « Suivi du temps » et du calendrier | M/L | envisagé |
| 3 Saisie express | Analyseur FR/EN (durée, plage, jour, projet et tâche flous, `#tag`, facturable), étiquettes à la frappe, placement dans les trous ; aussi dans la barre de menus (⌥⌘T) | M | envisagé |
| 4 Pistes | Moteur de suggestions : planning, habitudes, sessions de Claude et commits (rejoint le plan 10, lot 2, `time_suggestions`) ; agenda en option (Google, Microsoft) | M/L | envisagé |
| 5 Semaine | Une page, trois vues ; copie de la semaine précédente, remplissage par le planning, suggestions en pointillé, liste avant soumission | M | envisagé |
| 6 Fin de journée | Récapitulatif à heure réglable (barre de menus macOS, notification mobile) avec les pistes à cocher | S/M | envisagé |
| 7 Rapports par questions | Questions toutes faites, comparaison, prêt à facturer et facture en un clic, usage IA au coût | M | envisagé |
| 8 Équipe | Tableau des retards, relance par notification, approbation avec écart au planning | M | envisagé |
| 9 Mobile chantier | « Comme hier », durée au pouce, dictée, glisser, badge hors ligne, pointage d'équipe repensé | M | envisagé |
| 10 Identité visuelle | Polices, jetons de couleur, mode sombre, densité | S/M | envisagé |

Ordre proposé : 1 (gains immédiats, sans changer la structure), puis 2 et 3 ensemble (le cœur de la proposition),
puis 5 et 6, puis 4, 7, 8, 9 ; 10 au fil de l'eau.

## Mesures

- temps pour saisir une journée complète après coup (objectif : moins de 20 secondes pour une journée type) ;
- part des journées complètes le soir même ;
- clics par entrée saisie ou corrigée ; nombre de boîtes de dialogue sur les parcours courants (objectif : zéro) ;
- part des semaines soumises sans demande de correction.

## Questions

1. Le journal du jour remplace-t-il « Suivi du temps » ou le complète-t-il (deux vues du même jour) ?
2. Saisie express : quelle grammaire minimale en anglais, et faut-il les tags et la facturation dans la ligne ?
3. Agenda : quelles sources, et lire seulement l'heure et le titre des événements ?
4. Identité visuelle : garder le bleu actuel comme couleur de marque, ou passer à l'encre et réserver le bleu aux projets ?
