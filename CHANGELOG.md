# Notes de version

Les évolutions visibles de Clockifai, pour les utilisateurs et les administrateurs d'une installation.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

La section « Non publié » est complétée au fil des modifications. À chaque envoi en production ou sur les stores,
elle devient une version datée (numéro de `app/pubspec.yaml`), et son texte sert aux notes de TestFlight et de
Google Play. La 0.2.0 est la première version figée : elle reprend tout ce qui est arrivé depuis le début, avec
la date d'arrivée de chaque évolution.

## [Non publié]

## [0.2.0] — 2026-10-24

### Ajouté

- **Première version** (11 octobre 2026), sur le web, iPhone et Android, en français et en anglais :
  - saisie du temps : chronomètre (qui survit au redémarrage et continue sur un autre appareil), saisie après
    coup, « continuer », dupliquer, tags, facturable ;
  - feuille de temps hebdomadaire projets × jours, durées saisies en `1:30`, `1,5` ou `90m` ;
  - clients, projets (couleur, taux horaire, budget, public ou privé), tâches, tags, archivage ;
  - plusieurs workspaces, rôles propriétaire, admin, manager et membre, taux par membre, invitations par email
    ou par lien quand aucun serveur d'email n'est configuré ;
  - règles du workspace : projet ou description obligatoires, arrondi, arrêt automatique des chronomètres
    oubliés, verrouillage des périodes ;
  - rapports résumé et détaillé, graphiques, exports CSV, Excel et PDF ;
  - calendrier, planning (affectations, capacité, surcharge signalée), absences (types, droits annuels, soldes,
    demandes, validation, jours fériés), approbation des feuilles de temps ;
  - factures générées depuis le temps facturable (numérotation continue, TVA, remise, PDF) ;
  - kiosque : tablette partagée où chacun pointe avec son code PIN ;
  - fonctionnement hors connexion, synchronisation automatique au retour du réseau.
- **Chefs d'équipe** (11 octobre) : groupes d'utilisateurs et chefs d'équipe ; saisie du temps pour un collègue
  (selon le réglage du workspace), pointage de toute l'équipe en une fois, mention « saisi par … » sur les entrées ;
  approbation des feuilles de temps et des absences de son équipe ; rapports et exports limités à l'équipe.
- **Tâches à la volée** (12 octobre) : créer une tâche depuis le sélecteur de projet, sans passer par la page
  Projets ; réglage « qui peut créer des tâches » (tout le monde ou les managers) ; « Modifier le chronomètre »
  dans le menu du chronomètre.
- **Vidéos de démonstration** (12 octobre) : cinq vidéos, une par rôle (membre, chef d'équipe, manager,
  propriétaire, administrateur).
- **Application macOS** (14 octobre) : icône dans la barre de menus pour démarrer ou arrêter un chronomètre,
  choisir la description et le projet, relancer une entrée récente, avec le temps écoulé à côté de l'icône ;
  fermer la fenêtre ne quitte pas l'application ; option « Démarrer à l'ouverture de session ». Distribution
  notarisée et par TestFlight.
- **Distribution iPhone et Android** (14 octobre) : TestFlight et Google Play ; l'écran de connexion indique la
  version lancée et le serveur utilisé.
- **Chronomètres simultanés** (22 octobre) : nombre de chronomètres en cours réglable par workspace (1 par
  défaut, 0 = illimité ; au-delà, le plus ancien s'arrête) ; une ligne par chronomètre en cours ; calendrier en
  colonnes pour les entrées qui se chevauchent ; au kiosque, la sortie arrête tous les chronomètres du membre.
- **Entrées similaires regroupées** (22 octobre) : même jour, description, projet, tâche, tags et facturable →
  une seule ligne dépliable avec le nombre d'entrées et la durée cumulée ; modifier ou supprimer le groupe d'un
  coup ; réglage « Regrouper les entrées similaires » sur chaque appareil.
- **Installation** (13 octobre) : hébergement sur un serveur partagé avec d'autres applications, derrière un
  reverse proxy commun ; l'application web est compilée sur le serveur ; sauvegarde quotidienne de la base.
- **Documentation** (23 octobre) : guide utilisateur en ligne avec les vidéos (`/guide/`), guide d'exploitation
  (installation, sauvegarde, restauration), architecture et API ; dans l'application, « Guide d'utilisation »
  (en bas du menu, et Paramètres › Aide) ouvre la page du guide qui correspond à son rôle.
- **Temps de Claude Code** (24 octobre) : chaque membre connecte ses ordinateurs dans Paramètres › Intégrations ›
  Claude Code ; les sessions de Claude Code deviennent alors du temps de son agent « Claude · nom », membre de
  l'équipe, avec un chronomètre par session qui s'arrête à la dernière activité après 10 minutes sans activité,
  décrit par les messages des commits. Chaque installation distribue le plugin Claude Code
  (`/api/claude/marketplace.json`). Le pilote consulte et corrige le temps de son agent depuis le sélecteur de
  personne (feuille de temps, calendrier, rapports), sans pouvoir en saisir ; l'équipe affiche les agents à part.
  Les agents ne comptent ni dans la saisie pour autrui, ni dans les chefs d'équipe, groupes, absences, planning ou
  approbations. En donnant un projet à une entrée de son agent, « Toujours rattacher ce dépôt à ce projet » y envoie
  aussi les sessions suivantes du même dépôt. Le bandeau « Claude travaille », en haut du suivi du temps, montre
  les sessions en cours. Dans les rapports et leurs exports, le filtre « Humains et agents » met à part le temps
  des agents, et une colonne « Type » (humain ou agent) les distingue dans le détail des exports. Un administrateur
  décide si le temps des agents est facturable (Paramètres, « Temps des agents Claude »), avec une exception
  possible par projet. Depuis Paramètres › Intégrations › Claude Code, « Voir sa fiche dans l'équipe » mène à
  la fiche de son agent. La connexion d'un poste commence par l'installation de la commande `claude`, que
  l'extension VSCode n'installe pas, et indique l'ordre pour enregistrer le jeton (coller la commande, copier le
  jeton, puis Entrée). Un agent retiré par erreur se restaure depuis Équipe, rubrique « Agents retirés ». Dans la liste des
  postes connectés, « Reconnecter » redonne un jeton à un poste, et « Afficher les commandes d'installation »
  rappelle les commandes.

### Modifié

- Supabase Studio n'est plus accessible qu'en réseau local ; les API restent publiques (23 octobre). Réglage
  `STUDIO_ALLOWED_IPS` pour l'ouvrir à un VPN.
- Les emails d'invitation arrivent sous le nom « Clockifai » (`SMTP_SENDER_NAME`), comme ceux de connexion et
  de mot de passe oublié (23 octobre).
- Un seul chronomètre par tâche (22 octobre) : démarrer une tâche qui tourne déjà propose de l'arrêter ;
  sans tâche, la règle porte sur le projet et la description.

### Corrigé

- Claude Code : un poste configuré avec son seul jeton n'envoyait rien, faute d'adresse transmise au plugin.
  « Copier le jeton » copie aussi l'adresse, et le plugin retrouve celle de son instance (24 octobre).
- `make backup` ne rendait jamais la main : la sauvegarde immédiate partait en boucle (22 octobre).
- macOS : l'envoi vers TestFlight était refusé par Apple (ITMS-90284) (14 octobre).
