// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get account => 'Compte';

  @override
  String get activate => 'Réactiver';

  @override
  String get addHoliday => 'Ajouter un jour férié';

  @override
  String get addLine => 'Ajouter une ligne';

  @override
  String get addManualEntry => 'Ajouter une entrée';

  @override
  String get addRow => 'Ajouter une ligne';

  @override
  String get addTags => 'Ajouter des tags';

  @override
  String get addTask => 'Ajouter une tâche';

  @override
  String get addTimeForOthers => 'Ajouter du temps pour d\'autres';

  @override
  String get adminOnlySettings =>
      'Seuls les administrateurs peuvent modifier ces réglages.';

  @override
  String get agentBadge => 'Agent';

  @override
  String get agentBillableHelp =>
      'Pour les sessions de Claude Code rattachées à ce projet';

  @override
  String get agentBillableWorkspace => 'Comme le réglage du workspace';

  @override
  String get agentBilling => 'Temps des agents Claude';

  @override
  String get agentBillingHelp =>
      'Facturable ou non quand Claude Code enregistre une session ; un projet peut faire exception. Les entrées déjà enregistrées ne changent pas';

  @override
  String get agentBillingLikeHumans =>
      'Facturable comme le temps des personnes';

  @override
  String get agentBillingNever => 'Jamais facturable';

  @override
  String get agentCardLink => 'Voir sa fiche dans l\'équipe';

  @override
  String get agentInactive =>
      'Votre agent a été désactivé ou retiré par un administrateur : vos sessions Claude Code ne produisent plus de temps.';

  @override
  String get agentRestored =>
      'Agent restauré : les sessions Claude Code de son pilote produisent de nouveau du temps.';

  @override
  String get agents => 'Agents';

  @override
  String get agentsHelp =>
      'Agents Claude : leur temps est enregistré par Claude Code, un agent par personne qui a connecté un poste (Paramètres › Intégrations).';

  @override
  String get quickEntry => 'Saisie express';

  @override
  String get quickEntryHint =>
      'Ce que vous avez fait, en clair : « 1h20 point hebdo interne »';

  @override
  String get quickEntryTry => 'Essayer :';

  @override
  String get quickEntryHelp =>
      'Durée (1h20, 45min) ou plage (9h-10h30), jour (hier, vendredi), projet ou tâche, #tag, « non facturable » : dans n’importe quel ordre. Entrée pour enregistrer, Échap pour effacer.';

  @override
  String get quickDurationMissing => 'durée ?';

  @override
  String get quickProjectMissing => 'projet ?';

  @override
  String get quickInGap => 'dans un créneau vide';

  @override
  String quickAdded(String description, String day, String range) {
    return 'Ajouté : $description · $day, $range';
  }

  @override
  String get appearance => 'Apparence';

  @override
  String get appearanceSystem => 'Comme le système';

  @override
  String get appearanceLight => 'Claire';

  @override
  String get appearanceDark => 'Sombre';

  @override
  String get journalHeroPending => 'Votre journée est presque prête';

  @override
  String journalHeroPendingText(String total, String proposed, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count propositions à confirmer',
      one: '1 proposition à confirmer',
    );
    return '$total reconstituées, dont $proposed proposées : $_temp0.';
  }

  @override
  String get journalHeroGaps => 'Il reste des créneaux vides';

  @override
  String get journalHeroGapsText =>
      'Touchez un créneau en pointillé pour le remplir, ou glissez sur la ligne « Vous ».';

  @override
  String get journalHeroDone => 'Journée complète';

  @override
  String journalHeroDoneText(String total) {
    return '$total saisies, rien à confirmer.';
  }

  @override
  String get journalHeroNothing => 'Rien à proposer pour ce jour';

  @override
  String journalHeroNothingText(String total) {
    return '$total saisies.';
  }

  @override
  String journalConfirmAll(int count) {
    return 'Tout confirmer · $count';
  }

  @override
  String get journalReviewOne => 'Revoir une par une';

  @override
  String get journalYou => 'Vous';

  @override
  String journalToFill(String duration) {
    return '$duration à saisir';
  }

  @override
  String get journalHint =>
      'Glisser sur le vide : créer · tirer un bord ou le bloc : ajuster · Entrée : confirmer · Retour arrière : ignorer · flèches : décaler';

  @override
  String get journalProposed => 'Proposé par Clockifai';

  @override
  String get journalSourceClaude => 'Pendant une session de Claude';

  @override
  String get journalSourceHabit => 'Habitude';

  @override
  String get journalSourcePlanning => 'Planning';

  @override
  String get journalLogged => 'Saisi';

  @override
  String get journalRunning => 'En cours';

  @override
  String get journalNew => 'Nouvelle entrée';

  @override
  String get journalWhy => 'Pourquoi ce bloc';

  @override
  String journalReasonClaudeSession(String start, String end) {
    return 'Claude travaillait sur ce projet de $start à $end';
  }

  @override
  String get journalReasonClaudePilot =>
      'Le temps de suivre sa session et de relire son travail';

  @override
  String journalReasonHabitWeekday(int count, int of, String time) {
    return 'Habitude : $count fois sur les $of dernières semaines, le même jour, vers $time';
  }

  @override
  String journalReasonHabitDaily(int count, int of, String time) {
    return 'Habitude : $count jours sur les $of derniers jours travaillés, vers $time';
  }

  @override
  String journalReasonPlanned(String duration) {
    return 'Planning : $duration prévues sur ce projet';
  }

  @override
  String journalReasonAlreadyLogged(String duration) {
    return 'Déjà saisi sur ce projet aujourd’hui : $duration';
  }

  @override
  String get journalReasonNew =>
      'Créé sur la frise : choisissez le projet, puis enregistrez.';

  @override
  String get journalPrivacy =>
      'Rien de vos fichiers ni de vos messages : seulement des heures, vos entrées passées, le planning et les sessions de Claude.';

  @override
  String get journalConfirm => 'Confirmer';

  @override
  String get journalIgnore => 'Ignorer';

  @override
  String get journalEditEntry => 'Modifier…';

  @override
  String journalAdded(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées ajoutées',
      one: '1 entrée ajoutée',
    );
    return '$_temp0 · $duration';
  }

  @override
  String get journalIgnored => 'Proposition ignorée';

  @override
  String get journalSummary => 'Bilan du jour';

  @override
  String get journalConfirmed => 'Confirmé';

  @override
  String get journalToConfirm => 'À confirmer';

  @override
  String journalTarget(String duration) {
    return 'sur $duration';
  }

  @override
  String journalTypicalDay(String start, String end) {
    return 'Journée type : $start – $end, d’après vos semaines passées';
  }

  @override
  String journalTypicalDefault(String start, String end) {
    return 'Journée type par défaut : $start – $end';
  }

  @override
  String get journalDescriptionHint => 'Qu’avez-vous fait ?';

  @override
  String journalDayRing(String day, int percent) {
    return '$day : $percent % saisi';
  }

  @override
  String get journalBackToToday => 'Revenir à aujourd’hui';

  @override
  String get aiUsage => 'Usage IA';

  @override
  String get aiUsageHelp =>
      'Tokens consommés par Claude et coût estimé au tarif de l\'API d\'Anthropic, en dollars US. Avec un abonnement Claude (Pro, Max), ce n\'est pas une dépense réelle.';

  @override
  String aiTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String get aiCostEstimated => 'Coût IA estimé';

  @override
  String aiRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count appels',
      one: '1 appel',
    );
    return '$_temp0';
  }

  @override
  String aiUsageBreakdown(
    String input,
    String output,
    String written,
    String read,
  ) {
    return 'Entrée $input · sortie $output · cache écrit $written · cache lu $read';
  }

  @override
  String get aiUnknownPrice => 'tarif inconnu';

  @override
  String get aiFastMode => 'mode rapide';

  @override
  String aiEffort(String level) {
    return 'effort $level';
  }

  @override
  String get agentsWorking => 'Claude travaille';

  @override
  String get agentsWorkingHelp =>
      'Sessions Claude Code en cours de votre agent. Sans activité pendant 10 minutes, une session se clôt à l\'heure de sa dernière action. Touchez une session pour changer son projet, lui créer une tâche ou changer sa description.';

  @override
  String agentTimeOf(String name) {
    return 'Temps de $name : vous pouvez corriger ses entrées, pas en ajouter.';
  }

  @override
  String get allClients => 'Tous les clients';

  @override
  String get allMembers => 'Tous les membres';

  @override
  String get allProjects => 'Tous les projets';

  @override
  String get allowance => 'Droit annuel';

  @override
  String allowanceOverrideHelp(String value) {
    return 'Laisser vide pour appliquer le droit de la politique ($value).';
  }

  @override
  String get alwaysAttachRepo => 'Toujours rattacher ce dépôt à ce projet';

  @override
  String get alwaysAttachRepoHelp =>
      'Les prochaines sessions de Claude dans ce dépôt iront dans ce projet, sans tâche, et ses entrées sans projet de la semaine aussi.';

  @override
  String get amount => 'Montant';

  @override
  String get annualAllowance => 'Droit annuel';

  @override
  String apiTokenCreated(String name) {
    return 'Jeton créé pour « $name ». Il ne sera plus affiché : suivez ces étapes maintenant.';
  }

  @override
  String get apply => 'Appliquer';

  @override
  String get applyRateApply => 'Appliquer';

  @override
  String applyRateBody(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées non facturées ont gardé un autre taux.',
      one: '1 entrée non facturée a gardé un autre taux.',
    );
    return '$_temp0 Le nouveau taux vaut pour les nouvelles entrées ; l\'appliquer aussi à celles-ci ?';
  }

  @override
  String get applyRateKeep => 'Seulement les nouvelles';

  @override
  String get applyRateTitle => 'Appliquer le nouveau taux ?';

  @override
  String applyRounding(int minutes) {
    return 'Arrondi $minutes min';
  }

  @override
  String get attendance => 'Présence';

  @override
  String get attendanceHelp =>
      'Tout le temps de chaque personne, quels que soient le projet et le client. Prévu : la capacité journalière des jours ouvrés, hors jours fériés et absences approuvées.';

  @override
  String get attendanceArrival => 'Arrivée';

  @override
  String get attendanceDeparture => 'Départ';

  @override
  String get attendanceBreaks => 'Pauses';

  @override
  String get attendanceWorked => 'Travaillé';

  @override
  String get attendanceExpected => 'Prévu';

  @override
  String get attendanceDifference => 'Écart';

  @override
  String attendanceOvertime(String time) {
    return 'Heures sup : $time';
  }

  @override
  String attendanceMissing(String time) {
    return 'Manque : $time';
  }

  @override
  String get attendanceHoliday => 'Férié';

  @override
  String get attendanceTimeOff => 'Absence';

  @override
  String get exportAttendanceCsv => 'Présence (CSV)';

  @override
  String get sharedReports => 'Rapports partagés';

  @override
  String get sharedReportsHelp =>
      'Un lien en lecture seule, sans compte, pour un client ou un comptable. La période se recalcule à chaque ouverture ; le lien cesse de fonctionner si son auteur n\'est plus manager.';

  @override
  String get noSharedReports => 'Aucun rapport partagé pour l\'instant.';

  @override
  String get shareThisReport => 'Partager ce rapport';

  @override
  String get sharedReportName => 'Nom du rapport';

  @override
  String get sharedReportNameHint => 'ex. Site vitrine — ACME';

  @override
  String sharedReportPeriod(String period) {
    return 'Période : $period, avec les filtres affichés.';
  }

  @override
  String get sharedDetailed =>
      'Avec le détail des entrées (descriptions comprises)';

  @override
  String get sharedDetailedShort => 'détail des entrées';

  @override
  String get sharedAmounts => 'Avec les montants';

  @override
  String get sharedPublicLink => 'Lien public';

  @override
  String get sharedPublicLinkHelp =>
      'Toute personne qui a le lien lit le rapport.';

  @override
  String get sharedLinkOff => 'lien fermé';

  @override
  String get sharedLinkOpen => 'Ouvrir le lien public';

  @override
  String get sharedLinkClose => 'Fermer le lien public';

  @override
  String get sharedNewLink => 'Changer de lien (l\'ancien ne marchera plus)';

  @override
  String get deleteSharedReport => 'Supprimer le rapport partagé ?';

  @override
  String get deleteSharedReportMessage => 'Son lien ne fonctionnera plus.';

  @override
  String get open => 'Ouvrir';

  @override
  String get sharedSchedule => 'Envoi par email';

  @override
  String get sharedScheduleNone => 'Jamais';

  @override
  String get sharedScheduleWeekly => 'Chaque semaine (la semaine passée)';

  @override
  String get sharedScheduleMonthly => 'Chaque mois (le mois passé)';

  @override
  String get sharedScheduleHelp =>
      'À 8 h le premier jour de la semaine ou du mois, avec le PDF en pièce jointe. Le premier envoi couvre la période en cours, une fois finie.';

  @override
  String get sharedNoMail =>
      'Pas de serveur d\'envoi d\'emails sur cette installation.';

  @override
  String get sharedRecipients => 'Destinataires';

  @override
  String get sharedRecipientsHint => 'adresses séparées par des virgules';

  @override
  String get sharedWeeklyShort => 'chaque semaine';

  @override
  String get sharedMonthlyShort => 'chaque mois';

  @override
  String sharedRecipientsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count destinataires',
      one: '1 destinataire',
    );
    return '$_temp0';
  }

  @override
  String get sharedEditSchedule => 'Envoi par email…';

  @override
  String get approvals => 'Approbations';

  @override
  String get approve => 'Approuver';

  @override
  String approvedPeriodFor(String name) {
    return 'Période déjà approuvée pour $name.';
  }

  @override
  String get approvers => 'Approbateurs';

  @override
  String get approversManagers => 'Managers';

  @override
  String get approversManagersAndTeamManagers => 'Managers et chefs d\'équipe';

  @override
  String get archive => 'Archiver';

  @override
  String get archived => 'Archivé';

  @override
  String get autoStopTimers => 'Arrêt automatique des chronomètres';

  @override
  String get autoStopTimersHelp =>
      'Arrête les chronomètres oubliés après cette durée';

  @override
  String balancesFor(int year) {
    return 'Mes soldes $year';
  }

  @override
  String get billable => 'Facturable';

  @override
  String get billableAndNot => 'Facturable ou non';

  @override
  String get billableByDefault => 'Facturable par défaut';

  @override
  String get billableRate => 'Taux facturable (par heure)';

  @override
  String get billableTime => 'Temps facturable';

  @override
  String get billing => 'Facturation';

  @override
  String get billingAddress => 'Adresse de facturation';

  @override
  String get billingEmail => 'Email de facturation';

  @override
  String get budgetHours => 'Budget (heures)';

  @override
  String get budgetAmount => 'Budget (montant)';

  @override
  String budgetAmountUsed(int percent, String amount) {
    return '$percent % du budget de $amount';
  }

  @override
  String get editTask => 'Modifier la tâche';

  @override
  String get estimate => 'Estimation';

  @override
  String get estimateHint => 'ex. 4h, 1:30, 2,5';

  @override
  String estimateUsed(String used, String estimate) {
    return '$used sur $estimate estimées';
  }

  @override
  String get watchList => 'À surveiller';

  @override
  String get watchListHelp =>
      'Projets et tâches à 80 % ou plus de leur budget ou de leur estimation. Les managers reçoivent aussi un email à 80 % puis à 100 %.';

  @override
  String watchHours(int percent, String used, String budget) {
    return '$percent % du budget en heures ($used sur $budget)';
  }

  @override
  String watchAmount(int percent, String used, String budget) {
    return '$percent % du budget en montant ($used sur $budget)';
  }

  @override
  String watchEstimate(int percent, String used, String budget) {
    return '$percent % de l\'estimation ($used sur $budget)';
  }

  @override
  String budgetUsed(int percent, int hours) {
    return '$percent % du budget de $hours h';
  }

  @override
  String get calendar => 'Calendrier';

  @override
  String get cancel => 'Annuler';

  @override
  String get cancelRequest => 'Annuler la demande';

  @override
  String cannotOpenLink(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String changeRejected(String message) {
    return 'Modification refusée par le serveur : $message';
  }

  @override
  String get changeRejectedPermission =>
      'Modification refusée : droits insuffisants ou période verrouillée. Elle a été annulée.';

  @override
  String get checkYourEmail =>
      'Vérifiez votre boîte mail pour confirmer votre compte.';

  @override
  String claudeCodeHelp(String agent) {
    return 'Le temps de vos sessions Claude Code, au nom de votre agent « $agent »';
  }

  @override
  String claudeCodeIntro(String agent) {
    return 'Chaque session de Claude Code devient du temps de votre agent « $agent », membre de l\'équipe : un chronomètre démarre au premier prompt et s\'arrête après 10 minutes sans activité, à l\'heure de la dernière activité. Connectez chaque poste où vous utilisez Claude Code (terminal, VSCode, app de bureau).';
  }

  @override
  String get claudeCodeLocalInstance =>
      'Instance locale : Claude Code n\'accepte une marketplace qu\'en https, celle-ci est donc le dossier integrations/ de votre copie du dépôt.';

  @override
  String get claudeCodeRequirements =>
      'Il faut aussi python3 (sur Mac, les outils de développement : xcode-select --install).';

  @override
  String get claudeCodeStepCli =>
      '1. Dans un terminal, claude --version doit afficher un numéro de version. Sinon, installez Claude Code en ligne de commande (l\'extension VSCode embarque sa propre copie, absente du terminal), puis ouvrez un nouveau terminal :';

  @override
  String get claudeCodeStepInstall =>
      '2. Dans un terminal (le panneau Claude Code de VSCode ne propose pas /plugin) :';

  @override
  String get claudeCodeStepStart =>
      '4. Ouvrez une nouvelle conversation Claude Code : le chronomètre de Claude démarre au premier prompt. Claude nomme la tâche de chaque sujet : à la première demande, autorisez l\'outil Clockifai.';

  @override
  String get claudeCodeStepToken =>
      '3. Collez cette commande dans le terminal, sans appuyer sur Entrée :';

  @override
  String get claudeCodeStepTokenReconnect =>
      '3. Le jeton ne s\'affiche qu\'à la connexion d\'un poste : s\'il manque sur ce poste, touchez Reconnecter sur sa ligne, dans la liste ci-dessous.';

  @override
  String get claudeCodeStepTokenThen =>
      'Touchez Copier le jeton, puis appuyez sur Entrée dans le terminal : la commande lit le jeton dans le presse-papiers. Dans l\'autre ordre, copier la commande remplacerait le jeton.';

  @override
  String get claudeTasks => 'Tâches de Claude';

  @override
  String get claudeTasksHelp =>
      'Claude nomme l\'objectif de son travail (une tâche, par exemple le plan en cours) et chaque étape (une sous-tâche) : le temps de vos sessions y est rangé, dans le projet du dépôt. Un nom plus précis renomme au lieu d\'en créer un autre ; une tâche que vous choisissez reste.';

  @override
  String get claudeTasksOff => 'Pas de tâche : le projet seulement';

  @override
  String get claudeTasksSession => 'Une tâche par session Claude Code';

  @override
  String get claudeTasksSubject =>
      'Une tâche par objectif, une sous-tâche par étape';

  @override
  String get client => 'Client';

  @override
  String get clients => 'Clients';

  @override
  String get close => 'Fermer';

  @override
  String get color => 'Couleur';

  @override
  String get companyDetails => 'Coordonnées (adresse, SIRET, TVA…)';

  @override
  String get companyDetailsHint => 'Affichées en en-tête des factures';

  @override
  String get companyName => 'Raison sociale';

  @override
  String get computerName => 'Nom du poste';

  @override
  String get confirm => 'Confirmer';

  @override
  String get connectComputer => 'Connecter un poste';

  @override
  String get connectedComputers => 'Postes connectés';

  @override
  String get connection => 'Connexion';

  @override
  String get continueEntry => 'Continuer';

  @override
  String get copied => 'Copié.';

  @override
  String get copy => 'Copier';

  @override
  String get copyToken => 'Copier le jeton';

  @override
  String get costRate => 'Coût (par heure)';

  @override
  String get createAccount => 'Créer mon compte';

  @override
  String get createEntries => 'Créer les entrées';

  @override
  String get createProject => 'Créer un projet';

  @override
  String createTagNamed(String name) {
    return 'Créer le tag « $name »';
  }

  @override
  String get createTask => 'Créer une tâche';

  @override
  String createTaskIn(String name) {
    return 'Créer la tâche « $name » dans :';
  }

  @override
  String get createWorkspace => 'Créer un workspace';

  @override
  String get currency => 'Devise';

  @override
  String get currencyOverride => 'Devise spécifique (facultatif)';

  @override
  String get customRange => 'Période personnalisée';

  @override
  String get date => 'Date';

  @override
  String get day => 'Jour';

  @override
  String get days => 'Jours';

  @override
  String get daysRequested => 'Nombre de jours';

  @override
  String get daysShort => 'j';

  @override
  String get deactivate => 'Désactiver';

  @override
  String get decision => 'Décision';

  @override
  String get defaultHours => 'Horaires par défaut';

  @override
  String get delete => 'Supprimer';

  @override
  String get deleteGroup => 'Supprimer le groupe';

  @override
  String get deleteGroupMessage =>
      'Les membres restent dans le workspace ; les chefs d\'équipe n\'encadrent plus ce groupe.';

  @override
  String get deleteInvoice => 'Supprimer la facture ?';

  @override
  String get deleteInvoiceMessage =>
      'Les entrées de temps redeviennent facturables.';

  @override
  String get deletePolicy => 'Supprimer la politique ?';

  @override
  String deleteSimilarEntries(int count) {
    return 'Supprimer les $count entrées';
  }

  @override
  String get undo => 'Annuler';

  @override
  String get presenceTitle => 'Présence chantier';

  @override
  String get presenceHelp =>
      'Ce téléphone note votre arrivée et votre départ sur les chantiers ; Aujourd\'hui vous les propose, à confirmer. Votre position reste sur le téléphone : seules les heures servent.';

  @override
  String get presenceOn => 'Présence chantier activée sur ce téléphone.';

  @override
  String get presenceDenied =>
      'Accès à la position refusé : autorisez-le dans les réglages du téléphone.';

  @override
  String get presenceServiceOff =>
      'Localisation indisponible : activez-la sur l\'appareil.';

  @override
  String get presenceForget => 'Oublier les heures notées';

  @override
  String get presenceForgotten =>
      'Heures de présence effacées de ce téléphone.';

  @override
  String get presenceNotification =>
      'Présence chantier : arrivée et départ notés sur ce téléphone';

  @override
  String get presenceRounding => 'Heures de présence chantier';

  @override
  String get presenceRoundingHelp =>
      'Ce que proposent les téléphones des personnes qui ont activé la présence chantier.';

  @override
  String get presenceRoundingActual =>
      'Telles que détectées (à 5 minutes près)';

  @override
  String get presenceRoundingPlanning =>
      'Calées sur la journée type, à moins de 30 minutes';

  @override
  String get sitePosition => 'Position du chantier';

  @override
  String get sitePositionHelp =>
      'Latitude et longitude, copiées d\'une carte, ou « Ici » sur place. Sert à la présence chantier.';

  @override
  String get sitePositionInvalid =>
      'Attendu : latitude, longitude (48.8566, 2.3522)';

  @override
  String get siteOnMap => 'Voir sur la carte';

  @override
  String get siteRadius => 'Rayon';

  @override
  String get siteHere => 'Ici';

  @override
  String get journalSourcePresence => 'Chantier';

  @override
  String journalReasonPresence(String from, String to) {
    return 'Sur le chantier de $from à $to, d\'après ce téléphone';
  }

  @override
  String journalReasonPresenceSince(String from) {
    return 'Sur le chantier depuis $from, d\'après ce téléphone';
  }

  @override
  String get journalReasonPresenceRounded =>
      'Heures calées sur votre journée type (règle de l\'entreprise)';

  @override
  String pendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications en attente',
      one: '1 modification en attente',
    );
    return '$_temp0';
  }

  @override
  String get dayNothingToCopy => 'Rien à copier de ce jour-là.';

  @override
  String get likeYesterday => 'Comme hier';

  @override
  String likeDay(String day) {
    return 'Comme $day';
  }

  @override
  String likeDate(String date) {
    return 'Comme le $date';
  }

  @override
  String get duplicateToday => 'Dupliquer sur aujourd\'hui';

  @override
  String get morning => 'Matin';

  @override
  String get afternoon => 'Après-midi';

  @override
  String get dictate => 'Dicter';

  @override
  String get dictationStop => 'Arrêter la dictée';

  @override
  String get dictationUnavailable =>
      'Dictée indisponible : micro refusé ou pas de reconnaissance vocale sur cet appareil.';

  @override
  String get teamAbsent => 'Absence validée';

  @override
  String get teamAbsentHalf => 'Absence validée (demi-journée)';

  @override
  String teamAlreadyLogged(String time) {
    return 'Déjà saisi : $time';
  }

  @override
  String leftAt(String time) {
    return 'Départ à $time';
  }

  @override
  String arrivedAt(String time) {
    return 'Arrivée à $time';
  }

  @override
  String get arrivedAtPick => 'Arrivée à…';

  @override
  String get leftAtPick => 'Départ à…';

  @override
  String get otherHours => 'Autres horaires…';

  @override
  String get commonHours => 'Horaires communs';

  @override
  String get teamException => 'Exception';

  @override
  String get lateTitle => 'Semaine dernière';

  @override
  String lateHelp(String date) {
    return 'Qui n\'a pas encore soumis sa feuille de temps de la semaine du $date.';
  }

  @override
  String get lateAllGood => 'Tout le monde a soumis sa semaine.';

  @override
  String lateLine(String logged, String planned) {
    return '$logged saisies sur $planned prévues';
  }

  @override
  String lateLineNoPlan(String logged) {
    return '$logged saisies';
  }

  @override
  String get lateNotSubmitted => 'Pas soumise';

  @override
  String get remind => 'Relancer';

  @override
  String get reminded => 'Relancé';

  @override
  String remindedSnack(String name) {
    return 'Relance envoyée à $name';
  }

  @override
  String get reminderTitle => 'Feuille de temps';

  @override
  String reminderBanner(String who, String date) {
    return '$who vous rappelle de soumettre votre semaine du $date';
  }

  @override
  String get reminderOpen => 'Ouvrir la feuille';

  @override
  String get reminderOk => 'OK';

  @override
  String plannedVsSubmitted(String planned, String delta) {
    return '$planned prévues · écart $delta';
  }

  @override
  String get reportQuestions => 'Questions :';

  @override
  String get qMyWeek => 'Mon temps cette semaine';

  @override
  String get qTeamWeek => 'Le temps de l\'équipe cette semaine';

  @override
  String get qClientsMonth => 'Par client, ce mois-ci';

  @override
  String get qWhoWhat => 'Qui a fait quoi cette semaine';

  @override
  String get qReadyToBill => 'Prêt à facturer';

  @override
  String get qAiCost => 'Usage IA au coût';

  @override
  String get qOvertime => 'Heures sup du mois';

  @override
  String get qCompare => 'Comparer à la période précédente';

  @override
  String qDelta(String delta) {
    return '$delta vs période précédente';
  }

  @override
  String qBefore(String duration) {
    return 'avant : $duration';
  }

  @override
  String get readyToBillTitle => 'À facturer';

  @override
  String get readyToBillHelp =>
      'Temps facturable pas encore facturé, par client, sur les douze derniers mois (arrondi du workspace appliqué).';

  @override
  String get readyToBillNone => 'Tout est facturé.';

  @override
  String readyToBillSince(String day) {
    return 'depuis $day';
  }

  @override
  String get invoiceNow => 'Facturer';

  @override
  String get assistantTitle => 'Demander à Clockifai';

  @override
  String assistantTooltip(String shortcut) {
    return 'Demander à Clockifai ($shortcut)';
  }

  @override
  String get assistantIntro =>
      'Posez une question sur votre temps : totaux par projet, client, jour ou personne, comparaisons, entrées à corriger. Seuls des totaux et les noms des projets partent vers Claude, jamais vos descriptions.';

  @override
  String get assistantHint =>
      'Combien d\'heures sur la boulangerie ce mois-ci ?';

  @override
  String get assistantExample1 =>
      'Combien d\'heures cette semaine, par projet ?';

  @override
  String get assistantExample2 =>
      'Qu\'est-ce qui reste facturable ce mois-ci, par client ?';

  @override
  String get assistantExample3 =>
      'Mes entrées sans projet de la semaine dernière ?';

  @override
  String get assistantThinking => 'Clockifai cherche…';

  @override
  String get assistantRefused => 'Je ne peux pas répondre à cette question.';

  @override
  String get assistantTooLong =>
      'Cette question demande trop d\'étapes : précisez-la.';

  @override
  String get assistantUnavailable =>
      'L\'assistant est injoignable pour le moment.';

  @override
  String get assistantRateLimited =>
      'Trop de questions : réessayez dans un moment.';

  @override
  String get assistantOffline => 'L\'assistant demande une connexion.';

  @override
  String assistantEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées',
      one: '1 entrée',
      zero: 'Aucune entrée',
    );
    return '$_temp0';
  }

  @override
  String get assistantPreview => 'Voir l\'aperçu';

  @override
  String get assistantApply => 'Appliquer';

  @override
  String get assistantApplied => 'Appliqué';

  @override
  String get kbAssistant => 'Demander à Clockifai';

  @override
  String get recapTitle => 'Fin de journée';

  @override
  String recapLine(String logged, String target, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count propositions à confirmer',
      one: '1 proposition à confirmer',
    );
    return '$logged saisies sur $target · $_temp0';
  }

  @override
  String recapLineDone(String logged, String target) {
    return '$logged saisies sur $target, rien à confirmer';
  }

  @override
  String get recapNothing => 'Rien à confirmer : votre journée est complète.';

  @override
  String get recapOpenDay => 'Voir la frise';

  @override
  String recapConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Confirmer $count entrées',
      one: 'Confirmer 1 entrée',
    );
    return '$_temp0';
  }

  @override
  String get recapLater => 'Plus tard';

  @override
  String get recapReview => 'Revoir';

  @override
  String get recapSetting => 'Récapitulatif de fin de journée';

  @override
  String get recapSettingHelp =>
      'Chaque jour ouvré, à l\'heure choisie : le temps saisi et les propositions à confirmer d\'un geste. Réglé sur chaque appareil.';

  @override
  String get recapOff => 'Désactivé';

  @override
  String recapAt(String time) {
    return 'À $time';
  }

  @override
  String get recapNotificationBody =>
      'Votre journée vous attend : vérifiez-la et confirmez les propositions.';

  @override
  String get weekGrid => 'Grille';

  @override
  String get weekList => 'Liste';

  @override
  String get weekCopyPrevious => 'Copier la semaine précédente';

  @override
  String get weekFillPlanning => 'Compléter d\'après le planning';

  @override
  String get weekNothingToCopy => 'Rien à copier de la semaine précédente.';

  @override
  String get weekNothingToFill =>
      'Rien à compléter : le planning est déjà couvert.';

  @override
  String weekFilled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées ajoutées d\'après le planning',
      one: '1 entrée ajoutée d\'après le planning',
    );
    return '$_temp0';
  }

  @override
  String get weekReviewTitle => 'Avant de soumettre';

  @override
  String get weekReviewAllGood =>
      'Tout est en ordre : chaque jour ouvré a son temps.';

  @override
  String get weekReviewFix => 'Corriger';

  @override
  String get weekReviewSubmit => 'Soumettre';

  @override
  String get weekReviewSubmitAnyway => 'Soumettre quand même';

  @override
  String issueEmptyDay(String day) {
    return '$day : aucun temps saisi';
  }

  @override
  String issueEmptyDayPlanned(String day, String planned) {
    return '$day : aucun temps saisi ($planned prévues)';
  }

  @override
  String issueBelowPlan(String day, String logged, String planned) {
    return '$day : $logged saisies sur $planned prévues';
  }

  @override
  String issueNoProject(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées sans projet',
      one: '1 entrée sans projet',
    );
    return '$_temp0';
  }

  @override
  String issueNoDescription(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées sans description',
      one: '1 entrée sans description',
    );
    return '$_temp0';
  }

  @override
  String issueRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chronomètres encore en cours',
      one: '1 chronomètre encore en cours',
    );
    return '$_temp0';
  }

  @override
  String issueOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chevauchements entre entrées',
      one: '1 chevauchement entre deux entrées',
    );
    return '$_temp0';
  }

  @override
  String get journalSourceCalendar => 'Agenda';

  @override
  String get journalSourceCommits => 'Commits';

  @override
  String journalReasonCalendar(String start, String end) {
    return 'Dans votre agenda, de $start à $end';
  }

  @override
  String journalReasonCommits(
    int count,
    String repository,
    String start,
    String end,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '1 commit',
    );
    return '$_temp0 dans $repository, de $start à $end';
  }

  @override
  String get journalTraces => 'Traces';

  @override
  String get calendarTitle => 'Agenda';

  @override
  String get calendarHelp =>
      'Collez l\'adresse iCal privée de votre agenda : Google Agenda, Paramètres de l\'agenda › « Adresse secrète au format iCal » ; Outlook, Paramètres › Calendrier › Calendriers partagés › Publier ; Apple, clic droit sur l\'agenda › Partager. Clockifai n\'en lit que l\'heure et le titre des événements, pour vous proposer vos réunions dans « Aujourd\'hui ».';

  @override
  String get calendarUrl => 'Adresse iCal privée';

  @override
  String get calendarNone => 'Aucun agenda relié';

  @override
  String calendarLinked(String host) {
    return 'Relié : $host';
  }

  @override
  String get calendarRemove => 'Retirer l\'agenda';

  @override
  String get calendarOffline => 'Réglable en ligne seulement.';

  @override
  String get calendarErrorHttps =>
      'L\'adresse doit commencer par https:// (ou webcal://).';

  @override
  String get calendarErrorHost =>
      'Cette adresse n\'est pas accessible depuis Internet.';

  @override
  String get calendarErrorUnreachable =>
      'Agenda injoignable : vérifiez l\'adresse.';

  @override
  String get calendarErrorFormat =>
      'Cette adresse ne donne pas un agenda iCal.';

  @override
  String get calendarErrorTooLarge => 'Agenda trop volumineux.';

  @override
  String journalTypicalProfile(String start, String end) {
    return 'Journée type : $start – $end, réglée dans vos paramètres';
  }

  @override
  String get myDay => 'Ma journée type';

  @override
  String get myDayHelp =>
      'Arrivée, pause et départ habituels : la page « Aujourd\'hui » s\'en sert pour les créneaux vides. Sans réglage, Clockifai les déduit de vos semaines passées.';

  @override
  String get myDayAuto => 'Automatique, d\'après vos semaines passées';

  @override
  String get myDayReset => 'Revenir à l\'automatique';

  @override
  String get myDayInvalid =>
      'Les heures doivent se suivre : arrivée, pause, départ.';

  @override
  String get dayStart => 'Arrivée';

  @override
  String get lunchStart => 'Début de pause';

  @override
  String get lunchEnd => 'Fin de pause';

  @override
  String get dayEnd => 'Départ';

  @override
  String get openDay => 'Voir la journée';

  @override
  String get commandPalette => 'Commandes';

  @override
  String commandPaletteTooltip(String shortcut) {
    return 'Commandes ($shortcut)';
  }

  @override
  String get keyEscape => 'Échap';

  @override
  String get commandPaletteHint => 'Une action, une page, un projet…';

  @override
  String get commandNoResult => 'Aucune commande';

  @override
  String get cmdGoTo => 'Aller à';

  @override
  String get cmdStartTimer => 'Démarrer le chronomètre';

  @override
  String get cmdStopTimer => 'Arrêter le chronomètre';

  @override
  String get cmdStartOnProject => 'Démarrer le chronomètre sur ce projet';

  @override
  String get cmdResume => 'Reprendre';

  @override
  String get cmdThemeDark => 'Apparence : sombre';

  @override
  String get cmdThemeLight => 'Apparence : claire';

  @override
  String get cmdThemeSystem => 'Apparence : comme le système';

  @override
  String get shortcutsTitle => 'Raccourcis clavier';

  @override
  String get shortcutsEverywhere => 'Partout';

  @override
  String get shortcutsHelp =>
      'Une touche seule agit quand vous n\'écrivez pas dans un champ.';

  @override
  String get kbPalette => 'Commandes : pages, chronomètre, projets';

  @override
  String get kbNewEntry => 'Nouvelle entrée';

  @override
  String get kbTimer => 'Démarrer ou arrêter le chronomètre';

  @override
  String get kbUndo => 'Annuler la dernière action';

  @override
  String get kbHelp => 'Cette aide';

  @override
  String get kbMove => 'Entrée suivante, précédente';

  @override
  String get kbSelect => 'Sélectionner';

  @override
  String get kbEdit => 'Modifier';

  @override
  String get kbDuplicate => 'Dupliquer';

  @override
  String get kbDelete => 'Supprimer (la sélection, sinon l\'entrée)';

  @override
  String get kbClear => 'Tout désélectionner';

  @override
  String get kbTodayConfirm => 'Confirmer le bloc choisi';

  @override
  String get kbTodayIgnore => 'Ignorer la proposition';

  @override
  String get kbTodayShift =>
      'Décaler de 5 minutes (Maj : allonger ou raccourcir)';

  @override
  String selectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '1 sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get selectEntry => 'Sélectionner';

  @override
  String get duplicateTo => 'Dupliquer vers…';

  @override
  String entriesUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées modifiées',
      one: '1 entrée modifiée',
    );
    return '$_temp0';
  }

  @override
  String entriesDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées dupliquées',
      one: '1 entrée dupliquée',
    );
    return '$_temp0';
  }

  @override
  String get entryDeleted => 'Entrée supprimée';

  @override
  String entriesDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées supprimées',
      one: '1 entrée supprimée',
    );
    return '$_temp0';
  }

  @override
  String get entryUpdated => 'Entrée modifiée';

  @override
  String get timerDiscarded =>
      'Chronomètre abandonné : le temps en cours n\'est pas enregistré';

  @override
  String clientDeleted(String name) {
    return 'Client « $name » supprimé ; ses projets restent, sans client';
  }

  @override
  String projectDeleted(String name) {
    return 'Projet « $name » supprimé ; ses entrées restent';
  }

  @override
  String tagDeleted(String name) {
    return 'Tag « $name » supprimé';
  }

  @override
  String get description => 'Description';

  @override
  String get descriptionRequired =>
      'Une description est obligatoire dans ce workspace.';

  @override
  String get detailed => 'Détaillé';

  @override
  String get discardTimer => 'Abandonner le chronomètre';

  @override
  String get discount => 'Remise';

  @override
  String get discountPercent => 'Remise';

  @override
  String get draftNumberPending => 'Brouillon';

  @override
  String get due => 'échéance';

  @override
  String get duplicate => 'Dupliquer';

  @override
  String get duration => 'Durée';

  @override
  String get edit => 'Modifier';

  @override
  String get editAssignment => 'Modifier l\'affectation';

  @override
  String get editClient => 'Modifier le client';

  @override
  String get editEntry => 'Modifier l\'entrée';

  @override
  String get editPolicy => 'Modifier la politique';

  @override
  String get editProject => 'Modifier le projet';

  @override
  String get editRates => 'Modifier les taux';

  @override
  String get editRatesAndCapacity => 'Taux et capacité';

  @override
  String get capacityPerDay => 'Capacité par jour ouvré';

  @override
  String get capacityPerDayHelp =>
      'Heures prévues du lundi au vendredi : Présence (heures sup) et Planning.';

  @override
  String editSimilarEntries(int count) {
    return 'Modifier les $count entrées';
  }

  @override
  String get editTag => 'Modifier le tag';

  @override
  String get editTimer => 'Modifier le chronomètre';

  @override
  String get email => 'Email';

  @override
  String get emailRequired => 'Saisissez votre adresse email.';

  @override
  String get emptyIsUnlimited => 'Vide = illimité';

  @override
  String get endTime => 'Fin';

  @override
  String get endTimeRequired => 'Indiquez une heure de fin.';

  @override
  String get endsNextDay => 'Se termine le lendemain.';

  @override
  String enteredBy(String name) {
    return 'saisi par $name';
  }

  @override
  String enteringFor(String name) {
    return 'Vous saisissez le temps de $name.';
  }

  @override
  String entriesCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées créées',
      one: '1 entrée créée',
    );
    return '$_temp0';
  }

  @override
  String get entryLocked =>
      'Entrée verrouillée : seule une personne administratrice peut la modifier.';

  @override
  String get environmentLocal => 'Version locale';

  @override
  String get environmentProduction => 'Production';

  @override
  String get export => 'Exporter';

  @override
  String get exportCsvOffline => 'CSV (hors ligne)';

  @override
  String get exportDone => 'Export téléchargé.';

  @override
  String exportFailed(String error) {
    return 'Échec de l\'export : $error';
  }

  @override
  String get firstSync => 'Première synchronisation en cours…';

  @override
  String get forgotPassword => 'Mot de passe oublié';

  @override
  String get generate => 'Générer';

  @override
  String get groupBy => 'Grouper par';

  @override
  String get groupMembers => 'Membres du groupe';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get groupSimilarEntries => 'Regrouper les entrées similaires';

  @override
  String get groupSimilarEntriesHelp =>
      'Suivi du temps : les entrées d\'une même journée avec la même description, le même projet, la même tâche, les mêmes tags et la même facturation sont réunies sur une ligne dépliable';

  @override
  String get groups => 'Groupes';

  @override
  String get halfDay => 'Demi-journée';

  @override
  String get help => 'Aide';

  @override
  String get hideInstallCommands => 'Masquer les commandes d\'installation';

  @override
  String get hideSimilarEntries => 'Masquer le détail';

  @override
  String get history => 'Historique';

  @override
  String get holidays => 'Jours fériés';

  @override
  String get hourlyRate => 'Taux horaire';

  @override
  String get hours => 'Heures';

  @override
  String get hoursPerDay => 'Heures par jour';

  @override
  String get hoursRequested => 'Nombre d\'heures';

  @override
  String get humans => 'Humains';

  @override
  String get humansAndAgents => 'Humains et agents';

  @override
  String get installCommandsTitle => 'Commandes d\'installation d\'un poste';

  @override
  String get integrations => 'Intégrations';

  @override
  String get invalidDuration => 'Durée invalide (exemples : 1:30, 1,5, 90m).';

  @override
  String get invalidHours => 'Nombre d\'heures invalide (entre 0 et 24).';

  @override
  String invitationFailed(String error) {
    return 'Invitation impossible : $error';
  }

  @override
  String get invitationSent => 'Invitation envoyée.';

  @override
  String get invite => 'Inviter';

  @override
  String get inviteHelp =>
      'Si la personne a déjà un compte, elle est ajoutée immédiatement. Sinon, un lien d\'invitation est créé.';

  @override
  String get inviteMember => 'Inviter un membre';

  @override
  String get invoice => 'Facture';

  @override
  String get invoiceByTask => 'Détailler par tâche';

  @override
  String get invoiceDraft => 'Brouillon';

  @override
  String get invoiceNote => 'Mentions / conditions';

  @override
  String get invoiceNoteHint =>
      'Conditions de paiement, IBAN… (Entrée pour enregistrer)';

  @override
  String get invoicePaid => 'Payée';

  @override
  String get invoicePrefix => 'Préfixe des numéros';

  @override
  String get invoiceSent => 'Envoyée';

  @override
  String get invoiceVoid => 'Annulée';

  @override
  String get invoices => 'Factures';

  @override
  String get kiosk => 'Kiosque';

  @override
  String kioskClockInAs(String name) {
    return 'Arrivée de $name';
  }

  @override
  String kioskClockOutAs(String name) {
    return 'Départ de $name';
  }

  @override
  String get kioskClockedIn => 'Pointage d\'arrivée enregistré.';

  @override
  String get kioskClockedOut => 'Pointage de départ enregistré.';

  @override
  String get kioskDevices => 'Appareils kiosque';

  @override
  String get kioskDevicesHelp =>
      'Tablettes partagées où l\'équipe pointe avec un code PIN';

  @override
  String get kioskExit => 'Quitter le mode kiosque';

  @override
  String kioskGoodbye(String name) {
    return 'Au revoir $name !';
  }

  @override
  String kioskHello(String name) {
    return 'Bonjour $name !';
  }

  @override
  String get kioskMode => 'Mode kiosque (tablette partagée)';

  @override
  String get kioskNoPin =>
      'Cette personne n\'a pas encore défini son code PIN (Paramètres > Code PIN kiosque).';

  @override
  String get kioskPin => 'Code PIN kiosque';

  @override
  String get kioskPinHelp => 'Pour pointer sur une tablette partagée';

  @override
  String get kioskPinInvalid => 'Le PIN doit contenir 4 à 8 chiffres.';

  @override
  String get kioskPinLabel => 'Nouveau PIN (4 à 8 chiffres)';

  @override
  String get kioskPinSaved => 'Code PIN enregistré.';

  @override
  String get kioskReset => 'Désassocier cet appareil';

  @override
  String get kioskResetMessage => 'Le jeton sera oublié sur cet appareil.';

  @override
  String get kioskSetupHelp =>
      'Collez le jeton d\'appareil créé par un administrateur dans Paramètres > Appareils kiosque.';

  @override
  String get kioskTapYourName => 'Touchez votre nom pour pointer';

  @override
  String get kioskToken => 'Jeton d\'appareil';

  @override
  String get kioskTokenInvalid => 'Jeton invalide ou révoqué.';

  @override
  String get kioskTokenOnce =>
      'Copiez ce jeton maintenant : il ne sera plus affiché. Saisissez-le sur la tablette en mode kiosque.';

  @override
  String get kioskTooManyAttempts =>
      'Trop d\'essais. Réessayez dans quelques minutes.';

  @override
  String get kioskWrongPin => 'Code PIN incorrect.';

  @override
  String get language => 'Langue';

  @override
  String lastEventHoursAgo(int hours) {
    return 'Dernier événement il y a $hours h';
  }

  @override
  String get lastEventJustNow => 'Dernier événement à l\'instant';

  @override
  String lastEventMinutesAgo(int minutes) {
    return 'Dernier événement il y a $minutes min';
  }

  @override
  String get lastEventNever => 'Aucun événement reçu';

  @override
  String lastEventOn(String date) {
    return 'Dernier événement le $date';
  }

  @override
  String get lastMonth => 'Mois dernier';

  @override
  String get lastSeen => 'Dernière activité';

  @override
  String get lastSync => 'Dernière synchronisation';

  @override
  String get lastWeek => 'Semaine dernière';

  @override
  String get launchAtLogin => 'Démarrer à l\'ouverture de session';

  @override
  String get launchAtLoginApproval =>
      'À autoriser dans Réglages Système > Général > Ouverture.';

  @override
  String get launchAtLoginHelp =>
      'Clockifai s\'ouvre dans la barre de menus, sans fenêtre.';

  @override
  String get loadMore => 'Afficher plus';

  @override
  String get lockEntriesBefore => 'Verrouiller les entrées antérieures au';

  @override
  String get lockEntriesNone => 'Aucun verrouillage';

  @override
  String get magicLinkSent => 'Lien de connexion envoyé par email.';

  @override
  String managedByLabel(String names) {
    return 'Chef d\'équipe : $names';
  }

  @override
  String get managersOnly => 'Réservé aux managers';

  @override
  String managesLabel(String names) {
    return 'Encadre : $names';
  }

  @override
  String get markDone => 'Marquer terminée';

  @override
  String get member => 'Membre';

  @override
  String get memberAllowances => 'Droits par membre';

  @override
  String memberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
      zero: 'Aucun membre',
    );
    return '$_temp0';
  }

  @override
  String get members => 'Membres';

  @override
  String get menuBarOpenApp => 'Ouvrir Clockifai';

  @override
  String get menuBarQuit => 'Quitter Clockifai';

  @override
  String get menuBarRecent => 'Récemment';

  @override
  String get menuBarSignIn =>
      'Connectez-vous dans la fenêtre Clockifai pour suivre votre temps.';

  @override
  String get more => 'Plus';

  @override
  String get myRequests => 'Mes demandes';

  @override
  String get name => 'Nom';

  @override
  String get never => 'Jamais';

  @override
  String get neverSeen => 'Jamais connecté';

  @override
  String get newAssignment => 'Nouvelle affectation';

  @override
  String get newClient => 'Nouveau client';

  @override
  String get newGroup => 'Nouveau groupe';

  @override
  String get newInvoice => 'Nouvelle facture';

  @override
  String get newInvoiceHelp =>
      'Une ligne par projet, ou par tâche si vous détaillez, est créée à partir du temps facturable non encore facturé du client sur la période. Une entrée saisie avant que son projet ait un taux prend le taux actuel. Chaque durée suit l\'arrondi du workspace.';

  @override
  String get newKioskDevice => 'Nouvel appareil';

  @override
  String get newPassword => 'Nouveau mot de passe (8 caractères min.)';

  @override
  String get newPolicy => 'Nouvelle politique';

  @override
  String get newProject => 'Nouveau projet';

  @override
  String get newTag => 'Nouveau tag';

  @override
  String get newTask => 'Nouvelle tâche';

  @override
  String newTaskIn(String project) {
    return 'Nouvelle tâche dans $project';
  }

  @override
  String get nextWeek => 'Semaine suivante';

  @override
  String get noApproval => 'Sans validation';

  @override
  String get noClient => 'Sans client';

  @override
  String get noClients => 'Aucun client';

  @override
  String get noConnectedComputers => 'Aucun poste connecté.';

  @override
  String get noDataForPeriod => 'Aucune donnée sur cette période';

  @override
  String get noDescription => '(sans description)';

  @override
  String get noEntriesInPeriod => 'Aucune entrée sur la période';

  @override
  String get noEntriesYet => 'Aucune entrée pour l\'instant';

  @override
  String get noEntriesYetMessage =>
      'Démarrez le chronomètre ci-dessus ou ajoutez du temps manuellement.';

  @override
  String get noGroups => 'Aucun groupe';

  @override
  String get noGroupsMessage =>
      'Regroupez les membres (équipe, chantier, entreprise) pour les confier à un chef d\'équipe.';

  @override
  String get noHistory => 'Aucun historique';

  @override
  String get noHolidays => 'Aucun jour férié';

  @override
  String get noInvoices => 'Aucune facture';

  @override
  String get noInvoicesMessage =>
      'Générez une facture à partir du temps facturable d\'un client.';

  @override
  String get noMatch => 'Aucun résultat';

  @override
  String get noMembers => 'Aucun membre';

  @override
  String get noPoliciesYet => 'Aucun type d\'absence n\'est encore défini.';

  @override
  String get noProject => 'Sans projet';

  @override
  String get noProjects => 'Aucun projet';

  @override
  String get noProjectsMessage => 'Créez un projet pour classer votre temps.';

  @override
  String get noRequests => 'Aucune demande';

  @override
  String get noTag => 'Sans tag';

  @override
  String get noTags => 'Aucun tag';

  @override
  String get noTasks => 'Aucune tâche';

  @override
  String get noTeammateSelected => 'Choisissez au moins une personne.';

  @override
  String get noWorkspace => 'Aucun workspace';

  @override
  String get noWorkspaceMessage =>
      'Votre compte n\'appartient à aucun workspace actif. Demandez une invitation à un administrateur.';

  @override
  String get nonBillable => 'Non facturable';

  @override
  String get none => 'Aucun';

  @override
  String get notConfigured =>
      'Application non configurée : lancez `make app-config` puis relancez avec --dart-define-from-file.';

  @override
  String get note => 'Note';

  @override
  String get noteOptional => 'Commentaire (facultatif)';

  @override
  String get nothingToApprove => 'Rien à valider';

  @override
  String get nothingToInvoice =>
      'Aucun temps facturable non facturé pour ce client sur la période.';

  @override
  String get offline => 'Hors ligne';

  @override
  String get offlineExplanation =>
      'Vos saisies sont enregistrées sur l\'appareil et envoyées automatiquement dès que la connexion revient.';

  @override
  String get oldestTimerStopped =>
      'Limite atteinte : le chronomètre le plus ancien a été arrêté';

  @override
  String get online => 'En ligne';

  @override
  String get onlineOnly => 'Action impossible hors ligne.';

  @override
  String get openSystemSettings => 'Ouvrir les Réglages';

  @override
  String otherRunningTimers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ $count autres',
      one: '+ 1 autre',
    );
    return '$_temp0';
  }

  @override
  String get paid => 'Rémunérée';

  @override
  String get parallelTimers => 'Chronomètres simultanés';

  @override
  String get parallelTimersHelp =>
      'Nombre de chronomètres qu\'un membre peut faire tourner en même temps ; au-delà, le plus ancien s\'arrête';

  @override
  String get password => 'Mot de passe';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit faire au moins 8 caractères.';

  @override
  String get passwordUpdated => 'Mot de passe mis à jour.';

  @override
  String get paymentTermDays => 'Délai de paiement (jours)';

  @override
  String get pending => 'En attente';

  @override
  String get pendingChanges => 'Modifications en attente d\'envoi';

  @override
  String peopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes',
      one: '1 personne',
      zero: 'Personne',
    );
    return '$_temp0';
  }

  @override
  String get perHour => '/h';

  @override
  String pilotedBy(String name) {
    return 'Agent de $name';
  }

  @override
  String get policies => 'Politiques d\'absence';

  @override
  String get policy => 'Type d\'absence';

  @override
  String get policyExample => 'Congés payés, RTT, Maladie…';

  @override
  String get previousWeek => 'Semaine précédente';

  @override
  String get profile => 'Profil';

  @override
  String get project => 'Projet';

  @override
  String projectCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projets',
      one: '1 projet',
      zero: 'aucun projet',
    );
    return '$_temp0';
  }

  @override
  String get projectRequired => 'Un projet est obligatoire dans ce workspace.';

  @override
  String get projects => 'Projets';

  @override
  String get publicProject => 'Projet public';

  @override
  String get publicProjectHelp => 'Visible et utilisable par tous les membres';

  @override
  String get quantityHours => 'Quantité (h)';

  @override
  String readOnlyTimeOf(String name) {
    return 'Temps de $name : consultation seulement.';
  }

  @override
  String get reconnect => 'Reconnecter';

  @override
  String get reconnectComputer => 'Reconnecter ce poste ?';

  @override
  String reconnectComputerMessage(String name) {
    return 'Un nouveau jeton remplace celui de « $name », qui cesse de fonctionner. Suivez ensuite les étapes affichées, sur ce poste.';
  }

  @override
  String get reject => 'Refuser';

  @override
  String get remaining => 'restants';

  @override
  String get remove => 'Retirer';

  @override
  String get removeAgent => 'Retirer cet agent ?';

  @override
  String removeAgentMessage(String pilot) {
    return 'Les sessions Claude Code de $pilot ne produiront plus de temps, même avec un nouveau poste connecté. Ses entrées passées sont conservées. Pour une simple pause, choisissez plutôt Désactiver. Un administrateur peut le restaurer depuis Équipe, rubrique Agents retirés.';
  }

  @override
  String removedAgentOf(String name, String date) {
    return 'Agent de $name · retiré le $date';
  }

  @override
  String get removedAgents => 'Agents retirés';

  @override
  String get removedAgentsHelp =>
      'Leur temps n\'est plus enregistré, même si leur pilote connecte un nouveau poste.';

  @override
  String get removeMember => 'Retirer ce membre ?';

  @override
  String get removeMemberMessage =>
      'La personne perd l\'accès au workspace. Ses entrées passées sont conservées.';

  @override
  String get rename => 'Renommer';

  @override
  String get reopen => 'Rouvrir';

  @override
  String repoAttached(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dépôt rattaché à ce projet, et $count autres entrées.',
      one: 'Dépôt rattaché à ce projet, et 1 autre entrée.',
      zero: 'Dépôt rattaché à ce projet.',
    );
    return '$_temp0';
  }

  @override
  String get repoAttachOffline =>
      'Entrée enregistrée, mais le dépôt n\'a pas pu être rattaché : il faut être en ligne.';

  @override
  String get reports => 'Rapports';

  @override
  String get repoUnknown =>
      'Entrée enregistrée, mais son dépôt est inconnu : rien à rattacher.';

  @override
  String get requestSent => 'Demande envoyée.';

  @override
  String get requestTimeOff => 'Demander une absence';

  @override
  String get requireDescription => 'Description obligatoire';

  @override
  String get requireProject => 'Projet obligatoire';

  @override
  String get requiresApproval => 'Validation requise';

  @override
  String get requiresApprovalHint => 'Un manager doit valider cette demande.';

  @override
  String get resetEmailSent => 'Email de réinitialisation envoyé.';

  @override
  String get restore => 'Restaurer';

  @override
  String get retry => 'Réessayer';

  @override
  String get revoke => 'Révoquer';

  @override
  String revokeTokenConfirm(String name) {
    return 'Révoquer le jeton de « $name » ? Ce poste n\'enverra plus le temps de Claude.';
  }

  @override
  String get role => 'Rôle';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleMember => 'Membre';

  @override
  String get roleOwner => 'Propriétaire';

  @override
  String get rounding => 'Arrondi des durées';

  @override
  String get roundingHelp =>
      'Appliqué aux factures, et dans les rapports si demandé';

  @override
  String get runningTimer => 'Chronomètre en cours';

  @override
  String runningTimersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chronomètres en cours',
      one: '1 chronomètre en cours',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Enregistrer';

  @override
  String get saved => 'Enregistré.';

  @override
  String get schedule => 'Planning';

  @override
  String get search => 'Rechercher';

  @override
  String get searchProjectOrTask =>
      'Rechercher un projet, une tâche, un client';

  @override
  String get searchTags => 'Rechercher ou créer un tag';

  @override
  String get selectAll => 'Tout cocher';

  @override
  String get selectProject => 'Choisir un projet';

  @override
  String get selectTeammates => 'Choisir les collaborateurs';

  @override
  String get send => 'Envoyer';

  @override
  String get sendMagicLink => 'Recevoir un lien de connexion';

  @override
  String get setPassword => 'Définir le mot de passe';

  @override
  String get setPasswordHelp => 'Utile après une invitation ou un lien magique';

  @override
  String get settings => 'Paramètres';

  @override
  String get showArchived => 'Archivés';

  @override
  String get showInstallCommands => 'Afficher les commandes d\'installation';

  @override
  String showSimilarEntries(int count) {
    return 'Afficher les $count entrées';
  }

  @override
  String get signIn => 'Connexion';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutHelp =>
      'Les données locales de cet appareil seront effacées.';

  @override
  String get signUp => 'Inscription';

  @override
  String get similarEntriesEditHelp =>
      'Les horaires de chaque entrée ne changent pas.';

  @override
  String get similarEntriesLocked =>
      'Certaines entrées de ce groupe ne sont plus modifiables';

  @override
  String get start => 'Démarrer';

  @override
  String get startInFuture =>
      'L\'heure de début ne peut pas être dans le futur.';

  @override
  String get startTime => 'Début';

  @override
  String get statusApproved => 'Approuvée';

  @override
  String get statusCancelled => 'Annulée';

  @override
  String get statusNotSubmitted => 'Semaine non soumise';

  @override
  String get statusPending => 'En attente';

  @override
  String get statusRejected => 'Refusée';

  @override
  String get statusSubmitted => 'En attente d\'approbation';

  @override
  String get statusWithdrawn => 'Retirée';

  @override
  String get stop => 'Arrêter';

  @override
  String get submitForApproval => 'Soumettre pour approbation';

  @override
  String submittedForApproval(String total) {
    return 'Semaine soumise ($total).';
  }

  @override
  String get subtotal => 'Sous-total HT';

  @override
  String get summary => 'Résumé';

  @override
  String get switchWorkspace => 'Changer de workspace';

  @override
  String get syncStatus => 'Synchronisation';

  @override
  String get synced => 'Synchronisé';

  @override
  String get syncing => 'Synchronisation…';

  @override
  String get systemLanguage => 'Langue du système';

  @override
  String get tag => 'Tag';

  @override
  String get tagline => 'Suivi du temps libre et auto-hébergé';

  @override
  String get tags => 'Tags';

  @override
  String taskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tâches',
      one: '1 tâche',
    );
    return '$_temp0';
  }

  @override
  String get taskCreation => 'Création de tâches';

  @override
  String get taskCreationEveryone => 'Tout le monde';

  @override
  String get taskCreationHelp =>
      'Qui peut créer une tâche depuis le sélecteur de projet (chronomètre, saisie).';

  @override
  String get taskCreationManagers => 'Managers et administrateurs';

  @override
  String get tax => 'TVA';

  @override
  String get taxPercent => 'TVA';

  @override
  String get team => 'Équipe';

  @override
  String get teamEntry => 'Pointage d\'équipe';

  @override
  String get teamEntryHelp =>
      'Les présents sont cochés d\'office (sauf absence validée ou journée déjà saisie) : une entrée est créée pour chacun, même hors ligne. Touchez les horaires d\'une personne pour noter une exception (« Départ à 15:00 »).';

  @override
  String get teamManagerOf => 'Chef d\'équipe de…';

  @override
  String get teamManagerOfHelp =>
      'Ce membre verra le temps des personnes choisies et approuvera leurs feuilles de temps. La saisie pour autrui dépend du réglage du workspace.';

  @override
  String get teamMemberHint =>
      'Seuls les managers voient l\'activité de toute l\'équipe.';

  @override
  String get teamRequests => 'Demandes de l\'équipe';

  @override
  String get teammate => 'Collaborateur';

  @override
  String get teammates => 'Collaborateurs';

  @override
  String get thisMonth => 'Ce mois-ci';

  @override
  String get thisWeek => 'Cette semaine';

  @override
  String get thisYear => 'Cette année';

  @override
  String get timeForOthers => 'Saisie du temps pour autrui';

  @override
  String get timeForOthersAdmins => 'Administrateurs';

  @override
  String get timeForOthersAdminsAndTeamManagers =>
      'Administrateurs et chefs d\'équipe';

  @override
  String get timeForOthersHelp =>
      'Qui peut saisir et modifier le temps des autres membres.';

  @override
  String get timeOff => 'Absences';

  @override
  String get timeTracker => 'Suivi du temps';

  @override
  String get timerAlreadyRunningOnTask =>
      'Un chronomètre tourne déjà sur cette tâche';

  @override
  String get timesheet => 'Feuille de temps';

  @override
  String get toApprove => 'À valider';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get total => 'Total';

  @override
  String get totalInclTax => 'Total TTC';

  @override
  String get totalTime => 'Temps total';

  @override
  String get tracked => 'Suivi';

  @override
  String get unitPrice => 'Prix unitaire HT';

  @override
  String get unlimited => 'Illimité';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get unpaid => 'Non rémunérée';

  @override
  String get used => 'Pris';

  @override
  String get user => 'Utilisateur';

  @override
  String get userGuide => 'Guide d\'utilisation';

  @override
  String get userGuideHelp =>
      'Comment utiliser Clockifai selon votre rôle, avec des vidéos de démonstration.';

  @override
  String get users => 'Utilisateurs';

  @override
  String get view => 'Consulter';

  @override
  String weekOf(String date) {
    return 'Semaine du $date';
  }

  @override
  String get weekStartsOn => 'La semaine commence le';

  @override
  String get weekTotal => 'Total semaine';

  @override
  String weeksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count semaines',
      one: '1 semaine',
    );
    return '$_temp0';
  }

  @override
  String get whatAreYouWorkingOn => 'Sur quoi travaillez-vous ?';

  @override
  String get withdraw => 'Retirer';

  @override
  String get workspaceCreated =>
      'Workspace créé. Il apparaîtra après synchronisation.';

  @override
  String get workspaceSettings => 'Réglages du workspace';

  @override
  String get workspaces => 'Workspaces';

  @override
  String get year => 'an';

  @override
  String get yesterday => 'Hier';

  @override
  String get yourName => 'Votre nom';

  @override
  String get navWeek => 'Semaine';

  @override
  String get navPeople => 'Personnes';

  @override
  String get navProjectsClients => 'Projets et clients';

  @override
  String get searchOrAct => 'Rechercher ou agir';

  @override
  String get syncedWorksOffline => 'Synchronisé · fonctionne hors ligne';

  @override
  String get addTime => 'Ajouter du temps';

  @override
  String get add => 'Ajouter';

  @override
  String get inviteByEmail => 'Envoyer l\'invitation par email';

  @override
  String get inviteNoMail =>
      'Pas de serveur de mail sur cette installation : vous copierez le lien.';

  @override
  String get inviteReady => 'Invitation prête';

  @override
  String inviteEmailedTo(String email) {
    return 'Un email d\'invitation est parti à $email. Vous pouvez aussi lui transmettre ce lien :';
  }

  @override
  String inviteShareWith(String email) {
    return 'Transmettez ce lien à $email :';
  }

  @override
  String get copyLink => 'Copier le lien';

  @override
  String get linkCopied => 'Lien copié';

  @override
  String get journalToComplete => 'À compléter';

  @override
  String get journalFill => 'Remplir';

  @override
  String get journalNothingToday => 'Rien de saisi aujourd\'hui';

  @override
  String get journalNothingThatDay => 'Rien de saisi ce jour-là';

  @override
  String likeDayQuestion(String label) {
    return '$label ?';
  }

  @override
  String resumeDay(String duration) {
    return 'Reprendre la journée · $duration';
  }

  @override
  String get journalFromPlanning => 'Selon le planning';

  @override
  String get journalSomethingElse => 'Autre chose';

  @override
  String get journalYourDay => 'Votre journée';

  @override
  String get change => 'Changer';

  @override
  String get descriptionOptional => 'Description (facultative)';

  @override
  String get minus15 => 'Retirer 15 minutes';

  @override
  String get plus15 => 'Ajouter 15 minutes';

  @override
  String quickAddSaved(String duration, String range) {
    return 'Ajouté : $duration · $range';
  }

  @override
  String saveDuration(String duration) {
    return 'Enregistrer · $duration';
  }

  @override
  String subtaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sous-tâches',
      one: '1 sous-tâche',
    );
    return '$_temp0';
  }

  @override
  String get createSubtask => 'Ajouter une sous-tâche';

  @override
  String newSubtaskIn(String task) {
    return 'Nouvelle sous-tâche de $task';
  }

  @override
  String get subtasks => 'Sous-tâches';

  @override
  String get task => 'Tâche';

  @override
  String get noTask => 'Sans tâche';

  @override
  String get periodLocked =>
      'Période verrouillée : seule une personne administratrice peut y saisir du temps.';

  @override
  String get periodApproved =>
      'Période déjà approuvée : demandez sa réouverture pour y ajouter du temps.';

  @override
  String taskDeleted(String name) {
    return 'Tâche « $name » supprimée, avec ses sous-tâches ; ses entrées restent';
  }

  @override
  String get ticket => 'Ticket du client';

  @override
  String get ticketHint => 'URL Jira, Linear ou GitHub, ou clé (ENG-123)';

  @override
  String get ticketInvalid =>
      'Ticket non reconnu : une URL https ou une clé comme ENG-123';

  @override
  String ticketTaskExists(String name) {
    return 'Ce ticket a déjà sa tâche dans ce projet : $name';
  }

  @override
  String openTicket(String ticket) {
    return 'Ouvrir le ticket $ticket';
  }

  @override
  String createTicketTaskIn(String ticket) {
    return 'Créer la tâche du ticket $ticket dans :';
  }

  @override
  String newTicketTask(String ticket) {
    return 'Tâche du ticket $ticket';
  }

  @override
  String get ticketTitle => 'Titre (facultatif)';
}
