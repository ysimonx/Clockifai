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
  String get amount => 'Montant';

  @override
  String get annualAllowance => 'Droit annuel';

  @override
  String get apply => 'Appliquer';

  @override
  String applyRounding(int minutes) {
    return 'Arrondi $minutes min';
  }

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
  String get budgetHours => 'Budget';

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
  String get confirm => 'Confirmer';

  @override
  String get connection => 'Connexion';

  @override
  String get continueEntry => 'Continuer';

  @override
  String get copy => 'Copier';

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
  String get deleteClient => 'Supprimer le client ?';

  @override
  String get deleteClientMessage =>
      'Les projets de ce client seront conservés, sans client.';

  @override
  String get deleteEntry => 'Supprimer l\'entrée ?';

  @override
  String get deleteEntryMessage =>
      'Cette entrée de temps sera supprimée sur tous vos appareils.';

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
  String get deleteProject => 'Supprimer le projet ?';

  @override
  String get deleteProjectMessage =>
      'Les entrées existantes restent, mais ne seront plus rattachées à un projet visible.';

  @override
  String get deleteTag => 'Supprimer le tag ?';

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
  String get discardTimerMessage => 'Le temps en cours ne sera pas enregistré.';

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
  String get groups => 'Groupes';

  @override
  String get halfDay => 'Demi-journée';

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
  String get inviteLinkMessage =>
      'Aucun serveur d\'email n\'est configuré. Transmettez ce lien à la personne invitée :';

  @override
  String get inviteLinkTitle => 'Lien d\'invitation';

  @override
  String get inviteMember => 'Inviter un membre';

  @override
  String get invoice => 'Facture';

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
      'Une ligne par projet est créée à partir du temps facturable non encore facturé du client sur la période.';

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
  String get online => 'En ligne';

  @override
  String get onlineOnly => 'Action impossible hors ligne.';

  @override
  String get openSystemSettings => 'Ouvrir les Réglages';

  @override
  String get paid => 'Rémunérée';

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
  String get reject => 'Refuser';

  @override
  String get remaining => 'restants';

  @override
  String get remove => 'Retirer';

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
  String get reports => 'Rapports';

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
  String get roundingHelp => 'Appliqué dans les rapports si demandé';

  @override
  String get runningTimer => 'Chronomètre en cours';

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
  String get sectionManage => 'Gestion';

  @override
  String get sectionTeam => 'Équipe';

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
  String get signIn => 'Connexion';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutHelp =>
      'Les données locales de cet appareil seront effacées.';

  @override
  String get signUp => 'Inscription';

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
      'Cochez les présents : une entrée est créée pour chacun, même hors ligne. Touchez les horaires d\'une personne pour les ajuster.';

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
}
