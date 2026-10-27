# Notes de version

Les évolutions visibles de Clockifai, pour les utilisateurs et les administrateurs d'une installation.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

La section « Non publié » est complétée au fil des modifications. À chaque envoi en production ou sur les stores,
elle devient une version datée (numéro de `app/pubspec.yaml`), et son texte sert aux notes de TestFlight et de
Google Play. La 0.2.0 est la première version figée : elle reprend tout ce qui est arrivé depuis le début, avec
la date d'arrivée de chaque évolution.

## [Non publié]

### Ajouté

- **Sous-tâches** : Projet › Tâche › Sous-tâche (« Unité 4 » › « Montage »). La flèche ↳ en ajoute une, dans la
  page des projets et le sélecteur de projet ; la saisie montre les sous-tâches en pastilles sous la tâche choisie.
  Rapports : « Grouper par tâche » cumule les sous-tâches, qu'un clic déplie ; exports CSV, Excel et PDF : colonne
  « Sous-tâche » (27 octobre 2026).
- **Claude Code** : la tâche porte l'objectif (le titre du plan en cours, par exemple), stable d'une session à
  l'autre, et chaque étape devient une sous-tâche ; les rapports ne s'encombrent plus d'une tâche par étape. Mettez à
  jour le plugin sur chaque poste (`claude plugin update clockifai@clockifai`) (27 octobre 2026).

## [0.2.4] — 2026-10-27

### Modifié

- **Nouvelle allure**, celle des maquettes : police Geist (Geist Mono pour les heures et les durées), boutons
  d'action en noir, fond gris clair et cartes blanches, en clair comme en sombre (27 octobre 2026).
- **Menu simplifié** à sept rubriques : Aujourd'hui, Semaine, Rapports, Factures, Équipe, puis Projets et clients
  et Paramètres. « Semaine » réunit la grille (feuille de temps), le calendrier et la liste (suivi du temps) ;
  « Équipe » réunit personnes, approbations, pointage d'équipe, planning et absences, en onglets ; « Projets et
  clients » réunit projets, clients et tags. En tête du menu, « Rechercher ou agir ⌘K » ; en pied, l'état de la
  synchronisation (27 octobre 2026).
- **Chronomètre** : la barre « Sur quoi travaillez-vous ? » laisse la place à un bouton **Démarrer** en haut à
  droite, avec vos entrées récentes à reprendre d'un geste ; en marche, il devient une pastille (point vert,
  description, durée, bouton d'arrêt). À côté, **Ajouter du temps** saisit des heures déjà faites (27 octobre 2026).
- **Aujourd'hui** : la frise à gauche ; à droite, « À compléter » (chaque proposition à ajouter, ou les créneaux
  vides à remplir) et le bilan du jour, projet par projet, pour vous et pour Claude. Journée vide :
  « Comme vendredi ? » montre la dernière journée travaillée et « Reprendre la journée » la recopie
  (27 octobre 2026).
- **Téléphone** : barre du bas Aujourd'hui, Semaine, **+**, Équipe, Plus. Le « + » ajoute du temps sans clavier :
  durée en grand (± un quart d'heure, durées toutes faites), matin ou après-midi, tâches en pastilles, description
  dictée, « Enregistrer · 3:00 » ; ou démarre le chronomètre. « Comme vendredi ? » et la liste du jour en tête
  d'Aujourd'hui (27 octobre 2026).
- **Invitations** : avec un serveur de mail, la case « Envoyer l'invitation par email » (cochée) ; dans tous les cas,
  le lien s'affiche avec « Copier le lien », pour l'envoyer aussi par SMS ou messagerie (27 octobre 2026).
- Guide : les vidéos ne sont plus annoncées « sans son » à chaque page (27 octobre 2026).

## [0.2.3] — 2026-10-27

### Ajouté

- **Aujourd'hui**, la journée proposée : votre journée sur une frise, avec les créneaux vides de votre journée
  habituelle et des propositions tirées de vos habitudes, du planning et des sessions de Claude, à confirmer d'un
  geste (ou une par une, avec « Pourquoi ce bloc ») ; glisser pour créer ou ajuster une entrée, raccourcis clavier,
  sept derniers jours en anneaux (26 octobre 2026).
- Paramètres : **Apparence**, comme le système (par défaut), claire ou sombre, réglée sur chaque appareil
  (26 octobre 2026).
- Aujourd'hui : **Saisie express**, une ligne en clair (« 1h20 point hebdo interne », « 9h-10h30 maquettes hier »)
  devient une entrée, rangée dans le premier créneau vide assez grand, avec un aperçu de ce qui a été compris
  (26 octobre 2026).
- Suivi du temps : la **description** et le **projet** d'une entrée se modifient sur place, d'un clic ; Entrée
  enregistre, Échap abandonne, et le bandeau propose Annuler (26 octobre 2026).
- **Commandes (⌘K / Ctrl K)**, ou la loupe en haut : pages, démarrer ou arrêter le chronomètre, nouvelle entrée,
  dernières entrées à reprendre, démarrer sur un projet, apparence ; recherche sans accents (27 octobre 2026).
- **Raccourcis clavier** : N nouvelle entrée, S chronomètre, ⌘Z annuler, ? l'aide ; dans « Suivi du temps », J / K,
  X sélectionner, E modifier, D dupliquer, ⌫ supprimer, Échap (27 octobre 2026).
- Suivi du temps : **sélection multiple** (case au survol, appui long sur téléphone) et barre d'actions : projet,
  facturable ou non, dupliquer vers un autre jour, supprimer, avec Annuler (27 octobre 2026).
- Mac : la **saisie express** dans le panneau de la barre de menus, avec aperçu ; ⌥⌘T l'ouvre depuis n'importe
  quelle application (27 octobre 2026).
- Paramètres : **Ma journée type** (arrivée, pause, départ), pour les créneaux vides d'« Aujourd'hui » ; sans
  réglage, elle reste déduite de vos semaines passées (27 octobre 2026).
- **Voir la journée** : depuis « Suivi du temps » (le soleil à côté du jour) ou un jour du calendrier, la journée
  s'ouvre sur la frise d'« Aujourd'hui » (27 octobre 2026).
- Aujourd'hui : vos **réunions** (agenda relié par son adresse iCal privée, dans Paramètres › Intégrations ›
  Agenda) et vos **commits** deviennent des propositions, avec une ligne « Traces » sur la frise
  (27 octobre 2026).
- **Semaine** : trois vues de la même semaine (grille, calendrier, liste) ; heures prévues au planning en
  italique dans la grille, **Compléter d'après le planning**, **Copier la semaine précédente**, et **Avant de
  soumettre**, la liste de ce qui mérite un coup d'œil (27 octobre 2026).
- **Fin de journée** : à l'heure choisie (17:30 par défaut), le temps saisi et les propositions restantes, à
  confirmer d'un geste ; bandeau dans l'app, notification et ligne dans la barre de menus sur Mac, notification
  sur téléphone. Réglage dans Paramètres (27 octobre 2026).
- **Demander à Clockifai** (⌘J) : questions en clair sur le temps passé, réponses de Claude à partir de vos totaux
  (jamais vos descriptions), corrections proposées en aperçu puis appliquées d'un clic. Facultatif : s'active avec
  une clé d'API Anthropic dans `deploy/.env` (27 octobre 2026).
- Rapports : **questions toutes faites** (le temps de la semaine, par client ce mois-ci, qui a fait quoi, usage IA
  au coût), **comparaison** avec la période précédente, et **À facturer** : le temps non facturé par client, facturé
  d'un clic (27 octobre 2026).
- Approbations : **Semaine dernière**, qui n'a pas soumis sa feuille (heures saisies et prévues), et **Relancer** :
  un bandeau et une notification chez la personne ; l'**écart au planning** sous chaque feuille soumise
  (27 octobre 2026).
- **Téléphone** : « Comme vendredi » recopie la dernière journée travaillée sur une journée vide ; dictée de la
  saisie express (micro) ; durée au pouce (±15 min, 30 min à 4 h, matin, après-midi) et tâches en pastilles dans
  une entrée ; glisser une ligne pour la dupliquer sur aujourd'hui ou la supprimer ; nombre de modifications en
  attente sur l'icône de synchronisation (27 octobre 2026).
- **Présence chantier** (téléphone, réglage personnel) : le téléphone note l'arrivée et le départ sur un chantier
  placé par un manager (position du projet), et « Aujourd'hui » propose la journée, à confirmer ; heures détectées
  ou calées sur la journée type selon la règle de l'entreprise. La position reste sur le téléphone
  (27 octobre 2026).
- **Pointage d'équipe** : présents cochés d'office, absences validées exclues, journée déjà saisie décochée ;
  exceptions « Arrivée à… », « Départ à… » ; Annuler après la création (27 octobre 2026).

### Modifié

- **Apparence** : fond légèrement teinté et cartes au premier plan, coins et couleurs d'état harmonisés (vert
  « réussi » et orange lisibles aussi en sombre), menu plus serré sur ordinateur, bandeaux flottants ; sur
  téléphone, la frise d'« Aujourd'hui » ne superpose plus les heures (27 octobre 2026).
- **Aujourd'hui** devient l'écran d'accueil ; « Suivi du temps » reste la liste complète des entrées
  (27 octobre 2026).
- Suivi du temps : les durées et les totaux s'affichent à la minute (« 3:00 » au lieu de « 3:00:00 ») ; les
  secondes restent pour un chronomètre en cours (26 octobre 2026).
- **Annuler plutôt que confirmer** : supprimer une entrée ou un groupe d'entrées, abandonner un chronomètre,
  supprimer un projet, un client ou un tag se fait sans « Êtes-vous sûr ? » ; le bandeau propose Annuler pendant
  8 secondes, même si la suppression a déjà été synchronisée (26 octobre 2026).

### Corrigé

- Aujourd'hui : un jour de changement d'heure, la frise et les anneaux de la semaine décalaient les heures d'une
  heure (26 octobre 2026).
- Aujourd'hui : le bandeau « Annuler » restait affiché jusqu'à un clic (26 octobre 2026).

## [0.2.2] — 2026-10-26

### Ajouté

- Claude Code : **usage IA** de chaque entrée de l'agent, lu sur le poste dans la transcription (jamais le texte
  des messages) : tokens traités et coût estimé au tarif de l'API d'Anthropic, en dollars, sur la ligne de
  l'entrée, détaillé par modèle et effort dans sa fenêtre, totalisé dans les rapports (« Coût IA estimé ») et sur
  la fiche de l'agent ; colonnes « Tokens IA » et « Coût IA estimé (USD) » dans les exports (26 octobre 2026).
  Mettre à jour le plugin sur chaque poste (`claude plugin marketplace update clockifai`, puis
  `claude plugin update clockifai@clockifai`).

### Modifié

- Guide utilisateur : la vidéo 6 (Claude Code) montre l'usage IA, sur la fiche de l'agent, dans les rapports et
  dans la fenêtre d'une entrée de Claude (26 octobre 2026).

## [0.2.1] — 2026-10-26

### Ajouté

- Factures : **Détailler par tâche** à la création, une ligne « Projet — Tâche » par tâche, le temps sans
  tâche restant sur la ligne du projet (25 octobre 2026).
- Changer le taux horaire d'un projet ou d'une personne propose de l'appliquer aux entrées pas encore
  facturées qui ont gardé un autre taux (« Appliquer le nouveau taux ? ») (25 octobre 2026).
- Guide utilisateur : sixième vidéo, **Claude Code**, sur la page Membre (connecter un poste, une session en
  direct, les tâches de Claude, contrôler, corriger et facturer le temps de son agent) (26 octobre 2026).

### Modifié

- Rapports, vue **Détaillé** : les entrées jour par jour, avec le total de chaque journée ; les entrées
  similaires d'une journée (même personne, description, projet, tâche, tags, facturation) tiennent sur une
  ligne dépliable (25 octobre 2026).
- Factures : **Détailler par tâche** est coché par défaut (25 octobre 2026).

### Corrigé

- Une entrée saisie avant que son projet ou la personne ait un taux horaire prend le taux actuel dans les
  factures, les rapports et les exports, au lieu de sortir à 0 sur une ligne à part (25 octobre 2026).

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
  rappelle les commandes. « Nouvelle tâche », dans la fenêtre d'une entrée, crée une tâche pour la session de
  Claude, que la session garde quand elle reprend ; « Toujours rattacher ce dépôt » ne retient plus que le projet.
  Claude nomme lui-même la tâche de son travail dès qu'il sait sur quoi il porte (outil Clockifai du plugin, à
  autoriser la première fois) ; un nom précisé juste après renomme la tâche au lieu d'en créer une autre. Le
  réglage « Tâches de Claude » (Paramètres › Intégrations › Claude Code) choisit une tâche par sujet, une tâche
  par session Claude Code, ou pas de tâche.

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
