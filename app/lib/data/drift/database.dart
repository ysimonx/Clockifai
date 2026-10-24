import 'package:drift/drift.dart';
import 'package:powersync/powersync.dart' show uuid;

part 'database.g.dart';

/// Base Drift posée sur la base SQLite gérée par PowerSync (via drift_sqlite_async).
///
/// Les tables ci-dessous ne sont PAS créées par Drift : PowerSync crée des vues
/// à partir de lib/data/powersync/schema.dart. Drift sert d'ORM typé et de source
/// de flux réactifs (`watch`). Règles :
///   * pas de `withDefault` (défaut SQL) → utiliser `clientDefault` ;
///   * pas d'upsert / RETURNING (non supportés sur les vues) ;
///   * dates écrites en UTC ; comparaisons via [epoch] (formats ISO hétérogènes).

String newId() => uuid.v4();
DateTime nowUtc() => DateTime.now().toUtc();

/// `unixepoch(col)` : compare des dates indépendamment de leur format texte
/// ("2026-01-01 10:00:00Z" côté serveur, "2026-01-01T10:00:00.000Z" côté client).
Expression<int> epoch(Expression<DateTime> column) => FunctionCallExpression<int>('unixepoch', [column]);
Variable<int> epochOf(DateTime value) => Variable<int>(value.millisecondsSinceEpoch ~/ 1000);

@DataClassName('Profile')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get email => text().nullable()();
  TextColumn get displayName => text().clientDefault(() => '')();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get timezone => text().clientDefault(() => 'Europe/Paris')();
  TextColumn get locale => text().clientDefault(() => 'fr')();
  TextColumn get defaultWorkspaceId => text().nullable()();
  /// Tâches de Claude (plan 10, D18) : `subject`, `session` ou `off` ; nul tant que la colonne n'est pas synchronisée.
  TextColumn get claudeTasks => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Workspace')
class Workspaces extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text()();
  TextColumn get currency => text().clientDefault(() => 'EUR')();
  IntColumn get weekStart => integer().clientDefault(() => 1)();
  TextColumn get timeFormat => text().clientDefault(() => '24h')();
  IntColumn get roundingMinutes => integer().clientDefault(() => 0)();
  BoolColumn get requireProject => boolean().clientDefault(() => false)();
  BoolColumn get requireDescription => boolean().clientDefault(() => false)();
  TextColumn get lockEntriesBefore => text().nullable()();
  IntColumn get autoStopAfterHours => integer().clientDefault(() => 0)();
  TextColumn get companyName => text().nullable()();
  TextColumn get companyDetails => text().nullable()();
  TextColumn get invoicePrefix => text().clientDefault(() => 'F')();
  RealColumn get defaultTaxPercent => real().clientDefault(() => 20)();
  IntColumn get invoiceDueDays => integer().clientDefault(() => 30)();
  /// 'admins' | 'admins_and_team_managers' (nullable côté client : rempli par la sync).
  TextColumn get timeForOthers => text().nullable()();
  /// 'everyone' | 'managers' : qui crée des tâches depuis le sélecteur (nullable côté client : rempli par la sync).
  TextColumn get taskCreation => text().nullable()();
  /// Chronomètres simultanés par membre : 1 = un seul, 0 = illimité (nullable côté client : rempli par la sync).
  IntColumn get maxRunningTimers => integer().nullable()();
  /// Temps des agents Claude : 'like_humans' | 'never' (plan 10, D16 ; nullable côté client : rempli par la sync).
  TextColumn get agentBilling => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkspaceMember')
class WorkspaceMembers extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().clientDefault(() => 'member')();
  TextColumn get status => text().clientDefault(() => 'active')();
  TextColumn get displayName => text().clientDefault(() => '')();
  TextColumn get email => text().nullable()();
  IntColumn get hourlyRateCents => integer().nullable()();
  IntColumn get costRateCents => integer().nullable()();
  RealColumn get capacityHoursPerDay => real().clientDefault(() => 7)();
  /// 'human' | 'agent' (agent Claude d'un pilote, plan 10 ; posé par le serveur, nullable côté client).
  TextColumn get kind => text().nullable()();
  /// Pilote d'un agent ; null pour un humain.
  TextColumn get agentOwnerId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ClientItem')
class Clients extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get note => text().nullable()();
  TextColumn get currencyOverride => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().nullable()();
  BoolColumn get archived => boolean().clientDefault(() => false)();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Project')
class Projects extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get clientId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get color => text().clientDefault(() => '#3B82F6')();
  BoolColumn get billableDefault => boolean().clientDefault(() => true)();
  IntColumn get hourlyRateCents => integer().nullable()();
  IntColumn get budgetHours => integer().nullable()();
  IntColumn get budgetAmountCents => integer().nullable()();
  BoolColumn get isPublic => boolean().clientDefault(() => true)();
  BoolColumn get archived => boolean().clientDefault(() => false)();
  TextColumn get note => text().nullable()();
  /// Temps des agents sur ce projet : null = comme le workspace, sinon facturable ou non (plan 10, D16).
  BoolColumn get agentBillable => boolean().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Task')
class Tasks extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  IntColumn get estimateSeconds => integer().nullable()();
  TextColumn get status => text().clientDefault(() => 'active')();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Tag')
class Tags extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().clientDefault(() => '#6B7280')();
  BoolColumn get archived => boolean().clientDefault(() => false)();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimeEntry')
class TimeEntries extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get taskId => text().nullable()();
  TextColumn get description => text().clientDefault(() => '')();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  BoolColumn get billable => boolean().clientDefault(() => true)();
  IntColumn get hourlyRateCents => integer().nullable()();
  BoolColumn get locked => boolean().clientDefault(() => false)();
  /// Auteur de la saisie (posé par le serveur ; null = la personne elle-même).
  TextColumn get createdBy => text().nullable()();
  TextColumn get updatedBy => text().nullable()();
  /// Origine : null ou 'app' (saisie), 'kiosk', 'agent' (agent Claude), 'activity' (suggestion acceptée) ;
  /// posée à la création, jamais modifiée (garde serveur).
  TextColumn get source => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimeEntryTag')
class TimeEntryTags extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get timeEntryId => text()();
  TextColumn get tagId => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Modules : approbations, absences, planning, facturation.
// Les dates sans heure (period_start, start_date…) restent du texte « yyyy-MM-dd ».
// ---------------------------------------------------------------------------

@DataClassName('TimesheetSubmission')
class TimesheetSubmissions extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get periodStart => text()();
  TextColumn get periodEnd => text()();
  TextColumn get status => text().clientDefault(() => 'submitted')();
  IntColumn get totalSeconds => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get decidedBy => text().nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  TextColumn get decisionNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimeOffPolicy')
class TimeOffPolicies extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().clientDefault(() => '#10B981')();
  TextColumn get unit => text().clientDefault(() => 'days')();
  RealColumn get annualAllowance => real().nullable()();
  BoolColumn get paid => boolean().clientDefault(() => true)();
  BoolColumn get requiresApproval => boolean().clientDefault(() => true)();
  /// 'managers' | 'managers_and_team_managers' (nullable côté client : rempli par la sync).
  TextColumn get approvers => text().nullable()();
  BoolColumn get archived => boolean().clientDefault(() => false)();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimeOffAllowance')
class TimeOffAllowances extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get policyId => text()();
  IntColumn get year => integer()();
  RealColumn get allowance => real()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TimeOffRequest')
class TimeOffRequests extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get policyId => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  RealColumn get amount => real()();
  BoolColumn get halfDay => boolean().clientDefault(() => false)();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().clientDefault(() => 'pending')();
  TextColumn get decidedBy => text().nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  TextColumn get decisionNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Holiday')
class Holidays extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get date => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ScheduleAssignment')
class ScheduleAssignments extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  RealColumn get hoursPerDay => real().clientDefault(() => 7)();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Invoice')
class Invoices extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get clientId => text().nullable()();
  TextColumn get number => text().nullable()();
  TextColumn get status => text().clientDefault(() => 'draft')();
  TextColumn get issueDate => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get currency => text().clientDefault(() => 'EUR')();
  RealColumn get taxPercent => real().clientDefault(() => 0)();
  RealColumn get discountPercent => real().clientDefault(() => 0)();
  TextColumn get note => text().nullable()();
  TextColumn get periodStart => text().nullable()();
  TextColumn get periodEnd => text().nullable()();
  IntColumn get subtotalCents => integer().clientDefault(() => 0)();
  IntColumn get discountCents => integer().clientDefault(() => 0)();
  IntColumn get taxCents => integer().clientDefault(() => 0)();
  IntColumn get totalCents => integer().clientDefault(() => 0)();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('InvoiceItem')
class InvoiceItems extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get invoiceId => text()();
  IntColumn get position => integer().clientDefault(() => 0)();
  TextColumn get description => text().clientDefault(() => '')();
  RealColumn get quantity => real().clientDefault(() => 1)();
  IntColumn get unitPriceCents => integer().clientDefault(() => 0)();
  IntColumn get amountCents => integer().clientDefault(() => 0)();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Chefs d'équipe : groupes d'utilisateurs, affectations, périmètre (team_scope, écrit par le serveur).
// ---------------------------------------------------------------------------

@DataClassName('UserGroup')
class UserGroups extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('UserGroupMember')
class UserGroupMembers extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get groupId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Un chef d'équipe encadre un utilisateur ([userId]) ou un groupe ([groupId]).
@DataClassName('TeamManagerAssignment')
class TeamManagerAssignments extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get managerId => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get groupId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Périmètre effectif (chef → collaborateur), en lecture seule côté client.
@DataClassName('TeamScopeRow')
class TeamScope extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get managerId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('InvoiceEntry')
class InvoiceEntries extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get invoiceId => text()();
  TextColumn get timeEntryId => text()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Profiles,
  Workspaces,
  WorkspaceMembers,
  Clients,
  Projects,
  Tasks,
  Tags,
  TimeEntries,
  TimeEntryTags,
  TimesheetSubmissions,
  TimeOffPolicies,
  TimeOffAllowances,
  TimeOffRequests,
  Holidays,
  ScheduleAssignments,
  Invoices,
  InvoiceItems,
  InvoiceEntries,
  UserGroups,
  UserGroupMembers,
  TeamManagerAssignments,
  TeamScope,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // PowerSync crée et fait évoluer le schéma (vues) : Drift ne crée rien.
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );
}
