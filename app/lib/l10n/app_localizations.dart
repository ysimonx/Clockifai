import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @account.
  ///
  /// In fr, this message translates to:
  /// **'Compte'**
  String get account;

  /// No description provided for @activate.
  ///
  /// In fr, this message translates to:
  /// **'Réactiver'**
  String get activate;

  /// No description provided for @addHoliday.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un jour férié'**
  String get addHoliday;

  /// No description provided for @addLine.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une ligne'**
  String get addLine;

  /// No description provided for @addManualEntry.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une entrée'**
  String get addManualEntry;

  /// No description provided for @addRow.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une ligne'**
  String get addRow;

  /// No description provided for @addTags.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter des tags'**
  String get addTags;

  /// No description provided for @addTask.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une tâche'**
  String get addTask;

  /// No description provided for @addTimeForOthers.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter du temps pour d\'autres'**
  String get addTimeForOthers;

  /// No description provided for @adminOnlySettings.
  ///
  /// In fr, this message translates to:
  /// **'Seuls les administrateurs peuvent modifier ces réglages.'**
  String get adminOnlySettings;

  /// No description provided for @agentBadge.
  ///
  /// In fr, this message translates to:
  /// **'Agent'**
  String get agentBadge;

  /// No description provided for @agentBillableHelp.
  ///
  /// In fr, this message translates to:
  /// **'Pour les sessions de Claude Code rattachées à ce projet'**
  String get agentBillableHelp;

  /// No description provided for @agentBillableWorkspace.
  ///
  /// In fr, this message translates to:
  /// **'Comme le réglage du workspace'**
  String get agentBillableWorkspace;

  /// No description provided for @agentBilling.
  ///
  /// In fr, this message translates to:
  /// **'Temps des agents Claude'**
  String get agentBilling;

  /// No description provided for @agentBillingHelp.
  ///
  /// In fr, this message translates to:
  /// **'Facturable ou non quand Claude Code enregistre une session ; un projet peut faire exception. Les entrées déjà enregistrées ne changent pas'**
  String get agentBillingHelp;

  /// No description provided for @agentBillingLikeHumans.
  ///
  /// In fr, this message translates to:
  /// **'Facturable comme le temps des personnes'**
  String get agentBillingLikeHumans;

  /// No description provided for @agentBillingNever.
  ///
  /// In fr, this message translates to:
  /// **'Jamais facturable'**
  String get agentBillingNever;

  /// No description provided for @agentCardLink.
  ///
  /// In fr, this message translates to:
  /// **'Voir sa fiche dans l\'équipe'**
  String get agentCardLink;

  /// No description provided for @agentInactive.
  ///
  /// In fr, this message translates to:
  /// **'Votre agent a été désactivé ou retiré par un administrateur : vos sessions Claude Code ne produisent plus de temps.'**
  String get agentInactive;

  /// No description provided for @agents.
  ///
  /// In fr, this message translates to:
  /// **'Agents'**
  String get agents;

  /// No description provided for @agentsHelp.
  ///
  /// In fr, this message translates to:
  /// **'Agents Claude : leur temps est enregistré par Claude Code, un agent par personne qui a connecté un poste (Paramètres › Intégrations).'**
  String get agentsHelp;

  /// No description provided for @agentsWorking.
  ///
  /// In fr, this message translates to:
  /// **'Claude travaille'**
  String get agentsWorking;

  /// No description provided for @agentsWorkingHelp.
  ///
  /// In fr, this message translates to:
  /// **'Sessions Claude Code en cours de votre agent. Sans activité pendant 10 minutes, une session se clôt à l\'heure de sa dernière action. Touchez une session pour changer son projet ou sa description.'**
  String get agentsWorkingHelp;

  /// No description provided for @agentTimeOf.
  ///
  /// In fr, this message translates to:
  /// **'Temps de {name} : vous pouvez corriger ses entrées, pas en ajouter.'**
  String agentTimeOf(String name);

  /// No description provided for @allClients.
  ///
  /// In fr, this message translates to:
  /// **'Tous les clients'**
  String get allClients;

  /// No description provided for @allMembers.
  ///
  /// In fr, this message translates to:
  /// **'Tous les membres'**
  String get allMembers;

  /// No description provided for @allProjects.
  ///
  /// In fr, this message translates to:
  /// **'Tous les projets'**
  String get allProjects;

  /// No description provided for @allowance.
  ///
  /// In fr, this message translates to:
  /// **'Droit annuel'**
  String get allowance;

  /// No description provided for @allowanceOverrideHelp.
  ///
  /// In fr, this message translates to:
  /// **'Laisser vide pour appliquer le droit de la politique ({value}).'**
  String allowanceOverrideHelp(String value);

  /// No description provided for @alwaysAttachRepo.
  ///
  /// In fr, this message translates to:
  /// **'Toujours rattacher ce dépôt à ce projet'**
  String get alwaysAttachRepo;

  /// No description provided for @alwaysAttachRepoHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les prochaines sessions de Claude dans ce dépôt iront dans ce projet, et ses entrées sans projet de la semaine aussi.'**
  String get alwaysAttachRepoHelp;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @annualAllowance.
  ///
  /// In fr, this message translates to:
  /// **'Droit annuel'**
  String get annualAllowance;

  /// No description provided for @apiTokenCreated.
  ///
  /// In fr, this message translates to:
  /// **'Jeton créé pour « {name} ». Il ne sera plus affiché : suivez ces étapes maintenant.'**
  String apiTokenCreated(String name);

  /// No description provided for @apply.
  ///
  /// In fr, this message translates to:
  /// **'Appliquer'**
  String get apply;

  /// No description provided for @applyRounding.
  ///
  /// In fr, this message translates to:
  /// **'Arrondi {minutes} min'**
  String applyRounding(int minutes);

  /// No description provided for @approvals.
  ///
  /// In fr, this message translates to:
  /// **'Approbations'**
  String get approvals;

  /// No description provided for @approve.
  ///
  /// In fr, this message translates to:
  /// **'Approuver'**
  String get approve;

  /// No description provided for @approvedPeriodFor.
  ///
  /// In fr, this message translates to:
  /// **'Période déjà approuvée pour {name}.'**
  String approvedPeriodFor(String name);

  /// No description provided for @approvers.
  ///
  /// In fr, this message translates to:
  /// **'Approbateurs'**
  String get approvers;

  /// No description provided for @approversManagers.
  ///
  /// In fr, this message translates to:
  /// **'Managers'**
  String get approversManagers;

  /// No description provided for @approversManagersAndTeamManagers.
  ///
  /// In fr, this message translates to:
  /// **'Managers et chefs d\'équipe'**
  String get approversManagersAndTeamManagers;

  /// No description provided for @archive.
  ///
  /// In fr, this message translates to:
  /// **'Archiver'**
  String get archive;

  /// No description provided for @archived.
  ///
  /// In fr, this message translates to:
  /// **'Archivé'**
  String get archived;

  /// No description provided for @autoStopTimers.
  ///
  /// In fr, this message translates to:
  /// **'Arrêt automatique des chronomètres'**
  String get autoStopTimers;

  /// No description provided for @autoStopTimersHelp.
  ///
  /// In fr, this message translates to:
  /// **'Arrête les chronomètres oubliés après cette durée'**
  String get autoStopTimersHelp;

  /// No description provided for @balancesFor.
  ///
  /// In fr, this message translates to:
  /// **'Mes soldes {year}'**
  String balancesFor(int year);

  /// No description provided for @billable.
  ///
  /// In fr, this message translates to:
  /// **'Facturable'**
  String get billable;

  /// No description provided for @billableAndNot.
  ///
  /// In fr, this message translates to:
  /// **'Facturable ou non'**
  String get billableAndNot;

  /// No description provided for @billableByDefault.
  ///
  /// In fr, this message translates to:
  /// **'Facturable par défaut'**
  String get billableByDefault;

  /// No description provided for @billableRate.
  ///
  /// In fr, this message translates to:
  /// **'Taux facturable (par heure)'**
  String get billableRate;

  /// No description provided for @billableTime.
  ///
  /// In fr, this message translates to:
  /// **'Temps facturable'**
  String get billableTime;

  /// No description provided for @billing.
  ///
  /// In fr, this message translates to:
  /// **'Facturation'**
  String get billing;

  /// No description provided for @billingAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse de facturation'**
  String get billingAddress;

  /// No description provided for @billingEmail.
  ///
  /// In fr, this message translates to:
  /// **'Email de facturation'**
  String get billingEmail;

  /// No description provided for @budgetHours.
  ///
  /// In fr, this message translates to:
  /// **'Budget'**
  String get budgetHours;

  /// No description provided for @budgetUsed.
  ///
  /// In fr, this message translates to:
  /// **'{percent} % du budget de {hours} h'**
  String budgetUsed(int percent, int hours);

  /// No description provided for @calendar.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier'**
  String get calendar;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @cancelRequest.
  ///
  /// In fr, this message translates to:
  /// **'Annuler la demande'**
  String get cancelRequest;

  /// No description provided for @cannotOpenLink.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir {url}'**
  String cannotOpenLink(String url);

  /// No description provided for @changeRejected.
  ///
  /// In fr, this message translates to:
  /// **'Modification refusée par le serveur : {message}'**
  String changeRejected(String message);

  /// No description provided for @changeRejectedPermission.
  ///
  /// In fr, this message translates to:
  /// **'Modification refusée : droits insuffisants ou période verrouillée. Elle a été annulée.'**
  String get changeRejectedPermission;

  /// No description provided for @checkYourEmail.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez votre boîte mail pour confirmer votre compte.'**
  String get checkYourEmail;

  /// No description provided for @claudeCodeHelp.
  ///
  /// In fr, this message translates to:
  /// **'Le temps de vos sessions Claude Code, au nom de votre agent « {agent} »'**
  String claudeCodeHelp(String agent);

  /// No description provided for @claudeCodeIntro.
  ///
  /// In fr, this message translates to:
  /// **'Chaque session de Claude Code devient du temps de votre agent « {agent} », membre de l\'équipe : un chronomètre démarre au premier prompt et s\'arrête après 10 minutes sans activité, à l\'heure de la dernière activité. Connectez chaque poste où vous utilisez Claude Code (terminal, VSCode, app de bureau).'**
  String claudeCodeIntro(String agent);

  /// No description provided for @claudeCodeLocalInstance.
  ///
  /// In fr, this message translates to:
  /// **'Instance locale : Claude Code n\'accepte une marketplace qu\'en https, celle-ci est donc le dossier integrations/ de votre copie du dépôt.'**
  String get claudeCodeLocalInstance;

  /// No description provided for @claudeCodeRequirements.
  ///
  /// In fr, this message translates to:
  /// **'Il faut aussi python3 (sur Mac, les outils de développement : xcode-select --install).'**
  String get claudeCodeRequirements;

  /// No description provided for @claudeCodeStepCli.
  ///
  /// In fr, this message translates to:
  /// **'1. Dans un terminal, claude --version doit afficher un numéro de version. Sinon, installez Claude Code en ligne de commande (l\'extension VSCode embarque sa propre copie, absente du terminal), puis ouvrez un nouveau terminal :'**
  String get claudeCodeStepCli;

  /// No description provided for @claudeCodeStepInstall.
  ///
  /// In fr, this message translates to:
  /// **'2. Dans un terminal (le panneau Claude Code de VSCode ne propose pas /plugin) :'**
  String get claudeCodeStepInstall;

  /// No description provided for @claudeCodeStepStart.
  ///
  /// In fr, this message translates to:
  /// **'4. Ouvrez une nouvelle conversation Claude Code : le chronomètre de Claude démarre au premier prompt.'**
  String get claudeCodeStepStart;

  /// No description provided for @claudeCodeStepToken.
  ///
  /// In fr, this message translates to:
  /// **'3. Copiez le jeton, puis enregistrez-le dans le plugin :'**
  String get claudeCodeStepToken;

  /// No description provided for @client.
  ///
  /// In fr, this message translates to:
  /// **'Client'**
  String get client;

  /// No description provided for @clients.
  ///
  /// In fr, this message translates to:
  /// **'Clients'**
  String get clients;

  /// No description provided for @close.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get close;

  /// No description provided for @color.
  ///
  /// In fr, this message translates to:
  /// **'Couleur'**
  String get color;

  /// No description provided for @companyDetails.
  ///
  /// In fr, this message translates to:
  /// **'Coordonnées (adresse, SIRET, TVA…)'**
  String get companyDetails;

  /// No description provided for @companyDetailsHint.
  ///
  /// In fr, this message translates to:
  /// **'Affichées en en-tête des factures'**
  String get companyDetailsHint;

  /// No description provided for @companyName.
  ///
  /// In fr, this message translates to:
  /// **'Raison sociale'**
  String get companyName;

  /// No description provided for @computerName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du poste'**
  String get computerName;

  /// No description provided for @confirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get confirm;

  /// No description provided for @connectComputer.
  ///
  /// In fr, this message translates to:
  /// **'Connecter un poste'**
  String get connectComputer;

  /// No description provided for @connectedComputers.
  ///
  /// In fr, this message translates to:
  /// **'Postes connectés'**
  String get connectedComputers;

  /// No description provided for @connection.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get connection;

  /// No description provided for @continueEntry.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get continueEntry;

  /// No description provided for @copied.
  ///
  /// In fr, this message translates to:
  /// **'Copié.'**
  String get copied;

  /// No description provided for @copy.
  ///
  /// In fr, this message translates to:
  /// **'Copier'**
  String get copy;

  /// No description provided for @copyToken.
  ///
  /// In fr, this message translates to:
  /// **'Copier le jeton'**
  String get copyToken;

  /// No description provided for @costRate.
  ///
  /// In fr, this message translates to:
  /// **'Coût (par heure)'**
  String get costRate;

  /// No description provided for @createAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer mon compte'**
  String get createAccount;

  /// No description provided for @createEntries.
  ///
  /// In fr, this message translates to:
  /// **'Créer les entrées'**
  String get createEntries;

  /// No description provided for @createProject.
  ///
  /// In fr, this message translates to:
  /// **'Créer un projet'**
  String get createProject;

  /// No description provided for @createTagNamed.
  ///
  /// In fr, this message translates to:
  /// **'Créer le tag « {name} »'**
  String createTagNamed(String name);

  /// No description provided for @createTask.
  ///
  /// In fr, this message translates to:
  /// **'Créer une tâche'**
  String get createTask;

  /// No description provided for @createTaskIn.
  ///
  /// In fr, this message translates to:
  /// **'Créer la tâche « {name} » dans :'**
  String createTaskIn(String name);

  /// No description provided for @createWorkspace.
  ///
  /// In fr, this message translates to:
  /// **'Créer un workspace'**
  String get createWorkspace;

  /// No description provided for @currency.
  ///
  /// In fr, this message translates to:
  /// **'Devise'**
  String get currency;

  /// No description provided for @currencyOverride.
  ///
  /// In fr, this message translates to:
  /// **'Devise spécifique (facultatif)'**
  String get currencyOverride;

  /// No description provided for @customRange.
  ///
  /// In fr, this message translates to:
  /// **'Période personnalisée'**
  String get customRange;

  /// No description provided for @date.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @day.
  ///
  /// In fr, this message translates to:
  /// **'Jour'**
  String get day;

  /// No description provided for @days.
  ///
  /// In fr, this message translates to:
  /// **'Jours'**
  String get days;

  /// No description provided for @daysRequested.
  ///
  /// In fr, this message translates to:
  /// **'Nombre de jours'**
  String get daysRequested;

  /// No description provided for @daysShort.
  ///
  /// In fr, this message translates to:
  /// **'j'**
  String get daysShort;

  /// No description provided for @deactivate.
  ///
  /// In fr, this message translates to:
  /// **'Désactiver'**
  String get deactivate;

  /// No description provided for @decision.
  ///
  /// In fr, this message translates to:
  /// **'Décision'**
  String get decision;

  /// No description provided for @defaultHours.
  ///
  /// In fr, this message translates to:
  /// **'Horaires par défaut'**
  String get defaultHours;

  /// No description provided for @delete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get delete;

  /// No description provided for @deleteClient.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le client ?'**
  String get deleteClient;

  /// No description provided for @deleteClientMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les projets de ce client seront conservés, sans client.'**
  String get deleteClientMessage;

  /// No description provided for @deleteEntry.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer l\'entrée ?'**
  String get deleteEntry;

  /// No description provided for @deleteEntryMessage.
  ///
  /// In fr, this message translates to:
  /// **'Cette entrée de temps sera supprimée sur tous vos appareils.'**
  String get deleteEntryMessage;

  /// No description provided for @deleteGroup.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le groupe'**
  String get deleteGroup;

  /// No description provided for @deleteGroupMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les membres restent dans le workspace ; les chefs d\'équipe n\'encadrent plus ce groupe.'**
  String get deleteGroupMessage;

  /// No description provided for @deleteInvoice.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la facture ?'**
  String get deleteInvoice;

  /// No description provided for @deleteInvoiceMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les entrées de temps redeviennent facturables.'**
  String get deleteInvoiceMessage;

  /// No description provided for @deletePolicy.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la politique ?'**
  String get deletePolicy;

  /// No description provided for @deleteProject.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le projet ?'**
  String get deleteProject;

  /// No description provided for @deleteProjectMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les entrées existantes restent, mais ne seront plus rattachées à un projet visible.'**
  String get deleteProjectMessage;

  /// No description provided for @deleteSimilarEntries.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer les {count} entrées'**
  String deleteSimilarEntries(int count);

  /// No description provided for @deleteSimilarEntriesMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les {count} entrées de ce groupe seront supprimées.'**
  String deleteSimilarEntriesMessage(int count);

  /// No description provided for @deleteTag.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le tag ?'**
  String get deleteTag;

  /// No description provided for @description.
  ///
  /// In fr, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @descriptionRequired.
  ///
  /// In fr, this message translates to:
  /// **'Une description est obligatoire dans ce workspace.'**
  String get descriptionRequired;

  /// No description provided for @detailed.
  ///
  /// In fr, this message translates to:
  /// **'Détaillé'**
  String get detailed;

  /// No description provided for @discardTimer.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner le chronomètre'**
  String get discardTimer;

  /// No description provided for @discardTimerMessage.
  ///
  /// In fr, this message translates to:
  /// **'Le temps en cours ne sera pas enregistré.'**
  String get discardTimerMessage;

  /// No description provided for @discount.
  ///
  /// In fr, this message translates to:
  /// **'Remise'**
  String get discount;

  /// No description provided for @discountPercent.
  ///
  /// In fr, this message translates to:
  /// **'Remise'**
  String get discountPercent;

  /// No description provided for @draftNumberPending.
  ///
  /// In fr, this message translates to:
  /// **'Brouillon'**
  String get draftNumberPending;

  /// No description provided for @due.
  ///
  /// In fr, this message translates to:
  /// **'échéance'**
  String get due;

  /// No description provided for @duplicate.
  ///
  /// In fr, this message translates to:
  /// **'Dupliquer'**
  String get duplicate;

  /// No description provided for @duration.
  ///
  /// In fr, this message translates to:
  /// **'Durée'**
  String get duration;

  /// No description provided for @edit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get edit;

  /// No description provided for @editAssignment.
  ///
  /// In fr, this message translates to:
  /// **'Modifier l\'affectation'**
  String get editAssignment;

  /// No description provided for @editClient.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le client'**
  String get editClient;

  /// No description provided for @editEntry.
  ///
  /// In fr, this message translates to:
  /// **'Modifier l\'entrée'**
  String get editEntry;

  /// No description provided for @editPolicy.
  ///
  /// In fr, this message translates to:
  /// **'Modifier la politique'**
  String get editPolicy;

  /// No description provided for @editProject.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le projet'**
  String get editProject;

  /// No description provided for @editRates.
  ///
  /// In fr, this message translates to:
  /// **'Modifier les taux'**
  String get editRates;

  /// No description provided for @editSimilarEntries.
  ///
  /// In fr, this message translates to:
  /// **'Modifier les {count} entrées'**
  String editSimilarEntries(int count);

  /// No description provided for @editTag.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le tag'**
  String get editTag;

  /// No description provided for @editTimer.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le chronomètre'**
  String get editTimer;

  /// No description provided for @email.
  ///
  /// In fr, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre adresse email.'**
  String get emailRequired;

  /// No description provided for @emptyIsUnlimited.
  ///
  /// In fr, this message translates to:
  /// **'Vide = illimité'**
  String get emptyIsUnlimited;

  /// No description provided for @endTime.
  ///
  /// In fr, this message translates to:
  /// **'Fin'**
  String get endTime;

  /// No description provided for @endTimeRequired.
  ///
  /// In fr, this message translates to:
  /// **'Indiquez une heure de fin.'**
  String get endTimeRequired;

  /// No description provided for @endsNextDay.
  ///
  /// In fr, this message translates to:
  /// **'Se termine le lendemain.'**
  String get endsNextDay;

  /// No description provided for @enteredBy.
  ///
  /// In fr, this message translates to:
  /// **'saisi par {name}'**
  String enteredBy(String name);

  /// No description provided for @enteringFor.
  ///
  /// In fr, this message translates to:
  /// **'Vous saisissez le temps de {name}.'**
  String enteringFor(String name);

  /// No description provided for @entriesCreated.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 entrée créée} other{{count} entrées créées}}'**
  String entriesCreated(int count);

  /// No description provided for @entryLocked.
  ///
  /// In fr, this message translates to:
  /// **'Entrée verrouillée : seule une personne administratrice peut la modifier.'**
  String get entryLocked;

  /// No description provided for @environmentLocal.
  ///
  /// In fr, this message translates to:
  /// **'Version locale'**
  String get environmentLocal;

  /// No description provided for @environmentProduction.
  ///
  /// In fr, this message translates to:
  /// **'Production'**
  String get environmentProduction;

  /// No description provided for @export.
  ///
  /// In fr, this message translates to:
  /// **'Exporter'**
  String get export;

  /// No description provided for @exportCsvOffline.
  ///
  /// In fr, this message translates to:
  /// **'CSV (hors ligne)'**
  String get exportCsvOffline;

  /// No description provided for @exportDone.
  ///
  /// In fr, this message translates to:
  /// **'Export téléchargé.'**
  String get exportDone;

  /// No description provided for @exportFailed.
  ///
  /// In fr, this message translates to:
  /// **'Échec de l\'export : {error}'**
  String exportFailed(String error);

  /// No description provided for @firstSync.
  ///
  /// In fr, this message translates to:
  /// **'Première synchronisation en cours…'**
  String get firstSync;

  /// No description provided for @forgotPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe oublié'**
  String get forgotPassword;

  /// No description provided for @generate.
  ///
  /// In fr, this message translates to:
  /// **'Générer'**
  String get generate;

  /// No description provided for @groupBy.
  ///
  /// In fr, this message translates to:
  /// **'Grouper par'**
  String get groupBy;

  /// No description provided for @groupMembers.
  ///
  /// In fr, this message translates to:
  /// **'Membres du groupe'**
  String get groupMembers;

  /// No description provided for @groupName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du groupe'**
  String get groupName;

  /// No description provided for @groupSimilarEntries.
  ///
  /// In fr, this message translates to:
  /// **'Regrouper les entrées similaires'**
  String get groupSimilarEntries;

  /// No description provided for @groupSimilarEntriesHelp.
  ///
  /// In fr, this message translates to:
  /// **'Suivi du temps : les entrées d\'une même journée avec la même description, le même projet, la même tâche, les mêmes tags et la même facturation sont réunies sur une ligne dépliable'**
  String get groupSimilarEntriesHelp;

  /// No description provided for @groups.
  ///
  /// In fr, this message translates to:
  /// **'Groupes'**
  String get groups;

  /// No description provided for @halfDay.
  ///
  /// In fr, this message translates to:
  /// **'Demi-journée'**
  String get halfDay;

  /// No description provided for @help.
  ///
  /// In fr, this message translates to:
  /// **'Aide'**
  String get help;

  /// No description provided for @hideSimilarEntries.
  ///
  /// In fr, this message translates to:
  /// **'Masquer le détail'**
  String get hideSimilarEntries;

  /// No description provided for @history.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get history;

  /// No description provided for @holidays.
  ///
  /// In fr, this message translates to:
  /// **'Jours fériés'**
  String get holidays;

  /// No description provided for @hourlyRate.
  ///
  /// In fr, this message translates to:
  /// **'Taux horaire'**
  String get hourlyRate;

  /// No description provided for @hours.
  ///
  /// In fr, this message translates to:
  /// **'Heures'**
  String get hours;

  /// No description provided for @hoursPerDay.
  ///
  /// In fr, this message translates to:
  /// **'Heures par jour'**
  String get hoursPerDay;

  /// No description provided for @hoursRequested.
  ///
  /// In fr, this message translates to:
  /// **'Nombre d\'heures'**
  String get hoursRequested;

  /// No description provided for @humans.
  ///
  /// In fr, this message translates to:
  /// **'Humains'**
  String get humans;

  /// No description provided for @humansAndAgents.
  ///
  /// In fr, this message translates to:
  /// **'Humains et agents'**
  String get humansAndAgents;

  /// No description provided for @integrations.
  ///
  /// In fr, this message translates to:
  /// **'Intégrations'**
  String get integrations;

  /// No description provided for @invalidDuration.
  ///
  /// In fr, this message translates to:
  /// **'Durée invalide (exemples : 1:30, 1,5, 90m).'**
  String get invalidDuration;

  /// No description provided for @invalidHours.
  ///
  /// In fr, this message translates to:
  /// **'Nombre d\'heures invalide (entre 0 et 24).'**
  String get invalidHours;

  /// No description provided for @invitationFailed.
  ///
  /// In fr, this message translates to:
  /// **'Invitation impossible : {error}'**
  String invitationFailed(String error);

  /// No description provided for @invitationSent.
  ///
  /// In fr, this message translates to:
  /// **'Invitation envoyée.'**
  String get invitationSent;

  /// No description provided for @invite.
  ///
  /// In fr, this message translates to:
  /// **'Inviter'**
  String get invite;

  /// No description provided for @inviteHelp.
  ///
  /// In fr, this message translates to:
  /// **'Si la personne a déjà un compte, elle est ajoutée immédiatement. Sinon, un lien d\'invitation est créé.'**
  String get inviteHelp;

  /// No description provided for @inviteLinkMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun serveur d\'email n\'est configuré. Transmettez ce lien à la personne invitée :'**
  String get inviteLinkMessage;

  /// No description provided for @inviteLinkTitle.
  ///
  /// In fr, this message translates to:
  /// **'Lien d\'invitation'**
  String get inviteLinkTitle;

  /// No description provided for @inviteMember.
  ///
  /// In fr, this message translates to:
  /// **'Inviter un membre'**
  String get inviteMember;

  /// No description provided for @invoice.
  ///
  /// In fr, this message translates to:
  /// **'Facture'**
  String get invoice;

  /// No description provided for @invoiceDraft.
  ///
  /// In fr, this message translates to:
  /// **'Brouillon'**
  String get invoiceDraft;

  /// No description provided for @invoiceNote.
  ///
  /// In fr, this message translates to:
  /// **'Mentions / conditions'**
  String get invoiceNote;

  /// No description provided for @invoiceNoteHint.
  ///
  /// In fr, this message translates to:
  /// **'Conditions de paiement, IBAN… (Entrée pour enregistrer)'**
  String get invoiceNoteHint;

  /// No description provided for @invoicePaid.
  ///
  /// In fr, this message translates to:
  /// **'Payée'**
  String get invoicePaid;

  /// No description provided for @invoicePrefix.
  ///
  /// In fr, this message translates to:
  /// **'Préfixe des numéros'**
  String get invoicePrefix;

  /// No description provided for @invoiceSent.
  ///
  /// In fr, this message translates to:
  /// **'Envoyée'**
  String get invoiceSent;

  /// No description provided for @invoiceVoid.
  ///
  /// In fr, this message translates to:
  /// **'Annulée'**
  String get invoiceVoid;

  /// No description provided for @invoices.
  ///
  /// In fr, this message translates to:
  /// **'Factures'**
  String get invoices;

  /// No description provided for @kiosk.
  ///
  /// In fr, this message translates to:
  /// **'Kiosque'**
  String get kiosk;

  /// No description provided for @kioskClockInAs.
  ///
  /// In fr, this message translates to:
  /// **'Arrivée de {name}'**
  String kioskClockInAs(String name);

  /// No description provided for @kioskClockOutAs.
  ///
  /// In fr, this message translates to:
  /// **'Départ de {name}'**
  String kioskClockOutAs(String name);

  /// No description provided for @kioskClockedIn.
  ///
  /// In fr, this message translates to:
  /// **'Pointage d\'arrivée enregistré.'**
  String get kioskClockedIn;

  /// No description provided for @kioskClockedOut.
  ///
  /// In fr, this message translates to:
  /// **'Pointage de départ enregistré.'**
  String get kioskClockedOut;

  /// No description provided for @kioskDevices.
  ///
  /// In fr, this message translates to:
  /// **'Appareils kiosque'**
  String get kioskDevices;

  /// No description provided for @kioskDevicesHelp.
  ///
  /// In fr, this message translates to:
  /// **'Tablettes partagées où l\'équipe pointe avec un code PIN'**
  String get kioskDevicesHelp;

  /// No description provided for @kioskExit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter le mode kiosque'**
  String get kioskExit;

  /// No description provided for @kioskGoodbye.
  ///
  /// In fr, this message translates to:
  /// **'Au revoir {name} !'**
  String kioskGoodbye(String name);

  /// No description provided for @kioskHello.
  ///
  /// In fr, this message translates to:
  /// **'Bonjour {name} !'**
  String kioskHello(String name);

  /// No description provided for @kioskMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode kiosque (tablette partagée)'**
  String get kioskMode;

  /// No description provided for @kioskNoPin.
  ///
  /// In fr, this message translates to:
  /// **'Cette personne n\'a pas encore défini son code PIN (Paramètres > Code PIN kiosque).'**
  String get kioskNoPin;

  /// No description provided for @kioskPin.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN kiosque'**
  String get kioskPin;

  /// No description provided for @kioskPinHelp.
  ///
  /// In fr, this message translates to:
  /// **'Pour pointer sur une tablette partagée'**
  String get kioskPinHelp;

  /// No description provided for @kioskPinInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Le PIN doit contenir 4 à 8 chiffres.'**
  String get kioskPinInvalid;

  /// No description provided for @kioskPinLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau PIN (4 à 8 chiffres)'**
  String get kioskPinLabel;

  /// No description provided for @kioskPinSaved.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN enregistré.'**
  String get kioskPinSaved;

  /// No description provided for @kioskReset.
  ///
  /// In fr, this message translates to:
  /// **'Désassocier cet appareil'**
  String get kioskReset;

  /// No description provided for @kioskResetMessage.
  ///
  /// In fr, this message translates to:
  /// **'Le jeton sera oublié sur cet appareil.'**
  String get kioskResetMessage;

  /// No description provided for @kioskSetupHelp.
  ///
  /// In fr, this message translates to:
  /// **'Collez le jeton d\'appareil créé par un administrateur dans Paramètres > Appareils kiosque.'**
  String get kioskSetupHelp;

  /// No description provided for @kioskTapYourName.
  ///
  /// In fr, this message translates to:
  /// **'Touchez votre nom pour pointer'**
  String get kioskTapYourName;

  /// No description provided for @kioskToken.
  ///
  /// In fr, this message translates to:
  /// **'Jeton d\'appareil'**
  String get kioskToken;

  /// No description provided for @kioskTokenInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Jeton invalide ou révoqué.'**
  String get kioskTokenInvalid;

  /// No description provided for @kioskTokenOnce.
  ///
  /// In fr, this message translates to:
  /// **'Copiez ce jeton maintenant : il ne sera plus affiché. Saisissez-le sur la tablette en mode kiosque.'**
  String get kioskTokenOnce;

  /// No description provided for @kioskTooManyAttempts.
  ///
  /// In fr, this message translates to:
  /// **'Trop d\'essais. Réessayez dans quelques minutes.'**
  String get kioskTooManyAttempts;

  /// No description provided for @kioskWrongPin.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN incorrect.'**
  String get kioskWrongPin;

  /// No description provided for @language.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get language;

  /// No description provided for @lastEventHoursAgo.
  ///
  /// In fr, this message translates to:
  /// **'Dernier événement il y a {hours} h'**
  String lastEventHoursAgo(int hours);

  /// No description provided for @lastEventJustNow.
  ///
  /// In fr, this message translates to:
  /// **'Dernier événement à l\'instant'**
  String get lastEventJustNow;

  /// No description provided for @lastEventMinutesAgo.
  ///
  /// In fr, this message translates to:
  /// **'Dernier événement il y a {minutes} min'**
  String lastEventMinutesAgo(int minutes);

  /// No description provided for @lastEventNever.
  ///
  /// In fr, this message translates to:
  /// **'Aucun événement reçu'**
  String get lastEventNever;

  /// No description provided for @lastEventOn.
  ///
  /// In fr, this message translates to:
  /// **'Dernier événement le {date}'**
  String lastEventOn(String date);

  /// No description provided for @lastMonth.
  ///
  /// In fr, this message translates to:
  /// **'Mois dernier'**
  String get lastMonth;

  /// No description provided for @lastSeen.
  ///
  /// In fr, this message translates to:
  /// **'Dernière activité'**
  String get lastSeen;

  /// No description provided for @lastSync.
  ///
  /// In fr, this message translates to:
  /// **'Dernière synchronisation'**
  String get lastSync;

  /// No description provided for @lastWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine dernière'**
  String get lastWeek;

  /// No description provided for @launchAtLogin.
  ///
  /// In fr, this message translates to:
  /// **'Démarrer à l\'ouverture de session'**
  String get launchAtLogin;

  /// No description provided for @launchAtLoginApproval.
  ///
  /// In fr, this message translates to:
  /// **'À autoriser dans Réglages Système > Général > Ouverture.'**
  String get launchAtLoginApproval;

  /// No description provided for @launchAtLoginHelp.
  ///
  /// In fr, this message translates to:
  /// **'Clockifai s\'ouvre dans la barre de menus, sans fenêtre.'**
  String get launchAtLoginHelp;

  /// No description provided for @loadMore.
  ///
  /// In fr, this message translates to:
  /// **'Afficher plus'**
  String get loadMore;

  /// No description provided for @lockEntriesBefore.
  ///
  /// In fr, this message translates to:
  /// **'Verrouiller les entrées antérieures au'**
  String get lockEntriesBefore;

  /// No description provided for @lockEntriesNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucun verrouillage'**
  String get lockEntriesNone;

  /// No description provided for @magicLinkSent.
  ///
  /// In fr, this message translates to:
  /// **'Lien de connexion envoyé par email.'**
  String get magicLinkSent;

  /// No description provided for @managedByLabel.
  ///
  /// In fr, this message translates to:
  /// **'Chef d\'équipe : {names}'**
  String managedByLabel(String names);

  /// No description provided for @managersOnly.
  ///
  /// In fr, this message translates to:
  /// **'Réservé aux managers'**
  String get managersOnly;

  /// No description provided for @managesLabel.
  ///
  /// In fr, this message translates to:
  /// **'Encadre : {names}'**
  String managesLabel(String names);

  /// No description provided for @markDone.
  ///
  /// In fr, this message translates to:
  /// **'Marquer terminée'**
  String get markDone;

  /// No description provided for @member.
  ///
  /// In fr, this message translates to:
  /// **'Membre'**
  String get member;

  /// No description provided for @memberAllowances.
  ///
  /// In fr, this message translates to:
  /// **'Droits par membre'**
  String get memberAllowances;

  /// No description provided for @memberCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucun membre} =1{1 membre} other{{count} membres}}'**
  String memberCount(int count);

  /// No description provided for @members.
  ///
  /// In fr, this message translates to:
  /// **'Membres'**
  String get members;

  /// No description provided for @menuBarOpenApp.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir Clockifai'**
  String get menuBarOpenApp;

  /// No description provided for @menuBarQuit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter Clockifai'**
  String get menuBarQuit;

  /// No description provided for @menuBarRecent.
  ///
  /// In fr, this message translates to:
  /// **'Récemment'**
  String get menuBarRecent;

  /// No description provided for @menuBarSignIn.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous dans la fenêtre Clockifai pour suivre votre temps.'**
  String get menuBarSignIn;

  /// No description provided for @more.
  ///
  /// In fr, this message translates to:
  /// **'Plus'**
  String get more;

  /// No description provided for @myRequests.
  ///
  /// In fr, this message translates to:
  /// **'Mes demandes'**
  String get myRequests;

  /// No description provided for @name.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get name;

  /// No description provided for @never.
  ///
  /// In fr, this message translates to:
  /// **'Jamais'**
  String get never;

  /// No description provided for @neverSeen.
  ///
  /// In fr, this message translates to:
  /// **'Jamais connecté'**
  String get neverSeen;

  /// No description provided for @newAssignment.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle affectation'**
  String get newAssignment;

  /// No description provided for @newClient.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau client'**
  String get newClient;

  /// No description provided for @newGroup.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau groupe'**
  String get newGroup;

  /// No description provided for @newInvoice.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle facture'**
  String get newInvoice;

  /// No description provided for @newInvoiceHelp.
  ///
  /// In fr, this message translates to:
  /// **'Une ligne par projet est créée à partir du temps facturable non encore facturé du client sur la période.'**
  String get newInvoiceHelp;

  /// No description provided for @newKioskDevice.
  ///
  /// In fr, this message translates to:
  /// **'Nouvel appareil'**
  String get newKioskDevice;

  /// No description provided for @newPassword.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau mot de passe (8 caractères min.)'**
  String get newPassword;

  /// No description provided for @newPolicy.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle politique'**
  String get newPolicy;

  /// No description provided for @newProject.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau projet'**
  String get newProject;

  /// No description provided for @newTag.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau tag'**
  String get newTag;

  /// No description provided for @newTask.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle tâche'**
  String get newTask;

  /// No description provided for @newTaskIn.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle tâche dans {project}'**
  String newTaskIn(String project);

  /// No description provided for @nextWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine suivante'**
  String get nextWeek;

  /// No description provided for @noApproval.
  ///
  /// In fr, this message translates to:
  /// **'Sans validation'**
  String get noApproval;

  /// No description provided for @noClient.
  ///
  /// In fr, this message translates to:
  /// **'Sans client'**
  String get noClient;

  /// No description provided for @noClients.
  ///
  /// In fr, this message translates to:
  /// **'Aucun client'**
  String get noClients;

  /// No description provided for @noConnectedComputers.
  ///
  /// In fr, this message translates to:
  /// **'Aucun poste connecté.'**
  String get noConnectedComputers;

  /// No description provided for @noDataForPeriod.
  ///
  /// In fr, this message translates to:
  /// **'Aucune donnée sur cette période'**
  String get noDataForPeriod;

  /// No description provided for @noDescription.
  ///
  /// In fr, this message translates to:
  /// **'(sans description)'**
  String get noDescription;

  /// No description provided for @noEntriesInPeriod.
  ///
  /// In fr, this message translates to:
  /// **'Aucune entrée sur la période'**
  String get noEntriesInPeriod;

  /// No description provided for @noEntriesYet.
  ///
  /// In fr, this message translates to:
  /// **'Aucune entrée pour l\'instant'**
  String get noEntriesYet;

  /// No description provided for @noEntriesYetMessage.
  ///
  /// In fr, this message translates to:
  /// **'Démarrez le chronomètre ci-dessus ou ajoutez du temps manuellement.'**
  String get noEntriesYetMessage;

  /// No description provided for @noGroups.
  ///
  /// In fr, this message translates to:
  /// **'Aucun groupe'**
  String get noGroups;

  /// No description provided for @noGroupsMessage.
  ///
  /// In fr, this message translates to:
  /// **'Regroupez les membres (équipe, chantier, entreprise) pour les confier à un chef d\'équipe.'**
  String get noGroupsMessage;

  /// No description provided for @noHistory.
  ///
  /// In fr, this message translates to:
  /// **'Aucun historique'**
  String get noHistory;

  /// No description provided for @noHolidays.
  ///
  /// In fr, this message translates to:
  /// **'Aucun jour férié'**
  String get noHolidays;

  /// No description provided for @noInvoices.
  ///
  /// In fr, this message translates to:
  /// **'Aucune facture'**
  String get noInvoices;

  /// No description provided for @noInvoicesMessage.
  ///
  /// In fr, this message translates to:
  /// **'Générez une facture à partir du temps facturable d\'un client.'**
  String get noInvoicesMessage;

  /// No description provided for @noMatch.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get noMatch;

  /// No description provided for @noMembers.
  ///
  /// In fr, this message translates to:
  /// **'Aucun membre'**
  String get noMembers;

  /// No description provided for @noPoliciesYet.
  ///
  /// In fr, this message translates to:
  /// **'Aucun type d\'absence n\'est encore défini.'**
  String get noPoliciesYet;

  /// No description provided for @noProject.
  ///
  /// In fr, this message translates to:
  /// **'Sans projet'**
  String get noProject;

  /// No description provided for @noProjects.
  ///
  /// In fr, this message translates to:
  /// **'Aucun projet'**
  String get noProjects;

  /// No description provided for @noProjectsMessage.
  ///
  /// In fr, this message translates to:
  /// **'Créez un projet pour classer votre temps.'**
  String get noProjectsMessage;

  /// No description provided for @noRequests.
  ///
  /// In fr, this message translates to:
  /// **'Aucune demande'**
  String get noRequests;

  /// No description provided for @noTag.
  ///
  /// In fr, this message translates to:
  /// **'Sans tag'**
  String get noTag;

  /// No description provided for @noTags.
  ///
  /// In fr, this message translates to:
  /// **'Aucun tag'**
  String get noTags;

  /// No description provided for @noTasks.
  ///
  /// In fr, this message translates to:
  /// **'Aucune tâche'**
  String get noTasks;

  /// No description provided for @noTeammateSelected.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez au moins une personne.'**
  String get noTeammateSelected;

  /// No description provided for @noWorkspace.
  ///
  /// In fr, this message translates to:
  /// **'Aucun workspace'**
  String get noWorkspace;

  /// No description provided for @noWorkspaceMessage.
  ///
  /// In fr, this message translates to:
  /// **'Votre compte n\'appartient à aucun workspace actif. Demandez une invitation à un administrateur.'**
  String get noWorkspaceMessage;

  /// No description provided for @nonBillable.
  ///
  /// In fr, this message translates to:
  /// **'Non facturable'**
  String get nonBillable;

  /// No description provided for @none.
  ///
  /// In fr, this message translates to:
  /// **'Aucun'**
  String get none;

  /// No description provided for @notConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Application non configurée : lancez `make app-config` puis relancez avec --dart-define-from-file.'**
  String get notConfigured;

  /// No description provided for @note.
  ///
  /// In fr, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @noteOptional.
  ///
  /// In fr, this message translates to:
  /// **'Commentaire (facultatif)'**
  String get noteOptional;

  /// No description provided for @nothingToApprove.
  ///
  /// In fr, this message translates to:
  /// **'Rien à valider'**
  String get nothingToApprove;

  /// No description provided for @nothingToInvoice.
  ///
  /// In fr, this message translates to:
  /// **'Aucun temps facturable non facturé pour ce client sur la période.'**
  String get nothingToInvoice;

  /// No description provided for @offline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne'**
  String get offline;

  /// No description provided for @offlineExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Vos saisies sont enregistrées sur l\'appareil et envoyées automatiquement dès que la connexion revient.'**
  String get offlineExplanation;

  /// No description provided for @oldestTimerStopped.
  ///
  /// In fr, this message translates to:
  /// **'Limite atteinte : le chronomètre le plus ancien a été arrêté'**
  String get oldestTimerStopped;

  /// No description provided for @online.
  ///
  /// In fr, this message translates to:
  /// **'En ligne'**
  String get online;

  /// No description provided for @onlineOnly.
  ///
  /// In fr, this message translates to:
  /// **'Action impossible hors ligne.'**
  String get onlineOnly;

  /// No description provided for @openSystemSettings.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir les Réglages'**
  String get openSystemSettings;

  /// No description provided for @otherRunningTimers.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{+ 1 autre} other{+ {count} autres}}'**
  String otherRunningTimers(int count);

  /// No description provided for @paid.
  ///
  /// In fr, this message translates to:
  /// **'Rémunérée'**
  String get paid;

  /// No description provided for @parallelTimers.
  ///
  /// In fr, this message translates to:
  /// **'Chronomètres simultanés'**
  String get parallelTimers;

  /// No description provided for @parallelTimersHelp.
  ///
  /// In fr, this message translates to:
  /// **'Nombre de chronomètres qu\'un membre peut faire tourner en même temps ; au-delà, le plus ancien s\'arrête'**
  String get parallelTimersHelp;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @passwordTooShort.
  ///
  /// In fr, this message translates to:
  /// **'Le mot de passe doit faire au moins 8 caractères.'**
  String get passwordTooShort;

  /// No description provided for @passwordUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe mis à jour.'**
  String get passwordUpdated;

  /// No description provided for @paymentTermDays.
  ///
  /// In fr, this message translates to:
  /// **'Délai de paiement (jours)'**
  String get paymentTermDays;

  /// No description provided for @pending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get pending;

  /// No description provided for @pendingChanges.
  ///
  /// In fr, this message translates to:
  /// **'Modifications en attente d\'envoi'**
  String get pendingChanges;

  /// No description provided for @peopleCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Personne} =1{1 personne} other{{count} personnes}}'**
  String peopleCount(int count);

  /// No description provided for @perHour.
  ///
  /// In fr, this message translates to:
  /// **'/h'**
  String get perHour;

  /// No description provided for @pilotedBy.
  ///
  /// In fr, this message translates to:
  /// **'Agent de {name}'**
  String pilotedBy(String name);

  /// No description provided for @policies.
  ///
  /// In fr, this message translates to:
  /// **'Politiques d\'absence'**
  String get policies;

  /// No description provided for @policy.
  ///
  /// In fr, this message translates to:
  /// **'Type d\'absence'**
  String get policy;

  /// No description provided for @policyExample.
  ///
  /// In fr, this message translates to:
  /// **'Congés payés, RTT, Maladie…'**
  String get policyExample;

  /// No description provided for @previousWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine précédente'**
  String get previousWeek;

  /// No description provided for @profile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @project.
  ///
  /// In fr, this message translates to:
  /// **'Projet'**
  String get project;

  /// No description provided for @projectCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{aucun projet} =1{1 projet} other{{count} projets}}'**
  String projectCount(int count);

  /// No description provided for @projectRequired.
  ///
  /// In fr, this message translates to:
  /// **'Un projet est obligatoire dans ce workspace.'**
  String get projectRequired;

  /// No description provided for @projects.
  ///
  /// In fr, this message translates to:
  /// **'Projets'**
  String get projects;

  /// No description provided for @publicProject.
  ///
  /// In fr, this message translates to:
  /// **'Projet public'**
  String get publicProject;

  /// No description provided for @publicProjectHelp.
  ///
  /// In fr, this message translates to:
  /// **'Visible et utilisable par tous les membres'**
  String get publicProjectHelp;

  /// No description provided for @quantityHours.
  ///
  /// In fr, this message translates to:
  /// **'Quantité (h)'**
  String get quantityHours;

  /// No description provided for @readOnlyTimeOf.
  ///
  /// In fr, this message translates to:
  /// **'Temps de {name} : consultation seulement.'**
  String readOnlyTimeOf(String name);

  /// No description provided for @reject.
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get reject;

  /// No description provided for @remaining.
  ///
  /// In fr, this message translates to:
  /// **'restants'**
  String get remaining;

  /// No description provided for @remove.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get remove;

  /// No description provided for @removeMember.
  ///
  /// In fr, this message translates to:
  /// **'Retirer ce membre ?'**
  String get removeMember;

  /// No description provided for @removeMemberMessage.
  ///
  /// In fr, this message translates to:
  /// **'La personne perd l\'accès au workspace. Ses entrées passées sont conservées.'**
  String get removeMemberMessage;

  /// No description provided for @rename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer'**
  String get rename;

  /// No description provided for @reopen.
  ///
  /// In fr, this message translates to:
  /// **'Rouvrir'**
  String get reopen;

  /// No description provided for @repoAttached.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Dépôt rattaché à ce projet.} =1{Dépôt rattaché à ce projet, et 1 autre entrée.} other{Dépôt rattaché à ce projet, et {count} autres entrées.}}'**
  String repoAttached(int count);

  /// No description provided for @repoAttachOffline.
  ///
  /// In fr, this message translates to:
  /// **'Entrée enregistrée, mais le dépôt n\'a pas pu être rattaché : il faut être en ligne.'**
  String get repoAttachOffline;

  /// No description provided for @reports.
  ///
  /// In fr, this message translates to:
  /// **'Rapports'**
  String get reports;

  /// No description provided for @repoUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Entrée enregistrée, mais son dépôt est inconnu : rien à rattacher.'**
  String get repoUnknown;

  /// No description provided for @requestSent.
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée.'**
  String get requestSent;

  /// No description provided for @requestTimeOff.
  ///
  /// In fr, this message translates to:
  /// **'Demander une absence'**
  String get requestTimeOff;

  /// No description provided for @requireDescription.
  ///
  /// In fr, this message translates to:
  /// **'Description obligatoire'**
  String get requireDescription;

  /// No description provided for @requireProject.
  ///
  /// In fr, this message translates to:
  /// **'Projet obligatoire'**
  String get requireProject;

  /// No description provided for @requiresApproval.
  ///
  /// In fr, this message translates to:
  /// **'Validation requise'**
  String get requiresApproval;

  /// No description provided for @requiresApprovalHint.
  ///
  /// In fr, this message translates to:
  /// **'Un manager doit valider cette demande.'**
  String get requiresApprovalHint;

  /// No description provided for @resetEmailSent.
  ///
  /// In fr, this message translates to:
  /// **'Email de réinitialisation envoyé.'**
  String get resetEmailSent;

  /// No description provided for @restore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer'**
  String get restore;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @revoke.
  ///
  /// In fr, this message translates to:
  /// **'Révoquer'**
  String get revoke;

  /// No description provided for @revokeTokenConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Révoquer le jeton de « {name} » ? Ce poste n\'enverra plus le temps de Claude.'**
  String revokeTokenConfirm(String name);

  /// No description provided for @role.
  ///
  /// In fr, this message translates to:
  /// **'Rôle'**
  String get role;

  /// No description provided for @roleAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Administrateur'**
  String get roleAdmin;

  /// No description provided for @roleManager.
  ///
  /// In fr, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleMember.
  ///
  /// In fr, this message translates to:
  /// **'Membre'**
  String get roleMember;

  /// No description provided for @roleOwner.
  ///
  /// In fr, this message translates to:
  /// **'Propriétaire'**
  String get roleOwner;

  /// No description provided for @rounding.
  ///
  /// In fr, this message translates to:
  /// **'Arrondi des durées'**
  String get rounding;

  /// No description provided for @roundingHelp.
  ///
  /// In fr, this message translates to:
  /// **'Appliqué dans les rapports si demandé'**
  String get roundingHelp;

  /// No description provided for @runningTimer.
  ///
  /// In fr, this message translates to:
  /// **'Chronomètre en cours'**
  String get runningTimer;

  /// No description provided for @runningTimersCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 chronomètre en cours} other{{count} chronomètres en cours}}'**
  String runningTimersCount(int count);

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In fr, this message translates to:
  /// **'Enregistré.'**
  String get saved;

  /// No description provided for @schedule.
  ///
  /// In fr, this message translates to:
  /// **'Planning'**
  String get schedule;

  /// No description provided for @search.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get search;

  /// No description provided for @searchProjectOrTask.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un projet, une tâche, un client'**
  String get searchProjectOrTask;

  /// No description provided for @searchTags.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher ou créer un tag'**
  String get searchTags;

  /// No description provided for @sectionManage.
  ///
  /// In fr, this message translates to:
  /// **'Gestion'**
  String get sectionManage;

  /// No description provided for @sectionTeam.
  ///
  /// In fr, this message translates to:
  /// **'Équipe'**
  String get sectionTeam;

  /// No description provided for @selectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout cocher'**
  String get selectAll;

  /// No description provided for @selectProject.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un projet'**
  String get selectProject;

  /// No description provided for @selectTeammates.
  ///
  /// In fr, this message translates to:
  /// **'Choisir les collaborateurs'**
  String get selectTeammates;

  /// No description provided for @send.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get send;

  /// No description provided for @sendMagicLink.
  ///
  /// In fr, this message translates to:
  /// **'Recevoir un lien de connexion'**
  String get sendMagicLink;

  /// No description provided for @setPassword.
  ///
  /// In fr, this message translates to:
  /// **'Définir le mot de passe'**
  String get setPassword;

  /// No description provided for @setPasswordHelp.
  ///
  /// In fr, this message translates to:
  /// **'Utile après une invitation ou un lien magique'**
  String get setPasswordHelp;

  /// No description provided for @settings.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get settings;

  /// No description provided for @showArchived.
  ///
  /// In fr, this message translates to:
  /// **'Archivés'**
  String get showArchived;

  /// No description provided for @showSimilarEntries.
  ///
  /// In fr, this message translates to:
  /// **'Afficher les {count} entrées'**
  String showSimilarEntries(int count);

  /// No description provided for @signIn.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOut;

  /// No description provided for @signOutHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les données locales de cet appareil seront effacées.'**
  String get signOutHelp;

  /// No description provided for @signUp.
  ///
  /// In fr, this message translates to:
  /// **'Inscription'**
  String get signUp;

  /// No description provided for @similarEntriesEditHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les horaires de chaque entrée ne changent pas.'**
  String get similarEntriesEditHelp;

  /// No description provided for @similarEntriesLocked.
  ///
  /// In fr, this message translates to:
  /// **'Certaines entrées de ce groupe ne sont plus modifiables'**
  String get similarEntriesLocked;

  /// No description provided for @start.
  ///
  /// In fr, this message translates to:
  /// **'Démarrer'**
  String get start;

  /// No description provided for @startInFuture.
  ///
  /// In fr, this message translates to:
  /// **'L\'heure de début ne peut pas être dans le futur.'**
  String get startInFuture;

  /// No description provided for @startTime.
  ///
  /// In fr, this message translates to:
  /// **'Début'**
  String get startTime;

  /// No description provided for @statusApproved.
  ///
  /// In fr, this message translates to:
  /// **'Approuvée'**
  String get statusApproved;

  /// No description provided for @statusCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Annulée'**
  String get statusCancelled;

  /// No description provided for @statusNotSubmitted.
  ///
  /// In fr, this message translates to:
  /// **'Semaine non soumise'**
  String get statusNotSubmitted;

  /// No description provided for @statusPending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get statusPending;

  /// No description provided for @statusRejected.
  ///
  /// In fr, this message translates to:
  /// **'Refusée'**
  String get statusRejected;

  /// No description provided for @statusSubmitted.
  ///
  /// In fr, this message translates to:
  /// **'En attente d\'approbation'**
  String get statusSubmitted;

  /// No description provided for @statusWithdrawn.
  ///
  /// In fr, this message translates to:
  /// **'Retirée'**
  String get statusWithdrawn;

  /// No description provided for @stop.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter'**
  String get stop;

  /// No description provided for @submitForApproval.
  ///
  /// In fr, this message translates to:
  /// **'Soumettre pour approbation'**
  String get submitForApproval;

  /// No description provided for @submittedForApproval.
  ///
  /// In fr, this message translates to:
  /// **'Semaine soumise ({total}).'**
  String submittedForApproval(String total);

  /// No description provided for @subtotal.
  ///
  /// In fr, this message translates to:
  /// **'Sous-total HT'**
  String get subtotal;

  /// No description provided for @summary.
  ///
  /// In fr, this message translates to:
  /// **'Résumé'**
  String get summary;

  /// No description provided for @switchWorkspace.
  ///
  /// In fr, this message translates to:
  /// **'Changer de workspace'**
  String get switchWorkspace;

  /// No description provided for @syncStatus.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisation'**
  String get syncStatus;

  /// No description provided for @synced.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisé'**
  String get synced;

  /// No description provided for @syncing.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisation…'**
  String get syncing;

  /// No description provided for @systemLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue du système'**
  String get systemLanguage;

  /// No description provided for @tag.
  ///
  /// In fr, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @tagline.
  ///
  /// In fr, this message translates to:
  /// **'Suivi du temps libre et auto-hébergé'**
  String get tagline;

  /// No description provided for @tags.
  ///
  /// In fr, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @taskCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 tâche} other{{count} tâches}}'**
  String taskCount(int count);

  /// No description provided for @taskCreation.
  ///
  /// In fr, this message translates to:
  /// **'Création de tâches'**
  String get taskCreation;

  /// No description provided for @taskCreationEveryone.
  ///
  /// In fr, this message translates to:
  /// **'Tout le monde'**
  String get taskCreationEveryone;

  /// No description provided for @taskCreationHelp.
  ///
  /// In fr, this message translates to:
  /// **'Qui peut créer une tâche depuis le sélecteur de projet (chronomètre, saisie).'**
  String get taskCreationHelp;

  /// No description provided for @taskCreationManagers.
  ///
  /// In fr, this message translates to:
  /// **'Managers et administrateurs'**
  String get taskCreationManagers;

  /// No description provided for @tax.
  ///
  /// In fr, this message translates to:
  /// **'TVA'**
  String get tax;

  /// No description provided for @taxPercent.
  ///
  /// In fr, this message translates to:
  /// **'TVA'**
  String get taxPercent;

  /// No description provided for @team.
  ///
  /// In fr, this message translates to:
  /// **'Équipe'**
  String get team;

  /// No description provided for @teamEntry.
  ///
  /// In fr, this message translates to:
  /// **'Pointage d\'équipe'**
  String get teamEntry;

  /// No description provided for @teamEntryHelp.
  ///
  /// In fr, this message translates to:
  /// **'Cochez les présents : une entrée est créée pour chacun, même hors ligne. Touchez les horaires d\'une personne pour les ajuster.'**
  String get teamEntryHelp;

  /// No description provided for @teamManagerOf.
  ///
  /// In fr, this message translates to:
  /// **'Chef d\'équipe de…'**
  String get teamManagerOf;

  /// No description provided for @teamManagerOfHelp.
  ///
  /// In fr, this message translates to:
  /// **'Ce membre verra le temps des personnes choisies et approuvera leurs feuilles de temps. La saisie pour autrui dépend du réglage du workspace.'**
  String get teamManagerOfHelp;

  /// No description provided for @teamMemberHint.
  ///
  /// In fr, this message translates to:
  /// **'Seuls les managers voient l\'activité de toute l\'équipe.'**
  String get teamMemberHint;

  /// No description provided for @teamRequests.
  ///
  /// In fr, this message translates to:
  /// **'Demandes de l\'équipe'**
  String get teamRequests;

  /// No description provided for @teammate.
  ///
  /// In fr, this message translates to:
  /// **'Collaborateur'**
  String get teammate;

  /// No description provided for @teammates.
  ///
  /// In fr, this message translates to:
  /// **'Collaborateurs'**
  String get teammates;

  /// No description provided for @thisMonth.
  ///
  /// In fr, this message translates to:
  /// **'Ce mois-ci'**
  String get thisMonth;

  /// No description provided for @thisWeek.
  ///
  /// In fr, this message translates to:
  /// **'Cette semaine'**
  String get thisWeek;

  /// No description provided for @thisYear.
  ///
  /// In fr, this message translates to:
  /// **'Cette année'**
  String get thisYear;

  /// No description provided for @timeForOthers.
  ///
  /// In fr, this message translates to:
  /// **'Saisie du temps pour autrui'**
  String get timeForOthers;

  /// No description provided for @timeForOthersAdmins.
  ///
  /// In fr, this message translates to:
  /// **'Administrateurs'**
  String get timeForOthersAdmins;

  /// No description provided for @timeForOthersAdminsAndTeamManagers.
  ///
  /// In fr, this message translates to:
  /// **'Administrateurs et chefs d\'équipe'**
  String get timeForOthersAdminsAndTeamManagers;

  /// No description provided for @timeForOthersHelp.
  ///
  /// In fr, this message translates to:
  /// **'Qui peut saisir et modifier le temps des autres membres.'**
  String get timeForOthersHelp;

  /// No description provided for @timeOff.
  ///
  /// In fr, this message translates to:
  /// **'Absences'**
  String get timeOff;

  /// No description provided for @timeTracker.
  ///
  /// In fr, this message translates to:
  /// **'Suivi du temps'**
  String get timeTracker;

  /// No description provided for @timerAlreadyRunningOnTask.
  ///
  /// In fr, this message translates to:
  /// **'Un chronomètre tourne déjà sur cette tâche'**
  String get timerAlreadyRunningOnTask;

  /// No description provided for @timesheet.
  ///
  /// In fr, this message translates to:
  /// **'Feuille de temps'**
  String get timesheet;

  /// No description provided for @toApprove.
  ///
  /// In fr, this message translates to:
  /// **'À valider'**
  String get toApprove;

  /// No description provided for @today.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get today;

  /// No description provided for @total.
  ///
  /// In fr, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @totalInclTax.
  ///
  /// In fr, this message translates to:
  /// **'Total TTC'**
  String get totalInclTax;

  /// No description provided for @totalTime.
  ///
  /// In fr, this message translates to:
  /// **'Temps total'**
  String get totalTime;

  /// No description provided for @tracked.
  ///
  /// In fr, this message translates to:
  /// **'Suivi'**
  String get tracked;

  /// No description provided for @unitPrice.
  ///
  /// In fr, this message translates to:
  /// **'Prix unitaire HT'**
  String get unitPrice;

  /// No description provided for @unlimited.
  ///
  /// In fr, this message translates to:
  /// **'Illimité'**
  String get unlimited;

  /// No description provided for @unlock.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller'**
  String get unlock;

  /// No description provided for @unpaid.
  ///
  /// In fr, this message translates to:
  /// **'Non rémunérée'**
  String get unpaid;

  /// No description provided for @used.
  ///
  /// In fr, this message translates to:
  /// **'Pris'**
  String get used;

  /// No description provided for @user.
  ///
  /// In fr, this message translates to:
  /// **'Utilisateur'**
  String get user;

  /// No description provided for @userGuide.
  ///
  /// In fr, this message translates to:
  /// **'Guide d\'utilisation'**
  String get userGuide;

  /// No description provided for @userGuideHelp.
  ///
  /// In fr, this message translates to:
  /// **'Comment utiliser Clockifai selon votre rôle, avec des vidéos de démonstration.'**
  String get userGuideHelp;

  /// No description provided for @users.
  ///
  /// In fr, this message translates to:
  /// **'Utilisateurs'**
  String get users;

  /// No description provided for @view.
  ///
  /// In fr, this message translates to:
  /// **'Consulter'**
  String get view;

  /// No description provided for @weekOf.
  ///
  /// In fr, this message translates to:
  /// **'Semaine du {date}'**
  String weekOf(String date);

  /// No description provided for @weekStartsOn.
  ///
  /// In fr, this message translates to:
  /// **'La semaine commence le'**
  String get weekStartsOn;

  /// No description provided for @weekTotal.
  ///
  /// In fr, this message translates to:
  /// **'Total semaine'**
  String get weekTotal;

  /// No description provided for @weeksCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 semaine} other{{count} semaines}}'**
  String weeksCount(int count);

  /// No description provided for @whatAreYouWorkingOn.
  ///
  /// In fr, this message translates to:
  /// **'Sur quoi travaillez-vous ?'**
  String get whatAreYouWorkingOn;

  /// No description provided for @withdraw.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get withdraw;

  /// No description provided for @workspaceCreated.
  ///
  /// In fr, this message translates to:
  /// **'Workspace créé. Il apparaîtra après synchronisation.'**
  String get workspaceCreated;

  /// No description provided for @workspaceSettings.
  ///
  /// In fr, this message translates to:
  /// **'Réglages du workspace'**
  String get workspaceSettings;

  /// No description provided for @workspaces.
  ///
  /// In fr, this message translates to:
  /// **'Workspaces'**
  String get workspaces;

  /// No description provided for @year.
  ///
  /// In fr, this message translates to:
  /// **'an'**
  String get year;

  /// No description provided for @yesterday.
  ///
  /// In fr, this message translates to:
  /// **'Hier'**
  String get yesterday;

  /// No description provided for @yourName.
  ///
  /// In fr, this message translates to:
  /// **'Votre nom'**
  String get yourName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
