// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get account => 'Account';

  @override
  String get activate => 'Activate';

  @override
  String get addHoliday => 'Add holiday';

  @override
  String get addLine => 'Add line';

  @override
  String get addManualEntry => 'Add time entry';

  @override
  String get addRow => 'Add row';

  @override
  String get addTags => 'Add tags';

  @override
  String get addTask => 'Add task';

  @override
  String get addTimeForOthers => 'Add time for others';

  @override
  String get adminOnlySettings => 'Only admins can change these settings.';

  @override
  String get agentBadge => 'Agent';

  @override
  String get agentInactive =>
      'Your agent was deactivated or removed by an administrator: your Claude Code sessions no longer record time.';

  @override
  String get agents => 'Agents';

  @override
  String get agentsHelp =>
      'Claude agents: their time is recorded by Claude Code, one agent per person who connected a computer (Settings › Integrations).';

  @override
  String agentTimeOf(String name) {
    return 'Time of $name: you can correct its entries, not add new ones.';
  }

  @override
  String get allClients => 'All clients';

  @override
  String get allMembers => 'All members';

  @override
  String get allProjects => 'All projects';

  @override
  String get allowance => 'Allowance';

  @override
  String allowanceOverrideHelp(String value) {
    return 'Leave empty to use the policy allowance ($value).';
  }

  @override
  String get alwaysAttachRepo =>
      'Always attach this repository to this project';

  @override
  String get alwaysAttachRepoHelp =>
      'Claude\'s next sessions in this repository will go to this project, and so will its entries without a project from the past week.';

  @override
  String get amount => 'Amount';

  @override
  String get annualAllowance => 'Annual allowance';

  @override
  String apiTokenCreated(String name) {
    return 'Token created for “$name”. It won\'t be shown again: follow these three steps now.';
  }

  @override
  String get apply => 'Apply';

  @override
  String applyRounding(int minutes) {
    return 'Round to $minutes min';
  }

  @override
  String get approvals => 'Approvals';

  @override
  String get approve => 'Approve';

  @override
  String approvedPeriodFor(String name) {
    return 'Period already approved for $name.';
  }

  @override
  String get approvers => 'Approvers';

  @override
  String get approversManagers => 'Managers';

  @override
  String get approversManagersAndTeamManagers => 'Managers and team managers';

  @override
  String get archive => 'Archive';

  @override
  String get archived => 'Archived';

  @override
  String get autoStopTimers => 'Auto-stop timers';

  @override
  String get autoStopTimersHelp => 'Stops forgotten timers after this duration';

  @override
  String balancesFor(int year) {
    return 'My balances $year';
  }

  @override
  String get billable => 'Billable';

  @override
  String get billableAndNot => 'Billable and non-billable';

  @override
  String get billableByDefault => 'Billable by default';

  @override
  String get billableRate => 'Billable rate (per hour)';

  @override
  String get billableTime => 'Billable time';

  @override
  String get billing => 'Billing';

  @override
  String get billingAddress => 'Billing address';

  @override
  String get billingEmail => 'Billing email';

  @override
  String get budgetHours => 'Budget';

  @override
  String budgetUsed(int percent, int hours) {
    return '$percent% of $hours h budget';
  }

  @override
  String get calendar => 'Calendar';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String cannotOpenLink(String url) {
    return 'Could not open $url';
  }

  @override
  String changeRejected(String message) {
    return 'Change rejected by the server: $message';
  }

  @override
  String get changeRejectedPermission =>
      'Change rejected: insufficient rights or locked period. It has been reverted.';

  @override
  String get checkYourEmail => 'Check your inbox to confirm your account.';

  @override
  String claudeCodeHelp(String agent) {
    return 'Time spent by your Claude Code sessions, under your agent “$agent”';
  }

  @override
  String claudeCodeIntro(String agent) {
    return 'Each Claude Code session becomes time of your agent “$agent”, a member of the team: a timer starts at the first prompt and stops after 10 minutes without activity, at the time of the last activity. Connect every computer where you use Claude Code (terminal, VSCode, desktop app).';
  }

  @override
  String get claudeCodeLocalInstance =>
      'Local instance: Claude Code only accepts a marketplace over https, so this one is the integrations/ folder of your copy of the repository.';

  @override
  String get claudeCodeRequirements =>
      'You need an up-to-date claude command in the terminal, and python3 (on a Mac, the developer tools: xcode-select --install).';

  @override
  String get claudeCodeStepInstall =>
      '1. In a terminal (the Claude Code panel in VSCode has no /plugin):';

  @override
  String get claudeCodeStepStart =>
      '3. Open a new Claude Code conversation: Claude\'s timer starts at the first prompt.';

  @override
  String get claudeCodeStepToken =>
      '2. Copy the token, then save it in the plugin:';

  @override
  String get client => 'Client';

  @override
  String get clients => 'Clients';

  @override
  String get close => 'Close';

  @override
  String get color => 'Color';

  @override
  String get companyDetails => 'Company details (address, VAT…)';

  @override
  String get companyDetailsHint => 'Shown in the invoice header';

  @override
  String get companyName => 'Company name';

  @override
  String get computerName => 'Computer name';

  @override
  String get confirm => 'Confirm';

  @override
  String get connectComputer => 'Connect a computer';

  @override
  String get connectedComputers => 'Connected computers';

  @override
  String get connection => 'Connection';

  @override
  String get continueEntry => 'Continue';

  @override
  String get copied => 'Copied.';

  @override
  String get copy => 'Copy';

  @override
  String get copyToken => 'Copy token';

  @override
  String get costRate => 'Cost rate (per hour)';

  @override
  String get createAccount => 'Create account';

  @override
  String get createEntries => 'Create entries';

  @override
  String get createProject => 'Create project';

  @override
  String createTagNamed(String name) {
    return 'Create tag \"$name\"';
  }

  @override
  String get createTask => 'Create task';

  @override
  String createTaskIn(String name) {
    return 'Create task \"$name\" in:';
  }

  @override
  String get createWorkspace => 'Create workspace';

  @override
  String get currency => 'Currency';

  @override
  String get currencyOverride => 'Specific currency (optional)';

  @override
  String get customRange => 'Custom range';

  @override
  String get date => 'Date';

  @override
  String get day => 'Day';

  @override
  String get days => 'Days';

  @override
  String get daysRequested => 'Number of days';

  @override
  String get daysShort => 'd';

  @override
  String get deactivate => 'Deactivate';

  @override
  String get decision => 'Decision';

  @override
  String get defaultHours => 'Default hours';

  @override
  String get delete => 'Delete';

  @override
  String get deleteClient => 'Delete client?';

  @override
  String get deleteClientMessage =>
      'Projects of this client are kept, without a client.';

  @override
  String get deleteEntry => 'Delete entry?';

  @override
  String get deleteEntryMessage =>
      'This time entry will be deleted on all your devices.';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get deleteGroupMessage =>
      'Members stay in the workspace; team managers no longer manage this group.';

  @override
  String get deleteInvoice => 'Delete invoice?';

  @override
  String get deleteInvoiceMessage => 'Time entries become billable again.';

  @override
  String get deletePolicy => 'Delete policy?';

  @override
  String get deleteProject => 'Delete project?';

  @override
  String get deleteProjectMessage =>
      'Existing entries are kept but no longer linked to a visible project.';

  @override
  String deleteSimilarEntries(int count) {
    return 'Delete the $count entries';
  }

  @override
  String deleteSimilarEntriesMessage(int count) {
    return 'The $count entries of this group will be deleted.';
  }

  @override
  String get deleteTag => 'Delete tag?';

  @override
  String get description => 'Description';

  @override
  String get descriptionRequired =>
      'A description is required in this workspace.';

  @override
  String get detailed => 'Detailed';

  @override
  String get discardTimer => 'Discard timer';

  @override
  String get discardTimerMessage => 'The running time will not be saved.';

  @override
  String get discount => 'Discount';

  @override
  String get discountPercent => 'Discount';

  @override
  String get draftNumberPending => 'Draft';

  @override
  String get due => 'due';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get duration => 'Duration';

  @override
  String get edit => 'Edit';

  @override
  String get editAssignment => 'Edit assignment';

  @override
  String get editClient => 'Edit client';

  @override
  String get editEntry => 'Edit entry';

  @override
  String get editPolicy => 'Edit policy';

  @override
  String get editProject => 'Edit project';

  @override
  String get editRates => 'Edit rates';

  @override
  String editSimilarEntries(int count) {
    return 'Edit the $count entries';
  }

  @override
  String get editTag => 'Edit tag';

  @override
  String get editTimer => 'Edit timer';

  @override
  String get email => 'Email';

  @override
  String get emailRequired => 'Enter your email address.';

  @override
  String get emptyIsUnlimited => 'Empty = unlimited';

  @override
  String get endTime => 'End';

  @override
  String get endTimeRequired => 'Enter an end time.';

  @override
  String get endsNextDay => 'Ends the next day.';

  @override
  String enteredBy(String name) {
    return 'entered by $name';
  }

  @override
  String enteringFor(String name) {
    return 'You are entering time for $name.';
  }

  @override
  String entriesCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries created',
      one: '1 entry created',
    );
    return '$_temp0';
  }

  @override
  String get entryLocked => 'Locked entry: only an admin can change it.';

  @override
  String get environmentLocal => 'Local version';

  @override
  String get environmentProduction => 'Production';

  @override
  String get export => 'Export';

  @override
  String get exportCsvOffline => 'CSV (offline)';

  @override
  String get exportDone => 'Export downloaded.';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get firstSync => 'First synchronisation in progress…';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get generate => 'Generate';

  @override
  String get groupBy => 'Group by';

  @override
  String get groupMembers => 'Group members';

  @override
  String get groupName => 'Group name';

  @override
  String get groupSimilarEntries => 'Group similar entries';

  @override
  String get groupSimilarEntriesHelp =>
      'Time tracker: entries of the same day with the same description, project, task, tags and billable status are shown on one expandable row';

  @override
  String get groups => 'Groups';

  @override
  String get halfDay => 'Half day';

  @override
  String get help => 'Help';

  @override
  String get hideSimilarEntries => 'Hide details';

  @override
  String get history => 'History';

  @override
  String get holidays => 'Holidays';

  @override
  String get hourlyRate => 'Hourly rate';

  @override
  String get hours => 'Hours';

  @override
  String get hoursPerDay => 'Hours per day';

  @override
  String get hoursRequested => 'Number of hours';

  @override
  String get integrations => 'Integrations';

  @override
  String get invalidDuration => 'Invalid duration (e.g. 1:30, 1.5, 90m).';

  @override
  String get invalidHours => 'Invalid hours (between 0 and 24).';

  @override
  String invitationFailed(String error) {
    return 'Invitation failed: $error';
  }

  @override
  String get invitationSent => 'Invitation sent.';

  @override
  String get invite => 'Invite';

  @override
  String get inviteHelp =>
      'Existing users are added right away. Otherwise an invitation link is created.';

  @override
  String get inviteLinkMessage =>
      'No email server is configured. Send this link to the invitee:';

  @override
  String get inviteLinkTitle => 'Invitation link';

  @override
  String get inviteMember => 'Invite a member';

  @override
  String get invoice => 'Invoice';

  @override
  String get invoiceDraft => 'Draft';

  @override
  String get invoiceNote => 'Notes / terms';

  @override
  String get invoiceNoteHint => 'Payment terms, IBAN… (Enter to save)';

  @override
  String get invoicePaid => 'Paid';

  @override
  String get invoicePrefix => 'Number prefix';

  @override
  String get invoiceSent => 'Sent';

  @override
  String get invoiceVoid => 'Void';

  @override
  String get invoices => 'Invoices';

  @override
  String get kiosk => 'Kiosk';

  @override
  String kioskClockInAs(String name) {
    return 'Clock in: $name';
  }

  @override
  String kioskClockOutAs(String name) {
    return 'Clock out: $name';
  }

  @override
  String get kioskClockedIn => 'Clock-in recorded.';

  @override
  String get kioskClockedOut => 'Clock-out recorded.';

  @override
  String get kioskDevices => 'Kiosk devices';

  @override
  String get kioskDevicesHelp =>
      'Shared tablets where the team clocks in with a PIN';

  @override
  String get kioskExit => 'Exit kiosk mode';

  @override
  String kioskGoodbye(String name) {
    return 'Goodbye $name!';
  }

  @override
  String kioskHello(String name) {
    return 'Hello $name!';
  }

  @override
  String get kioskMode => 'Kiosk mode (shared tablet)';

  @override
  String get kioskNoPin =>
      'This person has not set a PIN yet (Settings > Kiosk PIN).';

  @override
  String get kioskPin => 'Kiosk PIN';

  @override
  String get kioskPinHelp => 'To clock in on a shared tablet';

  @override
  String get kioskPinInvalid => 'PIN must be 4 to 8 digits.';

  @override
  String get kioskPinLabel => 'New PIN (4 to 8 digits)';

  @override
  String get kioskPinSaved => 'PIN saved.';

  @override
  String get kioskReset => 'Unlink this device';

  @override
  String get kioskResetMessage => 'The token will be removed from this device.';

  @override
  String get kioskSetupHelp =>
      'Paste the device token created by an admin in Settings > Kiosk devices.';

  @override
  String get kioskTapYourName => 'Tap your name to clock in or out';

  @override
  String get kioskToken => 'Device token';

  @override
  String get kioskTokenInvalid => 'Invalid or revoked token.';

  @override
  String get kioskTokenOnce =>
      'Copy this token now, it will not be shown again. Enter it on the tablet in kiosk mode.';

  @override
  String get kioskTooManyAttempts =>
      'Too many attempts. Try again in a few minutes.';

  @override
  String get kioskWrongPin => 'Wrong PIN.';

  @override
  String get language => 'Language';

  @override
  String lastEventHoursAgo(int hours) {
    return 'Last event $hours h ago';
  }

  @override
  String get lastEventJustNow => 'Last event just now';

  @override
  String lastEventMinutesAgo(int minutes) {
    return 'Last event $minutes min ago';
  }

  @override
  String get lastEventNever => 'No event received yet';

  @override
  String lastEventOn(String date) {
    return 'Last event on $date';
  }

  @override
  String get lastMonth => 'Last month';

  @override
  String get lastSeen => 'Last seen';

  @override
  String get lastSync => 'Last sync';

  @override
  String get lastWeek => 'Last week';

  @override
  String get launchAtLogin => 'Start at login';

  @override
  String get launchAtLoginApproval =>
      'Allow it in System Settings > General > Login Items.';

  @override
  String get launchAtLoginHelp =>
      'Clockifai opens in the menu bar, without a window.';

  @override
  String get loadMore => 'Load more';

  @override
  String get lockEntriesBefore => 'Lock entries before';

  @override
  String get lockEntriesNone => 'No lock';

  @override
  String get magicLinkSent => 'Sign-in link sent by email.';

  @override
  String managedByLabel(String names) {
    return 'Team manager: $names';
  }

  @override
  String get managersOnly => 'Managers only';

  @override
  String managesLabel(String names) {
    return 'Manages: $names';
  }

  @override
  String get markDone => 'Mark as done';

  @override
  String get member => 'Member';

  @override
  String get memberAllowances => 'Allowances per member';

  @override
  String memberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No members',
    );
    return '$_temp0';
  }

  @override
  String get members => 'Members';

  @override
  String get menuBarOpenApp => 'Open Clockifai';

  @override
  String get menuBarQuit => 'Quit Clockifai';

  @override
  String get menuBarRecent => 'Recent';

  @override
  String get menuBarSignIn =>
      'Sign in from the Clockifai window to track your time.';

  @override
  String get more => 'More';

  @override
  String get myRequests => 'My requests';

  @override
  String get name => 'Name';

  @override
  String get never => 'Never';

  @override
  String get neverSeen => 'Never connected';

  @override
  String get newAssignment => 'New assignment';

  @override
  String get newClient => 'New client';

  @override
  String get newGroup => 'New group';

  @override
  String get newInvoice => 'New invoice';

  @override
  String get newInvoiceHelp =>
      'One line per project is created from the client\'s billable, not yet invoiced time in the period.';

  @override
  String get newKioskDevice => 'New device';

  @override
  String get newPassword => 'New password (min. 8 characters)';

  @override
  String get newPolicy => 'New policy';

  @override
  String get newProject => 'New project';

  @override
  String get newTag => 'New tag';

  @override
  String get newTask => 'New task';

  @override
  String newTaskIn(String project) {
    return 'New task in $project';
  }

  @override
  String get nextWeek => 'Next week';

  @override
  String get noApproval => 'No approval';

  @override
  String get noClient => 'No client';

  @override
  String get noClients => 'No clients';

  @override
  String get noConnectedComputers => 'No computer connected yet.';

  @override
  String get noDataForPeriod => 'No data for this period';

  @override
  String get noDescription => '(no description)';

  @override
  String get noEntriesInPeriod => 'No entries in this period';

  @override
  String get noEntriesYet => 'No time entries yet';

  @override
  String get noEntriesYetMessage =>
      'Start the timer above or add time manually.';

  @override
  String get noGroups => 'No groups yet';

  @override
  String get noGroupsMessage =>
      'Group members (team, site, company) to assign them to a team manager.';

  @override
  String get noHistory => 'No history';

  @override
  String get noHolidays => 'No holidays';

  @override
  String get noInvoices => 'No invoices';

  @override
  String get noInvoicesMessage =>
      'Generate an invoice from a client\'s billable time.';

  @override
  String get noMatch => 'No results';

  @override
  String get noMembers => 'No members';

  @override
  String get noPoliciesYet => 'No time-off type defined yet.';

  @override
  String get noProject => 'No project';

  @override
  String get noProjects => 'No projects';

  @override
  String get noProjectsMessage => 'Create a project to organise your time.';

  @override
  String get noRequests => 'No requests';

  @override
  String get noTag => 'No tag';

  @override
  String get noTags => 'No tags';

  @override
  String get noTasks => 'No tasks';

  @override
  String get noTeammateSelected => 'Select at least one person.';

  @override
  String get noWorkspace => 'No workspace';

  @override
  String get noWorkspaceMessage =>
      'Your account has no active workspace. Ask an admin for an invitation.';

  @override
  String get nonBillable => 'Non-billable';

  @override
  String get none => 'None';

  @override
  String get notConfigured =>
      'App not configured: run `make app-config` and restart with --dart-define-from-file.';

  @override
  String get note => 'Note';

  @override
  String get noteOptional => 'Comment (optional)';

  @override
  String get nothingToApprove => 'Nothing to approve';

  @override
  String get nothingToInvoice =>
      'No billable, uninvoiced time for this client in the period.';

  @override
  String get offline => 'Offline';

  @override
  String get offlineExplanation =>
      'Your changes are stored on the device and sent automatically when the connection is back.';

  @override
  String get oldestTimerStopped =>
      'Limit reached: the oldest timer was stopped';

  @override
  String get online => 'Online';

  @override
  String get onlineOnly => 'Not available offline.';

  @override
  String get openSystemSettings => 'Open Settings';

  @override
  String otherRunningTimers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ $count others',
      one: '+ 1 other',
    );
    return '$_temp0';
  }

  @override
  String get paid => 'Paid';

  @override
  String get parallelTimers => 'Simultaneous timers';

  @override
  String get parallelTimersHelp =>
      'How many timers a member can run at once; beyond that, the oldest one stops';

  @override
  String get password => 'Password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters.';

  @override
  String get passwordUpdated => 'Password updated.';

  @override
  String get paymentTermDays => 'Payment term (days)';

  @override
  String get pending => 'Pending';

  @override
  String get pendingChanges => 'Changes waiting to upload';

  @override
  String peopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
      zero: 'Nobody',
    );
    return '$_temp0';
  }

  @override
  String get perHour => '/h';

  @override
  String pilotedBy(String name) {
    return 'Agent of $name';
  }

  @override
  String get policies => 'Time-off policies';

  @override
  String get policy => 'Time-off type';

  @override
  String get policyExample => 'Vacation, Sick leave…';

  @override
  String get previousWeek => 'Previous week';

  @override
  String get profile => 'Profile';

  @override
  String get project => 'Project';

  @override
  String projectCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
      zero: 'no projects',
    );
    return '$_temp0';
  }

  @override
  String get projectRequired => 'A project is required in this workspace.';

  @override
  String get projects => 'Projects';

  @override
  String get publicProject => 'Public project';

  @override
  String get publicProjectHelp => 'Visible and usable by all members';

  @override
  String get quantityHours => 'Quantity (h)';

  @override
  String readOnlyTimeOf(String name) {
    return '$name\'s time: view only.';
  }

  @override
  String get reject => 'Reject';

  @override
  String get remaining => 'left';

  @override
  String get remove => 'Remove';

  @override
  String get removeMember => 'Remove this member?';

  @override
  String get removeMemberMessage =>
      'The person loses access to the workspace. Past entries are kept.';

  @override
  String get rename => 'Rename';

  @override
  String get reopen => 'Reopen';

  @override
  String repoAttached(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Repository attached to this project, and $count other entries.',
      one: 'Repository attached to this project, and 1 other entry.',
      zero: 'Repository attached to this project.',
    );
    return '$_temp0';
  }

  @override
  String get repoAttachOffline =>
      'Entry saved, but the repository could not be attached: you need to be online.';

  @override
  String get reports => 'Reports';

  @override
  String get repoUnknown =>
      'Entry saved, but its repository is unknown: nothing to attach.';

  @override
  String get requestSent => 'Request sent.';

  @override
  String get requestTimeOff => 'Request time off';

  @override
  String get requireDescription => 'Description required';

  @override
  String get requireProject => 'Project required';

  @override
  String get requiresApproval => 'Requires approval';

  @override
  String get requiresApprovalHint => 'A manager must approve this request.';

  @override
  String get resetEmailSent => 'Password reset email sent.';

  @override
  String get restore => 'Restore';

  @override
  String get retry => 'Retry';

  @override
  String get revoke => 'Revoke';

  @override
  String revokeTokenConfirm(String name) {
    return 'Revoke the token of “$name”? This computer will no longer send Claude\'s time.';
  }

  @override
  String get role => 'Role';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleMember => 'Member';

  @override
  String get roleOwner => 'Owner';

  @override
  String get rounding => 'Duration rounding';

  @override
  String get roundingHelp => 'Applied in reports on request';

  @override
  String get runningTimer => 'Running timer';

  @override
  String runningTimersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running timers',
      one: '1 running timer',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved.';

  @override
  String get schedule => 'Schedule';

  @override
  String get search => 'Search';

  @override
  String get searchProjectOrTask => 'Search project, task or client';

  @override
  String get searchTags => 'Search or create a tag';

  @override
  String get sectionManage => 'Manage';

  @override
  String get sectionTeam => 'Team';

  @override
  String get selectAll => 'Select all';

  @override
  String get selectProject => 'Select project';

  @override
  String get selectTeammates => 'Select teammates';

  @override
  String get send => 'Send';

  @override
  String get sendMagicLink => 'Email me a sign-in link';

  @override
  String get setPassword => 'Set password';

  @override
  String get setPasswordHelp => 'Useful after an invitation or a magic link';

  @override
  String get settings => 'Settings';

  @override
  String get showArchived => 'Archived';

  @override
  String showSimilarEntries(int count) {
    return 'Show the $count entries';
  }

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutHelp => 'Local data on this device will be erased.';

  @override
  String get signUp => 'Sign up';

  @override
  String get similarEntriesEditHelp => 'The times of each entry stay the same.';

  @override
  String get similarEntriesLocked =>
      'Some entries of this group can no longer be edited';

  @override
  String get start => 'Start';

  @override
  String get startInFuture => 'Start time cannot be in the future.';

  @override
  String get startTime => 'Start';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusNotSubmitted => 'Week not submitted';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusSubmitted => 'Awaiting approval';

  @override
  String get statusWithdrawn => 'Withdrawn';

  @override
  String get stop => 'Stop';

  @override
  String get submitForApproval => 'Submit for approval';

  @override
  String submittedForApproval(String total) {
    return 'Week submitted ($total).';
  }

  @override
  String get subtotal => 'Subtotal';

  @override
  String get summary => 'Summary';

  @override
  String get switchWorkspace => 'Switch workspace';

  @override
  String get syncStatus => 'Synchronisation';

  @override
  String get synced => 'Synced';

  @override
  String get syncing => 'Syncing…';

  @override
  String get systemLanguage => 'System language';

  @override
  String get tag => 'Tag';

  @override
  String get tagline => 'Free, self-hosted time tracking';

  @override
  String get tags => 'Tags';

  @override
  String taskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get taskCreation => 'Task creation';

  @override
  String get taskCreationEveryone => 'Everyone';

  @override
  String get taskCreationHelp =>
      'Who can create a task from the project picker (timer, entries).';

  @override
  String get taskCreationManagers => 'Managers and admins';

  @override
  String get tax => 'Tax';

  @override
  String get taxPercent => 'Tax';

  @override
  String get team => 'Team';

  @override
  String get teamEntry => 'Team entry';

  @override
  String get teamEntryHelp =>
      'Tick who was there: one entry is created for each person, even offline. Tap someone\'s hours to adjust them.';

  @override
  String get teamManagerOf => 'Team manager of…';

  @override
  String get teamManagerOfHelp =>
      'This member will see the selected people\'s time and approve their timesheets. Entering time for them depends on the workspace setting.';

  @override
  String get teamMemberHint =>
      'Only managers can see the whole team\'s activity.';

  @override
  String get teamRequests => 'Team requests';

  @override
  String get teammate => 'Teammate';

  @override
  String get teammates => 'Teammates';

  @override
  String get thisMonth => 'This month';

  @override
  String get thisWeek => 'This week';

  @override
  String get thisYear => 'This year';

  @override
  String get timeForOthers => 'Time entry for others';

  @override
  String get timeForOthersAdmins => 'Admins';

  @override
  String get timeForOthersAdminsAndTeamManagers => 'Admins and team managers';

  @override
  String get timeForOthersHelp => 'Who can add and edit other members\' time.';

  @override
  String get timeOff => 'Time off';

  @override
  String get timeTracker => 'Time tracker';

  @override
  String get timerAlreadyRunningOnTask =>
      'A timer is already running on this task';

  @override
  String get timesheet => 'Timesheet';

  @override
  String get toApprove => 'To approve';

  @override
  String get today => 'Today';

  @override
  String get total => 'Total';

  @override
  String get totalInclTax => 'Total';

  @override
  String get totalTime => 'Total time';

  @override
  String get tracked => 'Tracked';

  @override
  String get unitPrice => 'Unit price';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get unlock => 'Unlock';

  @override
  String get unpaid => 'Unpaid';

  @override
  String get used => 'Used';

  @override
  String get user => 'User';

  @override
  String get userGuide => 'User guide';

  @override
  String get userGuideHelp =>
      'How to use Clockifai for your role, with demo videos (in French).';

  @override
  String get users => 'Users';

  @override
  String get view => 'View';

  @override
  String weekOf(String date) {
    return 'Week of $date';
  }

  @override
  String get weekStartsOn => 'Week starts on';

  @override
  String get weekTotal => 'Week total';

  @override
  String weeksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks',
      one: '1 week',
    );
    return '$_temp0';
  }

  @override
  String get whatAreYouWorkingOn => 'What are you working on?';

  @override
  String get withdraw => 'Withdraw';

  @override
  String get workspaceCreated =>
      'Workspace created. It will appear after sync.';

  @override
  String get workspaceSettings => 'Workspace settings';

  @override
  String get workspaces => 'Workspaces';

  @override
  String get year => 'year';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get yourName => 'Your name';
}
