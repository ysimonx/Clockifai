# Plan 14 — Coller aux maquettes

> Statut : **en cours** (27 octobre 2026). Maquettes : canevas « Clockifai, UX repensée »
> (https://claude.ai/artifact/U6KHyAhd2xoKwYDnzggnRT, privé). Fait suite au plan 13.

## Constat

Le plan 13 a livré les fonctions des maquettes (Aujourd'hui, saisie express, propositions, Semaine, ⌘K, mobile
chantier, présence), mais pas leur allure. Retour de Yannick le 27 octobre 2026, une fois la 0.2.3 en ligne :
« je m'attendais à quelque chose de beaucoup plus changé avec les maquettes ». Écarts relevés sur la version en ligne :

| Maquettes | Version 0.2.3 |
|---|---|
| Menu de 7 entrées : Aujourd'hui, Semaine, Rapports, Factures, Équipe ; Projets et clients, Paramètres ; « Rechercher ou agir ⌘K » en tête, état de la synchronisation en pied | 15 entrées en trois sections (Suivi du temps, Feuille de temps, Calendrier, Planning, Absences, Approbations, Pointage, Clients, Tags… chacun la sienne) |
| Pas de barre de chronomètre : le chronomètre en cours est une pastille dans l'en-tête | Barre « Sur quoi travaillez-vous ? … DÉMARRER » de Clockify en haut de chaque page |
| Encre presque noire pour les actions, fond gris froid, cartes blanches, Geist et Geist Mono pour les heures | Bleu Material, police du système, boutons en capitales |
| Téléphone : « Comme vendredi ? » en tête, gros bouton « Reprendre la journée », barre du bas Aujourd'hui, Semaine, **+**, Équipe, Plus ; « + » ouvre la saisie au pouce | Barre de chronomètre, puis la page d'ordinateur en plus étroit ; barre du bas Aujourd'hui, Suivi du temps, Feuille de temps, Calendrier, Plus |

Et dans le guide : la mention « Vidéo sans son » revient sur chaque page, et aucune vidéo courte ne montre à tout
le monde le geste de base (démarrer et arrêter le chronomètre, ajouter du temps), sur ordinateur et sur téléphone.

## Décisions

- **27 octobre 2026** : on suit les maquettes. Cela revient sur deux choix du plan 13 :
  - décision 4 (« le bleu reste la couleur de marque ») et lot 10 (« pas de police embarquée ») : identité des
    maquettes, Geist et Geist Mono embarquées dans l'app (licence OFL, hors ligne, environ 700 Ko) ;
  - décision 1 (« Aujourd'hui complète Suivi du temps ») : « Suivi du temps » devient la vue Liste de « Semaine »,
    plus une entrée du menu.
- Le chronomètre reste à portée de tous : bouton « Démarrer » toujours visible en haut à droite (ordinateur), dans
  « + » et en tête d'« Aujourd'hui » (téléphone) ; en marche, il devient la pastille « description · projet · 0:47 ■ ».
- Regroupements du menu :
  - **Semaine** : Grille (feuille de temps), Liste (suivi du temps), Calendrier ;
  - **Équipe** : Personnes (avec le tableau des retards), Approbations, Pointage, Planning, Absences ; chacun ne
    voit que les onglets que ses droits ouvrent (un membre : Planning et Absences) ;
  - **Projets et clients** (managers) : Projets, Clients, Étiquettes.
  Les anciennes adresses (`/`, `/calendar`, `/approvals`…) restent valables : liens, notifications, palette ⌘K.

## Lots

| Lot | Contenu | État |
|---|---|---|
| 1 Menu et coquille | Menu de 7 rubriques, recherche ⌘K et synchronisation dans le menu ; barre de chronomètre remplacée par le bouton Démarrer / la pastille, avec « Ajouter du temps » à côté ; onglets d'Équipe et de Projets et clients ; Semaine : Grille, Calendrier, Liste (le Suivi du temps) ; téléphone : barre du bas avec « + » | fait |
| 2 Identité | Geist, Geist Mono (durées, heures, raccourcis) ; encre, fond gris froid, cartes blanches bordées, rayons 16 / 12 / 10 ; clair et sombre | fait |
| 3 Aujourd'hui | Ordinateur : en-tête, saisie express, frise à gauche ; À compléter (propositions à ajouter, ou créneaux à remplir), Bilan du jour par projet (Vous, Claude) à droite. Téléphone : « Comme vendredi ? » et « Reprendre la journée », liste du jour, puis saisie express et frise | fait (feuille « + » : `features/time_entries/quick_add_sheet.dart`) |
| 4 Autres pages | Semaine (grille, « Avant de soumettre »), Rapports, Équipe, Factures : en-têtes et cartes des maquettes | en cours (thème appliqué, titres) |
| 5 Guide et vidéos | Vidéo « Premiers pas » (ordinateur puis téléphone : démarrer, arrêter, ajouter du temps, « Comme hier ») en tête du guide ; plus de mention « Vidéo sans son » ; les six vidéos retournées | fait (vidéos tournées et publiées le 27 octobre 2026) |
| 6 Invitations | Avec un serveur de mail : case « Envoyer l'invitation par email », cochée ; dans tous les cas le lien, à copier (`GET /api/invitations/options`, `send_email`, `app_url`) | fait |

### Décisions de mise en œuvre

- Le chronomètre et « Ajouter du temps » restent en haut à droite de chaque page sur ordinateur ; sur téléphone, ▶
  en haut et « + » en bas. La pastille montre le plus récent des chronomètres en cours ; un toucher les liste.
- « Liste » de la Semaine ouvre le Suivi du temps (regroupement, sélection multiple, glisser sur téléphone) plutôt
  qu'une liste de plus.
- Les anciennes adresses restent valables ; la palette ⌘K liste toujours chaque page.
