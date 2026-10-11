import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../drift/database.dart';

final _day = DateFormat('yyyy-MM-dd');
String dayKey(DateTime d) => _day.format(d);
DateTime parseDay(String s) => DateTime.parse(s);

/// Approbations, absences, planning et facturation (base locale, règles vérifiées par le serveur).
class ModulesRepository {
  ModulesRepository(this.db);
  final AppDatabase db;

  // ======================================================== approbations
  Stream<List<TimesheetSubmission>> watchSubmissions(String workspaceId, {String? userId, String? status}) {
    final q = db.select(db.timesheetSubmissions)
      ..where((t) {
        Expression<bool> e = t.workspaceId.equals(workspaceId) & t.deletedAt.isNull();
        if (userId != null) e = e & t.userId.equals(userId);
        if (status != null) e = e & t.status.equals(status);
        return e;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.periodStart)]);
    return q.watch();
  }

  /// Soumet (ou re-soumet) une période pour approbation.
  Future<void> submitPeriod({
    required String workspaceId,
    required String userId,
    required DateTime start,
    required DateTime end,
    required int totalSeconds,
    String? note,
  }) async {
    final existing = await (db.select(db.timesheetSubmissions)
          ..where((t) => t.workspaceId.equals(workspaceId) & t.userId.equals(userId) & t.periodStart.equals(dayKey(start))))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.timesheetSubmissions).insert(TimesheetSubmissionsCompanion.insert(
            workspaceId: workspaceId,
            userId: userId,
            periodStart: dayKey(start),
            periodEnd: dayKey(end),
            totalSeconds: Value(totalSeconds),
            note: Value(note),
          ));
    } else {
      await (db.update(db.timesheetSubmissions)..where((t) => t.id.equals(existing.id))).write(TimesheetSubmissionsCompanion(
        status: const Value('submitted'),
        totalSeconds: Value(totalSeconds),
        note: Value(note),
        deletedAt: const Value(null),
      ));
    }
  }

  /// Vrai si la journée [dayLocal] de [userId] appartient à une période déjà approuvée
  /// (le serveur refuserait toute saisie : on prévient avant, y compris hors ligne).
  Future<bool> isDayApproved(String workspaceId, String userId, DateTime dayLocal) async {
    final key = dayKey(dayLocal);
    final rows = await (db.select(db.timesheetSubmissions)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) &
              t.userId.equals(userId) &
              t.status.equals('approved') &
              t.deletedAt.isNull() &
              t.periodStart.isSmallerOrEqualValue(key) &
              t.periodEnd.isBiggerOrEqualValue(key)))
        .get();
    return rows.isNotEmpty;
  }

  Future<void> withdrawSubmission(String id) => (db.update(db.timesheetSubmissions)..where((t) => t.id.equals(id)))
      .write(const TimesheetSubmissionsCompanion(status: Value('withdrawn')));

  Future<void> decideSubmission(String id, {required bool approve, String? note}) =>
      (db.update(db.timesheetSubmissions)..where((t) => t.id.equals(id))).write(TimesheetSubmissionsCompanion(
        status: Value(approve ? 'approved' : 'rejected'),
        decisionNote: Value(note),
      ));

  // ======================================================== absences
  Stream<List<TimeOffPolicy>> watchPolicies(String workspaceId) => (db.select(db.timeOffPolicies)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  Stream<List<TimeOffRequest>> watchRequests(String workspaceId, {String? userId}) {
    final q = db.select(db.timeOffRequests)
      ..where((t) {
        Expression<bool> e = t.workspaceId.equals(workspaceId) & t.deletedAt.isNull();
        if (userId != null) e = e & t.userId.equals(userId);
        return e;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.startDate)]);
    return q.watch();
  }

  Stream<List<TimeOffAllowance>> watchAllowances(String workspaceId, {String? userId}) {
    final q = db.select(db.timeOffAllowances)
      ..where((t) {
        Expression<bool> e = t.workspaceId.equals(workspaceId) & t.deletedAt.isNull();
        if (userId != null) e = e & t.userId.equals(userId);
        return e;
      });
    return q.watch();
  }

  Stream<List<Holiday>> watchHolidays(String workspaceId) => (db.select(db.holidays)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .watch();

  Future<void> savePolicy(String workspaceId, TimeOffPoliciesCompanion data, {String? id}) async {
    if (id == null) {
      await db.into(db.timeOffPolicies).insert(data.copyWith(workspaceId: Value(workspaceId)));
    } else {
      await (db.update(db.timeOffPolicies)..where((t) => t.id.equals(id))).write(data);
    }
  }

  Future<void> deletePolicy(String id) =>
      (db.update(db.timeOffPolicies)..where((t) => t.id.equals(id))).write(TimeOffPoliciesCompanion(deletedAt: Value(nowUtc())));

  Future<void> addHoliday(String workspaceId, String name, DateTime date) =>
      db.into(db.holidays).insert(HolidaysCompanion.insert(workspaceId: workspaceId, name: name.trim(), date: dayKey(date)));

  Future<void> deleteHoliday(String id) =>
      (db.update(db.holidays)..where((t) => t.id.equals(id))).write(HolidaysCompanion(deletedAt: Value(nowUtc())));

  Future<void> setAllowance({required String workspaceId, required String userId, required String policyId, required int year, required double allowance}) async {
    final existing = await (db.select(db.timeOffAllowances)
          ..where((t) => t.workspaceId.equals(workspaceId) & t.userId.equals(userId) & t.policyId.equals(policyId) & t.year.equals(year)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.timeOffAllowances).insert(TimeOffAllowancesCompanion.insert(
            workspaceId: workspaceId,
            userId: userId,
            policyId: policyId,
            year: year,
            allowance: allowance,
          ));
    } else {
      await (db.update(db.timeOffAllowances)..where((t) => t.id.equals(existing.id)))
          .write(TimeOffAllowancesCompanion(allowance: Value(allowance), deletedAt: const Value(null)));
    }
  }

  Future<void> requestTimeOff({
    required String workspaceId,
    required String userId,
    required String policyId,
    required DateTime start,
    required DateTime end,
    required double amount,
    bool halfDay = false,
    String? note,
  }) =>
      db.into(db.timeOffRequests).insert(TimeOffRequestsCompanion.insert(
            workspaceId: workspaceId,
            userId: userId,
            policyId: policyId,
            startDate: dayKey(start),
            endDate: dayKey(end),
            amount: amount,
            halfDay: Value(halfDay),
            note: Value(note),
          ));

  Future<void> cancelRequest(String id) => (db.update(db.timeOffRequests)..where((t) => t.id.equals(id)))
      .write(const TimeOffRequestsCompanion(status: Value('cancelled')));

  Future<void> decideRequest(String id, {required bool approve, String? note}) =>
      (db.update(db.timeOffRequests)..where((t) => t.id.equals(id))).write(TimeOffRequestsCompanion(
        status: Value(approve ? 'approved' : 'rejected'),
        decisionNote: Value(note),
      ));

  // ======================================================== planning
  /// Affectations qui chevauchent [from, to] (dates incluses).
  Stream<List<ScheduleAssignment>> watchAssignments(String workspaceId, {String? userId, required DateTime from, required DateTime to}) {
    final f = dayKey(from), t = dayKey(to);
    final q = db.select(db.scheduleAssignments)
      ..where((a) {
        Expression<bool> e = a.workspaceId.equals(workspaceId) &
            a.deletedAt.isNull() &
            a.startDate.isSmallerOrEqualValue(t) &
            a.endDate.isBiggerOrEqualValue(f);
        if (userId != null) e = e & a.userId.equals(userId);
        return e;
      })
      ..orderBy([(a) => OrderingTerm.asc(a.startDate)]);
    return q.watch();
  }

  Future<void> saveAssignment(String workspaceId, ScheduleAssignmentsCompanion data, {String? id}) async {
    if (id == null) {
      await db.into(db.scheduleAssignments).insert(data.copyWith(workspaceId: Value(workspaceId)));
    } else {
      await (db.update(db.scheduleAssignments)..where((t) => t.id.equals(id))).write(data);
    }
  }

  Future<void> deleteAssignment(String id) => (db.update(db.scheduleAssignments)..where((t) => t.id.equals(id)))
      .write(ScheduleAssignmentsCompanion(deletedAt: Value(nowUtc())));

  // ======================================================== facturation
  Stream<List<Invoice>> watchInvoices(String workspaceId) => (db.select(db.invoices)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Stream<List<InvoiceItem>> watchItems(String invoiceId) => (db.select(db.invoiceItems)
        ..where((t) => t.invoiceId.equals(invoiceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .watch();

  /// Entrées déjà rattachées à une facture non annulée.
  Future<Set<String>> invoicedEntryIds(String workspaceId) async {
    final rows = await db.customSelect(
      'SELECT ie.time_entry_id FROM invoice_entries ie JOIN invoices i ON i.id = ie.invoice_id '
      "WHERE ie.workspace_id = ?1 AND i.status <> 'void' AND i.deleted_at IS NULL",
      variables: [Variable<String>(workspaceId)],
      readsFrom: {db.invoiceEntries, db.invoices},
    ).get();
    return rows.map((r) => r.read<String>('time_entry_id')).toSet();
  }

  /// Crée une facture brouillon depuis le temps facturable d'un client sur une période :
  /// une ligne par (projet, taux), quantités en heures. Les entrées sont marquées facturées.
  /// Le numéro définitif est attribué par le serveur à la synchronisation.
  Future<String?> createInvoiceFromTime({
    required String workspaceId,
    required String userId,
    required String clientId,
    required DateTime from,
    required DateTime to,
    required String currency,
    required double taxPercent,
    required Map<String, String> projectNames,
  }) async {
    final already = await invoicedEntryIds(workspaceId);
    final projectIds = (await (db.select(db.projects)..where((p) => p.clientId.equals(clientId) & p.deletedAt.isNull())).get())
        .map((p) => p.id)
        .toList();
    if (projectIds.isEmpty) return null;
    final entries = await (db.select(db.timeEntries)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) &
              t.deletedAt.isNull() &
              t.endAt.isNotNull() &
              t.billable.equals(true) &
              t.projectId.isIn(projectIds) &
              epoch(t.startAt).isBiggerOrEqual(epochOf(from)) &
              epoch(t.startAt).isSmallerThan(epochOf(to))))
        .get();
    final toBill = entries.where((e) => !already.contains(e.id)).toList();
    if (toBill.isEmpty) return null;

    final groups = <(String?, int), List<TimeEntry>>{};
    for (final e in toBill) {
      groups.putIfAbsent((e.projectId, e.hourlyRateCents ?? 0), () => []).add(e);
    }
    final invoiceId = newId();
    await db.transaction(() async {
      await db.into(db.invoices).insert(InvoicesCompanion.insert(
            id: Value(invoiceId),
            workspaceId: workspaceId,
            clientId: Value(clientId),
            currency: Value(currency),
            taxPercent: Value(taxPercent),
            issueDate: Value(dayKey(DateTime.now())),
            periodStart: Value(dayKey(from)),
            periodEnd: Value(dayKey(to.subtract(const Duration(days: 1)))),
            createdBy: Value(userId),
          ));
      var position = 0;
      final keys = groups.keys.toList()..sort((a, b) => (projectNames[a.$1] ?? '').compareTo(projectNames[b.$1] ?? ''));
      for (final key in keys) {
        final list = groups[key]!;
        final seconds = list.fold<int>(0, (s, e) => s + e.endAt!.difference(e.startAt).inSeconds);
        final hours = (seconds / 36).round() / 100; // 2 décimales
        await db.into(db.invoiceItems).insert(InvoiceItemsCompanion.insert(
              workspaceId: workspaceId,
              invoiceId: invoiceId,
              position: Value(position++),
              description: Value(projectNames[key.$1] ?? ''),
              quantity: Value(hours),
              unitPriceCents: Value(key.$2),
              amountCents: Value((hours * key.$2).round()),
              projectId: Value(key.$1),
            ));
      }
      for (final e in toBill) {
        await db.into(db.invoiceEntries).insert(InvoiceEntriesCompanion.insert(
              workspaceId: workspaceId,
              invoiceId: invoiceId,
              timeEntryId: e.id,
            ));
      }
    });
    return invoiceId;
  }

  Future<void> updateInvoice(String id, InvoicesCompanion data) =>
      (db.update(db.invoices)..where((t) => t.id.equals(id))).write(data);

  /// Suppression : libère les entrées facturées.
  Future<void> deleteInvoice(String id) async {
    await db.transaction(() async {
      await (db.delete(db.invoiceEntries)..where((t) => t.invoiceId.equals(id))).go();
      await (db.update(db.invoices)..where((t) => t.id.equals(id))).write(InvoicesCompanion(deletedAt: Value(nowUtc())));
    });
  }

  Future<void> saveItem(String workspaceId, String invoiceId, InvoiceItemsCompanion data, {String? id}) async {
    final q = data.quantity.present ? data.quantity.value : null;
    final p = data.unitPriceCents.present ? data.unitPriceCents.value : null;
    var d = data;
    if (q != null && p != null) d = d.copyWith(amountCents: Value((q * p).round()));
    if (id == null) {
      await db.into(db.invoiceItems).insert(d.copyWith(workspaceId: Value(workspaceId), invoiceId: Value(invoiceId)));
    } else {
      await (db.update(db.invoiceItems)..where((t) => t.id.equals(id))).write(d);
    }
  }

  Future<void> deleteItem(String id) =>
      (db.update(db.invoiceItems)..where((t) => t.id.equals(id))).write(InvoiceItemsCompanion(deletedAt: Value(nowUtc())));
}
