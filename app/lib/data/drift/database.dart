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
  /// Journée type (plan 13, lot 2) : « 08:30 », à l'horloge ; nulles = déduite des semaines passées.
  TextColumn get dayStart => text().nullable()();
  TextColumn get lunchStart => text().nullable()();
  TextColumn get lunchEnd => text().nullable()();
  TextColumn get dayEnd => text().nullable()();
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
  /// Présence chantier : null ou 'actual' (heures détectées), 'planning' (calées sur la journée type ; plan 13, lot 13).
  TextColumn get presenceRounding => text().nullable()();
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
  /// Facturé par ticket : Claude Code demande le ticket du client à chaque session (plans/19-tickets-clients.md).
  BoolColumn get billedByTicket => boolean().nullable()();
  /// Chantier : position et rayon en mètres, pour la présence détectée par le téléphone (plan 13, lot 13).
  RealColumn get siteLat => real().nullable()();
  RealColumn get siteLng => real().nullable()();
  IntColumn get siteRadius => integer().nullable()();
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
  /// Tâche parente d'une sous-tâche (plans/16-sous-taches.md) : un seul niveau.
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get estimateSeconds => integer().nullable()();
  TextColumn get status => text().clientDefault(() => 'active')();
  /// Ticket du client (plans/19-tickets-clients.md) : son URL et sa clé (« ENG-123 »), qui retrouve la tâche.
  TextColumn get ticketUrl => text().nullable()();
  TextColumn get ticketKey => text().nullable()();
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

/// Usage IA d'une entrée d'agent Claude, par modèle, effort et vitesse (plan 10, D17). Écrit par le serveur :
/// tokens lus dans la transcription sur le poste, coût estimé au tarif de l'API en millionièmes de dollar.
@DataClassName('AgentUsageRow')
class AgentUsage extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get timeEntryId => text()();
  TextColumn get userId => text()();
  TextColumn get model => text()();
  TextColumn get effort => text().nullable()();
  TextColumn get speed => text().nullable()();
  IntColumn get requests => integer().nullable()();
  IntColumn get inputTokens => integer().nullable()();
  IntColumn get outputTokens => integer().nullable()();
  IntColumn get cacheWrite5mTokens => integer().named('cache_write_5m_tokens').nullable()();
  IntColumn get cacheWrite1hTokens => integer().named('cache_write_1h_tokens').nullable()();
  IntColumn get cacheReadTokens => integer().nullable()();
  /// Null : modèle sans tarif connu.
  IntColumn get costMicros => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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

/// Relance d'un membre qui n'a pas soumis sa semaine (plan 13, lot 8) ; [userId] : la personne relancée.
@DataClassName('Reminder')
class Reminders extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get workspaceId => text()();
  TextColumn get userId => text()();
  TextColumn get kind => text().clientDefault(() => 'timesheet')();
  /// Lundi de la semaine visée, `yyyy-MM-dd`.
  TextColumn get periodStart => text()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get seenAt => dateTime().nullable()();
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
  AgentUsage,
  TimesheetSubmissions,
  Reminders,
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

  /// « Annuler » (plans/13-ux-moderne.md) : remet [row], lue avant une suppression logique ou une modification, telle
  /// qu'elle était (`toCompanion(false)`, nulls compris). Une ligne supprimée a pu quitter la base locale entre-temps,
  /// les flux ne gardant que les lignes non supprimées : elle est alors réinsérée, encore marquée supprimée, puis
  /// rétablie par une mise à jour. Une insertion PowerSync n'envoie pas les colonnes nulles ; la mise à jour
  /// envoie `deleted_at: null`, que le serveur applique. À appeler dans une transaction de l'appelant (pas de
  /// transaction imbriquée sur sqlite_async).
  Future<void> restoreRow<T extends Table, D>(TableInfo<T, D> table, UpdateCompanion<D> row) async {
    final values = row.toColumns(false);
    final idColumn = table.columnsByName['id']! as GeneratedColumn<String>;
    Expression<bool> byId(T _) => idColumn.equalsExp(values['id']! as Expression<String>);
    final here = await (select(table)..where(byId)).getSingleOrNull();
    if (here == null) {
      await into(table).insert(RawValuesInsertable<D>({...values, 'deleted_at': Variable<DateTime>(nowUtc())}));
    }
    await (update(table)..where(byId)).write(row);
  }
}
