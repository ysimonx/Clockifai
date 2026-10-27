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
  String get agentBillableHelp =>
      'For Claude Code sessions attached to this project';

  @override
  String get agentBillableWorkspace => 'Same as the workspace setting';

  @override
  String get agentBilling => 'Claude agents\' time';

  @override
  String get agentBillingHelp =>
      'Whether a session recorded by Claude Code is billable; a project can override it. Entries already recorded don\'t change';

  @override
  String get agentBillingLikeHumans => 'Billable like people\'s time';

  @override
  String get agentBillingNever => 'Never billable';

  @override
  String get agentCardLink => 'See its card in Team';

  @override
  String get agentInactive =>
      'Your agent was deactivated or removed by an administrator: your Claude Code sessions no longer record time.';

  @override
  String get agentRestored =>
      'Agent restored: its pilot\'s Claude Code sessions record time again.';

  @override
  String get agents => 'Agents';

  @override
  String get agentsHelp =>
      'Claude agents: their time is recorded by Claude Code, one agent per person who connected a computer (Settings › Integrations).';

  @override
  String get quickEntry => 'Quick entry';

  @override
  String get quickEntryHint =>
      'What you did, in plain words: “1h20 weekly meeting internal”';

  @override
  String get quickEntryTry => 'Try:';

  @override
  String get quickEntryHelp =>
      'Duration (1h20, 45min) or range (9h-10h30), day (yesterday, friday), project or task, #tag, “non facturable”: in any order. Enter to save, Esc to clear.';

  @override
  String get quickDurationMissing => 'duration?';

  @override
  String get quickProjectMissing => 'project?';

  @override
  String get quickInGap => 'in an empty slot';

  @override
  String quickAdded(String description, String day, String range) {
    return 'Added: $description · $day, $range';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceSystem => 'Same as system';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get journalHeroPending => 'Your day is almost ready';

  @override
  String journalHeroPendingText(String total, String proposed, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions to confirm',
      one: '1 suggestion to confirm',
    );
    return '$total rebuilt, $proposed of it proposed: $_temp0.';
  }

  @override
  String get journalHeroGaps => 'Some slots are still empty';

  @override
  String get journalHeroGapsText =>
      'Tap a dashed slot to fill it, or drag across the “You” line.';

  @override
  String get journalHeroDone => 'Day complete';

  @override
  String journalHeroDoneText(String total) {
    return '$total logged, nothing to confirm.';
  }

  @override
  String get journalHeroNothing => 'Nothing to suggest for this day';

  @override
  String journalHeroNothingText(String total) {
    return '$total logged.';
  }

  @override
  String journalConfirmAll(int count) {
    return 'Confirm all · $count';
  }

  @override
  String get journalReviewOne => 'Review one by one';

  @override
  String get journalYou => 'You';

  @override
  String journalToFill(String duration) {
    return '$duration to log';
  }

  @override
  String get journalHint =>
      'Drag on empty space: create · drag an edge or the block: adjust · Enter: confirm · Backspace: dismiss · arrows: shift';

  @override
  String get journalProposed => 'Suggested by Clockifai';

  @override
  String get journalSourceClaude => 'During a Claude session';

  @override
  String get journalSourceHabit => 'Habit';

  @override
  String get journalSourcePlanning => 'Schedule';

  @override
  String get journalLogged => 'Logged';

  @override
  String get journalRunning => 'Running';

  @override
  String get journalNew => 'New entry';

  @override
  String get journalWhy => 'Why this block';

  @override
  String journalReasonClaudeSession(String start, String end) {
    return 'Claude was working on this project from $start to $end';
  }

  @override
  String get journalReasonClaudePilot =>
      'Time spent following its session and reviewing its work';

  @override
  String journalReasonHabitWeekday(int count, int of, String time) {
    return 'Habit: $count times in the last $of weeks, same day, around $time';
  }

  @override
  String journalReasonHabitDaily(int count, int of, String time) {
    return 'Habit: $count of the last $of working days, around $time';
  }

  @override
  String journalReasonPlanned(String duration) {
    return 'Schedule: $duration planned on this project';
  }

  @override
  String journalReasonAlreadyLogged(String duration) {
    return 'Already logged on this project today: $duration';
  }

  @override
  String get journalReasonNew =>
      'Created on the timeline: pick the project, then save.';

  @override
  String get journalPrivacy =>
      'Nothing from your files or messages: only times, your past entries, the schedule and Claude sessions.';

  @override
  String get journalConfirm => 'Confirm';

  @override
  String get journalIgnore => 'Dismiss';

  @override
  String get journalEditEntry => 'Edit…';

  @override
  String journalAdded(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries added',
      one: '1 entry added',
    );
    return '$_temp0 · $duration';
  }

  @override
  String get journalIgnored => 'Suggestion dismissed';

  @override
  String get journalSummary => 'Day summary';

  @override
  String get journalConfirmed => 'Confirmed';

  @override
  String get journalToConfirm => 'To confirm';

  @override
  String journalTarget(String duration) {
    return 'of $duration';
  }

  @override
  String journalTypicalDay(String start, String end) {
    return 'Typical day: $start – $end, from your past weeks';
  }

  @override
  String journalTypicalDefault(String start, String end) {
    return 'Default typical day: $start – $end';
  }

  @override
  String get journalSelectHint =>
      'Pick a block, or drag across the “You” line to create one.';

  @override
  String get journalDescriptionHint => 'What did you do?';

  @override
  String journalDayRing(String day, int percent) {
    return '$day: $percent% logged';
  }

  @override
  String get journalBackToToday => 'Back to today';

  @override
  String get aiUsage => 'AI usage';

  @override
  String get aiUsageHelp =>
      'Tokens used by Claude and cost estimated at Anthropic API prices, in US dollars. With a Claude subscription (Pro, Max), this is not an actual expense.';

  @override
  String aiTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String get aiCostEstimated => 'Estimated AI cost';

  @override
  String aiRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calls',
      one: '1 call',
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
    return 'Input $input · output $output · cache write $written · cache read $read';
  }

  @override
  String get aiUnknownPrice => 'unknown price';

  @override
  String get aiFastMode => 'fast mode';

  @override
  String aiEffort(String level) {
    return '$level effort';
  }

  @override
  String get agentsWorking => 'Claude is working';

  @override
  String get agentsWorkingHelp =>
      'Your agent\'s running Claude Code sessions. After 10 minutes without activity, a session closes at the time of its last action. Tap a session to change its project, create a task for it or change its description.';

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
      'Claude\'s next sessions in this repository will go to this project, without a task, and so will its entries without a project from the past week.';

  @override
  String get amount => 'Amount';

  @override
  String get annualAllowance => 'Annual allowance';

  @override
  String apiTokenCreated(String name) {
    return 'Token created for “$name”. It won\'t be shown again: follow these steps now.';
  }

  @override
  String get apply => 'Apply';

  @override
  String get applyRateApply => 'Apply';

  @override
  String applyRateBody(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unbilled entries kept another rate.',
      one: '1 unbilled entry kept another rate.',
    );
    return '$_temp0 The new rate applies to new entries; apply it to these as well?';
  }

  @override
  String get applyRateKeep => 'Only new entries';

  @override
  String get applyRateTitle => 'Apply the new rate?';

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
      'You also need python3 (on a Mac, the developer tools: xcode-select --install).';

  @override
  String get claudeCodeStepCli =>
      '1. In a terminal, claude --version should print a version number. Otherwise, install the Claude Code command line (the VSCode extension ships its own copy, which the terminal can\'t see), then open a new terminal:';

  @override
  String get claudeCodeStepInstall =>
      '2. In a terminal (the Claude Code panel in VSCode has no /plugin):';

  @override
  String get claudeCodeStepStart =>
      '4. Open a new Claude Code conversation: Claude\'s timer starts at the first prompt. Claude names the task of each subject: allow the Clockifai tool when asked the first time.';

  @override
  String get claudeCodeStepToken =>
      '3. Paste this command into the terminal, without pressing Enter:';

  @override
  String get claudeCodeStepTokenReconnect =>
      '3. The token is only shown when a computer is connected: if this computer lacks it, tap Reconnect on its row in the list below.';

  @override
  String get claudeCodeStepTokenThen =>
      'Tap Copy token, then press Enter in the terminal: the command reads the token from the clipboard. In the other order, copying the command would replace the token.';

  @override
  String get claudeTasks => 'Claude\'s tasks';

  @override
  String get claudeTasksHelp =>
      'Claude names the task of its work, and your sessions\' time goes there, in the repository\'s project. A more precise name renames the task instead of creating another; a task you choose stays.';

  @override
  String get claudeTasksOff => 'No task: project only';

  @override
  String get claudeTasksSession => 'One task per Claude Code session';

  @override
  String get claudeTasksSubject =>
      'One task per subject (same name, same task)';

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
  String deleteSimilarEntries(int count) {
    return 'Delete the $count entries';
  }

  @override
  String get undo => 'Undo';

  @override
  String get presenceTitle => 'Site presence';

  @override
  String get presenceHelp =>
      'This phone notes when you arrive at and leave a site; Today offers them for you to confirm. Your location stays on the phone: only the times are used.';

  @override
  String get presenceOn => 'Site presence is on for this phone.';

  @override
  String get presenceDenied =>
      'Location access denied: allow it in the phone settings.';

  @override
  String get presenceServiceOff =>
      'Location unavailable: turn it on for this device.';

  @override
  String get presenceForget => 'Forget recorded times';

  @override
  String get presenceForgotten => 'Presence times erased from this phone.';

  @override
  String get presenceNotification =>
      'Site presence: arrival and departure noted on this phone';

  @override
  String get presenceRounding => 'Site presence times';

  @override
  String get presenceRoundingHelp =>
      'What the phones of people who turned on site presence suggest.';

  @override
  String get presenceRoundingActual => 'As detected (to the nearest 5 minutes)';

  @override
  String get presenceRoundingPlanning =>
      'Snapped to the usual day, within 30 minutes';

  @override
  String get sitePosition => 'Site location';

  @override
  String get sitePositionHelp =>
      'Latitude and longitude, copied from a map, or \"Here\" on site. Used for site presence.';

  @override
  String get sitePositionInvalid =>
      'Expected: latitude, longitude (48.8566, 2.3522)';

  @override
  String get siteOnMap => 'Show on map';

  @override
  String get siteRadius => 'Radius';

  @override
  String get siteHere => 'Here';

  @override
  String get journalSourcePresence => 'Site';

  @override
  String journalReasonPresence(String from, String to) {
    return 'On site from $from to $to, according to this phone';
  }

  @override
  String journalReasonPresenceSince(String from) {
    return 'On site since $from, according to this phone';
  }

  @override
  String get journalReasonPresenceRounded =>
      'Times snapped to your usual day (company rule)';

  @override
  String pendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting',
      one: '1 change waiting',
    );
    return '$_temp0';
  }

  @override
  String get dayNothingToCopy => 'Nothing to copy from that day.';

  @override
  String get likeYesterday => 'Same as yesterday';

  @override
  String likeDay(String day) {
    return 'Same as $day';
  }

  @override
  String likeDate(String date) {
    return 'Same as $date';
  }

  @override
  String get duplicateToday => 'Duplicate to today';

  @override
  String get morning => 'Morning';

  @override
  String get afternoon => 'Afternoon';

  @override
  String get dictate => 'Dictate';

  @override
  String get dictationStop => 'Stop dictation';

  @override
  String get dictationUnavailable =>
      'Dictation unavailable: microphone denied or no speech recognition on this device.';

  @override
  String get teamAbsent => 'Approved time off';

  @override
  String get teamAbsentHalf => 'Approved time off (half day)';

  @override
  String teamAlreadyLogged(String time) {
    return 'Already logged: $time';
  }

  @override
  String leftAt(String time) {
    return 'Left at $time';
  }

  @override
  String arrivedAt(String time) {
    return 'Arrived at $time';
  }

  @override
  String get arrivedAtPick => 'Arrived at…';

  @override
  String get leftAtPick => 'Left at…';

  @override
  String get otherHours => 'Other hours…';

  @override
  String get commonHours => 'Common hours';

  @override
  String get teamException => 'Exception';

  @override
  String get lateTitle => 'Last week';

  @override
  String lateHelp(String date) {
    return 'Who has not yet submitted their timesheet for the week of $date.';
  }

  @override
  String get lateAllGood => 'Everyone has submitted their week.';

  @override
  String lateLine(String logged, String planned) {
    return '$logged entered out of $planned planned';
  }

  @override
  String lateLineNoPlan(String logged) {
    return '$logged entered';
  }

  @override
  String get lateNotSubmitted => 'Not submitted';

  @override
  String get remind => 'Remind';

  @override
  String get reminded => 'Reminded';

  @override
  String remindedSnack(String name) {
    return 'Reminder sent to $name';
  }

  @override
  String get reminderTitle => 'Timesheet';

  @override
  String reminderBanner(String who, String date) {
    return '$who reminds you to submit your week of $date';
  }

  @override
  String get reminderOpen => 'Open the timesheet';

  @override
  String get reminderOk => 'OK';

  @override
  String plannedVsSubmitted(String planned, String delta) {
    return '$planned planned · difference $delta';
  }

  @override
  String get reportQuestions => 'Questions:';

  @override
  String get qMyWeek => 'My time this week';

  @override
  String get qTeamWeek => 'The team\'s time this week';

  @override
  String get qClientsMonth => 'By client, this month';

  @override
  String get qWhoWhat => 'Who did what this week';

  @override
  String get qReadyToBill => 'Ready to bill';

  @override
  String get qAiCost => 'AI usage at cost';

  @override
  String get qCompare => 'Compare with the previous period';

  @override
  String qDelta(String delta) {
    return '$delta vs previous period';
  }

  @override
  String qBefore(String duration) {
    return 'before: $duration';
  }

  @override
  String get readyToBillTitle => 'To bill';

  @override
  String get readyToBillHelp =>
      'Billable time not yet invoiced, by client, over the last twelve months (workspace rounding applied).';

  @override
  String get readyToBillNone => 'Everything is invoiced.';

  @override
  String readyToBillSince(String day) {
    return 'since $day';
  }

  @override
  String get invoiceNow => 'Invoice';

  @override
  String get assistantTitle => 'Ask Clockifai';

  @override
  String assistantTooltip(String shortcut) {
    return 'Ask Clockifai ($shortcut)';
  }

  @override
  String get assistantIntro =>
      'Ask about your time: totals by project, client, day or person, comparisons, entries to fix. Only totals and project names are sent to Claude, never your descriptions.';

  @override
  String get assistantHint => 'How many hours on the bakery this month?';

  @override
  String get assistantExample1 => 'How many hours this week, by project?';

  @override
  String get assistantExample2 => 'What is billable this month, by client?';

  @override
  String get assistantExample3 => 'My entries without a project last week?';

  @override
  String get assistantThinking => 'Clockifai is looking…';

  @override
  String get assistantRefused => 'I can\'t answer this question.';

  @override
  String get assistantTooLong =>
      'This question needs too many steps: make it more specific.';

  @override
  String get assistantUnavailable => 'The assistant is unavailable right now.';

  @override
  String get assistantRateLimited =>
      'Too many questions: try again in a while.';

  @override
  String get assistantOffline => 'The assistant needs a connection.';

  @override
  String assistantEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'No entry',
    );
    return '$_temp0';
  }

  @override
  String get assistantPreview => 'Preview';

  @override
  String get assistantApply => 'Apply';

  @override
  String get assistantApplied => 'Applied';

  @override
  String get kbAssistant => 'Ask Clockifai';

  @override
  String get recapTitle => 'End of day';

  @override
  String recapLine(String logged, String target, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions to confirm',
      one: '1 suggestion to confirm',
    );
    return '$logged entered out of $target · $_temp0';
  }

  @override
  String recapLineDone(String logged, String target) {
    return '$logged entered out of $target, nothing to confirm';
  }

  @override
  String get recapNothing => 'Nothing to confirm: your day is complete.';

  @override
  String get recapOpenDay => 'Open the timeline';

  @override
  String recapConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Confirm $count entries',
      one: 'Confirm 1 entry',
    );
    return '$_temp0';
  }

  @override
  String get recapLater => 'Later';

  @override
  String get recapReview => 'Review';

  @override
  String get recapSetting => 'End-of-day summary';

  @override
  String get recapSettingHelp =>
      'Every working day, at the chosen time: the time entered and the suggestions to confirm in one go. Set on each device.';

  @override
  String get recapOff => 'Off';

  @override
  String recapAt(String time) {
    return 'At $time';
  }

  @override
  String get recapNotificationBody =>
      'Your day is waiting: check it and confirm the suggestions.';

  @override
  String get weekGrid => 'Grid';

  @override
  String get weekList => 'List';

  @override
  String get weekCopyPrevious => 'Copy previous week';

  @override
  String get weekFillPlanning => 'Fill from the schedule';

  @override
  String get weekNothingToCopy => 'Nothing to copy from the previous week.';

  @override
  String get weekNothingToFill =>
      'Nothing to fill: the schedule is already covered.';

  @override
  String weekFilled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries added from the schedule',
      one: '1 entry added from the schedule',
    );
    return '$_temp0';
  }

  @override
  String weekPlanned(String duration) {
    return 'Planned: $duration';
  }

  @override
  String get weekReviewTitle => 'Before submitting';

  @override
  String get weekReviewAllGood => 'All good: every working day has its time.';

  @override
  String get weekReviewFix => 'Fix';

  @override
  String get weekReviewSubmit => 'Submit';

  @override
  String get weekReviewSubmitAnyway => 'Submit anyway';

  @override
  String issueEmptyDay(String day) {
    return '$day: no time entered';
  }

  @override
  String issueEmptyDayPlanned(String day, String planned) {
    return '$day: no time entered ($planned planned)';
  }

  @override
  String issueBelowPlan(String day, String logged, String planned) {
    return '$day: $logged entered out of $planned planned';
  }

  @override
  String issueNoProject(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries without a project',
      one: '1 entry without a project',
    );
    return '$_temp0';
  }

  @override
  String issueNoDescription(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries without a description',
      one: '1 entry without a description',
    );
    return '$_temp0';
  }

  @override
  String issueRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count timers still running',
      one: '1 timer still running',
    );
    return '$_temp0';
  }

  @override
  String issueOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overlaps between entries',
      one: '1 overlap between two entries',
    );
    return '$_temp0';
  }

  @override
  String get journalSourceCalendar => 'Calendar';

  @override
  String get journalSourceCommits => 'Commits';

  @override
  String journalReasonCalendar(String start, String end) {
    return 'In your calendar, from $start to $end';
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
    return '$_temp0 in $repository, from $start to $end';
  }

  @override
  String get journalTraces => 'Traces';

  @override
  String get calendarTitle => 'Calendar';

  @override
  String get calendarHelp =>
      'Paste the private iCal address of your calendar: Google Calendar, calendar settings › “Secret address in iCal format”; Outlook, Settings › Calendar › Shared calendars › Publish; Apple, right-click the calendar › Share. Clockifai only reads the time and title of events, to suggest your meetings in Today.';

  @override
  String get calendarUrl => 'Private iCal address';

  @override
  String get calendarNone => 'No calendar linked';

  @override
  String calendarLinked(String host) {
    return 'Linked: $host';
  }

  @override
  String get calendarRemove => 'Remove the calendar';

  @override
  String get calendarOffline => 'Can only be set while online.';

  @override
  String get calendarErrorHttps =>
      'The address must start with https:// (or webcal://).';

  @override
  String get calendarErrorHost =>
      'This address is not reachable from the Internet.';

  @override
  String get calendarErrorUnreachable =>
      'Calendar unreachable: check the address.';

  @override
  String get calendarErrorFormat =>
      'This address does not lead to an iCal calendar.';

  @override
  String get calendarErrorTooLarge => 'Calendar too large.';

  @override
  String journalTypicalProfile(String start, String end) {
    return 'Typical day: $start – $end, set in your settings';
  }

  @override
  String get myDay => 'My typical day';

  @override
  String get myDayHelp =>
      'Usual arrival, break and departure: the Today page uses them for empty slots. When not set, Clockifai infers them from your past weeks.';

  @override
  String get myDayAuto => 'Automatic, from your past weeks';

  @override
  String get myDayReset => 'Back to automatic';

  @override
  String get myDayInvalid =>
      'Times must follow each other: arrival, break, departure.';

  @override
  String get dayStart => 'Arrival';

  @override
  String get lunchStart => 'Break starts';

  @override
  String get lunchEnd => 'Break ends';

  @override
  String get dayEnd => 'Departure';

  @override
  String get openDay => 'Open the day';

  @override
  String get commandPalette => 'Commands';

  @override
  String commandPaletteTooltip(String shortcut) {
    return 'Commands ($shortcut)';
  }

  @override
  String get keyEscape => 'Esc';

  @override
  String get commandPaletteHint => 'An action, a page, a project…';

  @override
  String get commandNoResult => 'No command';

  @override
  String get cmdGoTo => 'Go to';

  @override
  String get cmdStartTimer => 'Start the timer';

  @override
  String get cmdStopTimer => 'Stop the timer';

  @override
  String get cmdStartOnProject => 'Start the timer on this project';

  @override
  String get cmdResume => 'Resume';

  @override
  String get cmdThemeDark => 'Appearance: dark';

  @override
  String get cmdThemeLight => 'Appearance: light';

  @override
  String get cmdThemeSystem => 'Appearance: system';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutsEverywhere => 'Everywhere';

  @override
  String get shortcutsHelp =>
      'A single key works when you are not typing in a field.';

  @override
  String get kbPalette => 'Commands: pages, timer, projects';

  @override
  String get kbNewEntry => 'New entry';

  @override
  String get kbTimer => 'Start or stop the timer';

  @override
  String get kbUndo => 'Undo the last action';

  @override
  String get kbHelp => 'This help';

  @override
  String get kbMove => 'Next, previous entry';

  @override
  String get kbSelect => 'Select';

  @override
  String get kbEdit => 'Edit';

  @override
  String get kbDuplicate => 'Duplicate';

  @override
  String get kbDelete => 'Delete (the selection, or the entry)';

  @override
  String get kbClear => 'Clear the selection';

  @override
  String get kbTodayConfirm => 'Confirm the chosen block';

  @override
  String get kbTodayIgnore => 'Dismiss the suggestion';

  @override
  String get kbTodayShift => 'Shift by 5 minutes (Shift: lengthen or shorten)';

  @override
  String selectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get selectEntry => 'Select';

  @override
  String get duplicateTo => 'Duplicate to…';

  @override
  String entriesUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries updated',
      one: '1 entry updated',
    );
    return '$_temp0';
  }

  @override
  String entriesDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries duplicated',
      one: '1 entry duplicated',
    );
    return '$_temp0';
  }

  @override
  String get entryDeleted => 'Entry deleted';

  @override
  String entriesDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries deleted',
      one: '1 entry deleted',
    );
    return '$_temp0';
  }

  @override
  String get entryUpdated => 'Entry updated';

  @override
  String get timerDiscarded =>
      'Timer discarded: the running time was not saved';

  @override
  String clientDeleted(String name) {
    return 'Client “$name” deleted; its projects remain, without a client';
  }

  @override
  String projectDeleted(String name) {
    return 'Project “$name” deleted; its entries remain';
  }

  @override
  String tagDeleted(String name) {
    return 'Tag “$name” deleted';
  }

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
  String get hideInstallCommands => 'Hide the setup commands';

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
  String get humans => 'Humans';

  @override
  String get humansAndAgents => 'Humans and agents';

  @override
  String get installCommandsTitle => 'Setup commands for a computer';

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
  String get inviteMember => 'Invite a member';

  @override
  String get invoice => 'Invoice';

  @override
  String get invoiceByTask => 'Detail by task';

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
      'One line per project, or per task when detailed, is created from the client\'s billable, not yet invoiced time in the period. An entry recorded before its project had a rate takes the current rate.';

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
  String get reconnect => 'Reconnect';

  @override
  String get reconnectComputer => 'Reconnect this computer?';

  @override
  String reconnectComputerMessage(String name) {
    return 'A new token replaces the one of “$name”, which stops working. Then follow the steps shown, on that computer.';
  }

  @override
  String get reject => 'Reject';

  @override
  String get remaining => 'left';

  @override
  String get remove => 'Remove';

  @override
  String get removeAgent => 'Remove this agent?';

  @override
  String removeAgentMessage(String pilot) {
    return '$pilot\'s Claude Code sessions will no longer record time, even from a newly connected computer. Past entries are kept. For a pause, choose Deactivate instead. An admin can restore it from Team, under Removed agents.';
  }

  @override
  String removedAgentOf(String name, String date) {
    return '$name\'s agent · removed on $date';
  }

  @override
  String get removedAgents => 'Removed agents';

  @override
  String get removedAgentsHelp =>
      'Their time is no longer recorded, even if their pilot connects a new computer.';

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
  String get showInstallCommands => 'Show the setup commands';

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
      'Everyone present is ticked (except approved time off or a day already logged): one entry is created for each person, even offline. Tap someone\'s hours to note an exception (\"Left at 15:00\").';

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

  @override
  String get navWeek => 'Week';

  @override
  String get navPeople => 'People';

  @override
  String get navProjectsClients => 'Projects and clients';

  @override
  String get searchOrAct => 'Search or act';

  @override
  String get syncedWorksOffline => 'Synced · works offline';

  @override
  String get addTime => 'Add time';

  @override
  String get add => 'Add';

  @override
  String get inviteByEmail => 'Send the invitation by email';

  @override
  String get inviteNoMail =>
      'No mail server on this installation: you will copy the link.';

  @override
  String get inviteReady => 'Invitation ready';

  @override
  String inviteEmailedTo(String email) {
    return 'An invitation email was sent to $email. You can also send them this link:';
  }

  @override
  String inviteShareWith(String email) {
    return 'Send this link to $email:';
  }

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get journalToComplete => 'To complete';

  @override
  String get journalFill => 'Fill';

  @override
  String get journalNothingToday => 'Nothing logged today';

  @override
  String get journalNothingThatDay => 'Nothing logged that day';

  @override
  String likeDayQuestion(String label) {
    return '$label?';
  }

  @override
  String resumeDay(String duration) {
    return 'Repeat that day · $duration';
  }

  @override
  String get journalFromPlanning => 'From the schedule';

  @override
  String get journalSomethingElse => 'Something else';

  @override
  String get journalYourDay => 'Your day';
}
