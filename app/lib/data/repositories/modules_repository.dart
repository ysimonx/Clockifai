import 'package:drift/drift.dart';

import '../../core/format.dart' show addDays, dayKey;
import '../drift/database.dart';

export '../../core/format.dart' show dayKey, parseDay;

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

  // ------------------------------------------------------------------ relances (plan 13, lot 8)

  /// Relances du workspace ; [userId] : celles d'une personne ; [unseen] : pas encore vues.
  Stream<List<Reminder>> watchReminders(String workspaceId, {String? userId, bool unseen = false}) {
    final q = db.select(db.reminders)
      ..where((t) {
        Expression<bool> e = t.workspaceId.equals(workspaceId) & t.deletedAt.isNull();
        if (userId != null) e = e & t.userId.equals(userId);
        if (unseen) e = e & t.seenAt.isNull();
        return e;
      })
      ..orderBy([(t) => OrderingTerm.desc(epoch(t.createdAt))]);
    return q.watch();
  }

  /// Relance [userId] pour la semaine commençant le [periodStart] ; l'auteur est posé par le serveur (RLS : il faut
  /// encadrer la personne).
  Future<String> remind({required String workspaceId, required String userId, required DateTime periodStart, String? by}) async {
    final id = newId();
    await db.into(db.reminders).insert(RemindersCompanion.insert(
          id: Value(id),
          workspaceId: workspaceId,
          userId: userId,
          periodStart: dayKey(periodStart),
          createdBy: Value(by),
        ));
    return id;
  }

  Future<void> markReminderSeen(String id) =>
      (db.update(db.reminders)..where((t) => t.id.equals(id))).write(RemindersCompanion(seenAt: Value(nowUtc())));

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
        ..orderBy([(t) => OrderingTerm.desc(epoch(t.createdAt))]))
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

  /// Entrées qu'un nouveau taux peut encore toucher : ni supprimées, ni facturées ; hors admin, ni verrouillées,
  /// ni antérieures à [lockBefore], ni dans une période approuvée, comme `time_entries_guard`.
  Future<List<TimeEntry>> rerateableEntries(String workspaceId,
      {String? projectId, String? userId, required bool isAdmin, DateTime? lockBefore}) async {
    final invoiced = await invoicedEntryIds(workspaceId);
    final q = db.select(db.timeEntries)..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull());
    if (projectId != null) q.where((t) => t.projectId.equals(projectId));
    if (userId != null) q.where((t) => t.userId.equals(userId));
    final entries = (await q.get()).where((e) => !invoiced.contains(e.id));
    if (isAdmin) return entries.toList();
    final approved = await (db.select(db.timesheetSubmissions)
          ..where((s) => s.workspaceId.equals(workspaceId) & s.status.equals('approved') & s.deletedAt.isNull()))
        .get();
    bool frozen(TimeEntry e) {
      final day = dayKey(e.startAt.toLocal());
      if (e.locked || (lockBefore != null && day.compareTo(dayKey(lockBefore)) < 0)) return true;
      return approved.any((s) => s.userId == e.userId && s.periodStart.compareTo(day) <= 0 && s.periodEnd.compareTo(day) >= 0);
    }

    return entries.where((e) => !frozen(e)).toList();
  }

  /// Pose le taux de chaque entrée ([rates] : identifiant → taux en centimes, nul pour aucun).
  Future<void> setEntryRates(Map<String, int?> rates) => db.transaction(() async {
        for (final MapEntry(key: id, value: rate) in rates.entries) {
          await (db.update(db.timeEntries)..where((t) => t.id.equals(id)))
              .write(TimeEntriesCompanion(hourlyRateCents: Value(rate)));
        }
      });

  /// Crée une facture brouillon depuis le temps facturable d'un client sur une période :
  /// une ligne par (projet, taux), ou par (projet, tâche, taux) avec [byTask], quantités en heures. Une entrée
  /// sans taux prend celui applicable aujourd'hui (`CatalogController.entryRate`). Les entrées sont marquées
  /// facturées. Le numéro définitif est attribué par le serveur à la synchronisation.
  Future<String?> createInvoiceFromTime({
    required String workspaceId,
    required String userId,
    required String clientId,
    required DateTime from,
    required DateTime to,
    required String currency,
    required double taxPercent,
    required Map<String, String> projectNames,
    bool byTask = false,
    Map<String, String> taskNames = const {},
  }) async {
    final already = await invoicedEntryIds(workspaceId);
    final projects = await (db.select(db.projects)..where((p) => p.clientId.equals(clientId) & p.deletedAt.isNull())).get();
    final projectIds = projects.map((p) => p.id).toList();
    if (projectIds.isEmpty) return null;
    final projectRates = {for (final p in projects) p.id: p.hourlyRateCents};
    final memberRates = {
      for (final m in await (db.select(db.workspaceMembers)..where((m) => m.workspaceId.equals(workspaceId))).get())
        m.userId: m.hourlyRateCents,
    };
    int rateOf(TimeEntry e) => e.hourlyRateCents ?? projectRates[e.projectId] ?? memberRates[e.userId] ?? 0;
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

    final groups = <(String?, String?, int), List<TimeEntry>>{};
    for (final e in toBill) {
      // Une tâche inconnue (supprimée) compte comme sans tâche.
      final task = byTask && taskNames.containsKey(e.taskId) ? e.taskId : null;
      groups.putIfAbsent((e.projectId, task, rateOf(e)), () => []).add(e);
    }
    // « Projet », ou « Projet — Tâche ».
    String label((String?, String?, int) key) {
      final project = projectNames[key.$1] ?? '';
      final task = taskNames[key.$2];
      return task == null ? project : '$project — $task';
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
            periodEnd: Value(dayKey(addDays(to, -1))),
            createdBy: Value(userId),
          ));
      var position = 0;
      // Par projet, la ligne sans tâche d'abord, puis les tâches dans l'ordre alphabétique.
      int compare((String?, String?, int) a, (String?, String?, int) b) {
        final byProject = (projectNames[a.$1] ?? '').compareTo(projectNames[b.$1] ?? '');
        if (byProject != 0) return byProject;
        final ta = taskNames[a.$2], tb = taskNames[b.$2];
        if (ta == null || tb == null) return ta == tb ? a.$3.compareTo(b.$3) : (ta == null ? -1 : 1);
        final byTask = ta.compareTo(tb);
        return byTask != 0 ? byTask : a.$3.compareTo(b.$3);
      }

      final keys = groups.keys.toList()..sort(compare);
      for (final key in keys) {
        final list = groups[key]!;
        final seconds = list.fold<int>(0, (s, e) => s + e.endAt!.difference(e.startAt).inSeconds);
        final hours = (seconds / 36).round() / 100; // 2 décimales
        await db.into(db.invoiceItems).insert(InvoiceItemsCompanion.insert(
              workspaceId: workspaceId,
              invoiceId: invoiceId,
              position: Value(position++),
              description: Value(label(key)),
              quantity: Value(hours),
              unitPriceCents: Value(key.$3),
              amountCents: Value((hours * key.$3).round()),
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
