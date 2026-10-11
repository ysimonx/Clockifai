import 'package:drift/drift.dart';

import '../drift/database.dart';

/// Une entrée de temps et les identifiants de ses tags.
class EntryRow {
  const EntryRow(this.entry, this.tagIds);
  final TimeEntry entry;
  final List<String> tagIds;

  int get seconds {
    final e = entry;
    final end = e.endAt ?? DateTime.now().toUtc();
    return end.difference(e.startAt).inSeconds.clamp(0, 1 << 31);
  }
}

/// Paramètres d'une nouvelle entrée ou d'un nouveau chronomètre.
class EntryDraft {
  EntryDraft({
    this.description = '',
    this.projectId,
    this.taskId,
    this.billable = true,
    this.hourlyRateCents,
    this.tagIds = const [],
  });

  String description;
  String? projectId;
  String? taskId;
  bool billable;
  int? hourlyRateCents;
  List<String> tagIds;
}

/// Toutes les lectures/écritures d'entrées de temps passent par la base locale.
/// PowerSync se charge d'envoyer les modifications au serveur et de récupérer
/// celles des autres appareils.
class TimeEntryRepository {
  TimeEntryRepository(this.db);
  final AppDatabase db;

  /// Chronomètre en cours de l'utilisateur dans le workspace.
  Stream<TimeEntry?> watchRunning(String workspaceId, String userId) {
    final q = db.select(db.timeEntries)
      ..where((t) =>
          t.workspaceId.equals(workspaceId) & t.userId.equals(userId) & t.endAt.isNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(epoch(t.startAt))])
      ..limit(1);
    return q.watchSingleOrNull();
  }

  /// Entrées démarrées dans [from, to[ (UTC), les plus récentes d'abord.
  /// [userId] null = toute l'équipe (selon ce que la sync a fourni).
  Stream<List<EntryRow>> watchEntries({
    required String workspaceId,
    String? userId,
    required DateTime from,
    required DateTime to,
    bool includeRunning = false,
  }) {
    final where = StringBuffer(
        'te.workspace_id = ?1 AND te.deleted_at IS NULL AND unixepoch(te.start_at) >= ?2 AND unixepoch(te.start_at) < ?3');
    final vars = <Variable>[
      Variable<String>(workspaceId),
      epochOf(from),
      epochOf(to),
    ];
    if (userId != null) {
      where.write(' AND te.user_id = ?4');
      vars.add(Variable<String>(userId));
    }
    if (!includeRunning) where.write(' AND te.end_at IS NOT NULL');

    return db
        .customSelect(
          'SELECT te.*, (SELECT group_concat(tet.tag_id) FROM time_entry_tags tet '
          'WHERE tet.time_entry_id = te.id) AS tag_ids '
          'FROM time_entries te WHERE $where ORDER BY unixepoch(te.start_at) DESC',
          variables: vars,
          readsFrom: {db.timeEntries, db.timeEntryTags},
        )
        .watch()
        .map((rows) => rows.map(_toEntryRow).toList());
  }

  EntryRow _toEntryRow(QueryRow row) {
    final entry = db.timeEntries.map(row.data);
    final raw = row.data['tag_ids'] as String?;
    return EntryRow(entry, raw == null || raw.isEmpty ? const [] : raw.split(','));
  }

  /// Temps total (terminé) par projet : clé null = sans projet.
  /// [userId] null = toutes les entrées présentes localement (équipe si synchronisée).
  Stream<Map<String?, int>> watchTotalsByProject(String workspaceId, {String? userId}) {
    final vars = <Variable>[Variable<String>(workspaceId)];
    var where = 'workspace_id = ?1 AND deleted_at IS NULL AND end_at IS NOT NULL';
    if (userId != null) {
      where += ' AND user_id = ?2';
      vars.add(Variable<String>(userId));
    }
    return db
        .customSelect(
          'SELECT project_id, SUM(unixepoch(end_at) - unixepoch(start_at)) AS secs '
          'FROM time_entries WHERE $where GROUP BY project_id',
          variables: vars,
          readsFrom: {db.timeEntries},
        )
        .watch()
        .map((rows) => {for (final r in rows) r.read<String?>('project_id'): r.read<int?>('secs') ?? 0});
  }

  /// Démarre un chronomètre (arrête d'abord celui qui tourne, dans la même transaction).
  Future<String> start({
    required String workspaceId,
    required String userId,
    required EntryDraft draft,
    DateTime? at,
  }) async {
    final now = (at ?? DateTime.now()).toUtc();
    final id = newId();
    await db.transaction(() async {
      final running = await (db.select(db.timeEntries)
            ..where((t) =>
                t.workspaceId.equals(workspaceId) &
                t.userId.equals(userId) &
                t.endAt.isNull() &
                t.deletedAt.isNull()))
          .get();
      for (final r in running) {
        final end = now.isBefore(r.startAt) ? r.startAt : now;
        await (db.update(db.timeEntries)..where((t) => t.id.equals(r.id))).write(
            TimeEntriesCompanion(endAt: Value(end), durationSeconds: Value(end.difference(r.startAt).inSeconds)));
      }
      await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
            id: Value(id),
            workspaceId: workspaceId,
            userId: userId,
            projectId: Value(draft.projectId),
            taskId: Value(draft.taskId),
            description: Value(draft.description.trim()),
            startAt: now,
            billable: Value(draft.billable),
            hourlyRateCents: Value(draft.hourlyRateCents),
          ));
      await _insertTags(id, workspaceId, userId, draft.tagIds);
    });
    return id;
  }

  Future<void> stop(String entryId, {DateTime? at}) async {
    final end = (at ?? DateTime.now()).toUtc();
    final entry = await (db.select(db.timeEntries)..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (entry == null) return;
    // Un chronomètre ne peut pas finir avant d'avoir commencé (horloges désynchronisées).
    final safeEnd = end.isBefore(entry.startAt) ? entry.startAt : end;
    await (db.update(db.timeEntries)..where((t) => t.id.equals(entryId)))
        .write(TimeEntriesCompanion(endAt: Value(safeEnd), durationSeconds: Value(safeEnd.difference(entry.startAt).inSeconds)));
  }

  /// Entrée saisie manuellement (déjà terminée).
  Future<String> createManual({
    required String workspaceId,
    required String userId,
    required EntryDraft draft,
    required DateTime start,
    required DateTime end,
  }) async {
    final id = newId();
    await db.transaction(() async {
      await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
            id: Value(id),
            workspaceId: workspaceId,
            userId: userId,
            projectId: Value(draft.projectId),
            taskId: Value(draft.taskId),
            description: Value(draft.description.trim()),
            startAt: start.toUtc(),
            endAt: Value(end.toUtc()),
            durationSeconds: Value(end.difference(start).inSeconds),
            billable: Value(draft.billable),
            hourlyRateCents: Value(draft.hourlyRateCents),
          ));
      await _insertTags(id, workspaceId, userId, draft.tagIds);
    });
    return id;
  }

  /// Met à jour les champs d'une entrée (null = inchangé, sauf [clearProject]).
  Future<void> update(
    TimeEntry entry, {
    String? description,
    String? projectId,
    bool clearProject = false,
    String? taskId,
    bool clearTask = false,
    bool? billable,
    int? hourlyRateCents,
    DateTime? start,
    DateTime? end,
    List<String>? tagIds,
  }) async {
    await db.transaction(() async {
      final newStart = start?.toUtc() ?? entry.startAt;
      final newEnd = end?.toUtc() ?? entry.endAt;
      await (db.update(db.timeEntries)..where((t) => t.id.equals(entry.id))).write(TimeEntriesCompanion(
        description: description == null ? const Value.absent() : Value(description.trim()),
        projectId: clearProject ? const Value(null) : (projectId == null ? const Value.absent() : Value(projectId)),
        taskId: (clearTask || clearProject) ? const Value(null) : (taskId == null ? const Value.absent() : Value(taskId)),
        billable: billable == null ? const Value.absent() : Value(billable),
        hourlyRateCents: hourlyRateCents == null ? const Value.absent() : Value(hourlyRateCents),
        startAt: start == null ? const Value.absent() : Value(newStart),
        endAt: end == null ? const Value.absent() : Value(newEnd),
        durationSeconds: (start == null && end == null) || newEnd == null
            ? const Value.absent()
            : Value(newEnd.difference(newStart).inSeconds),
      ));
      if (tagIds != null) await _replaceTags(entry, tagIds);
    });
  }

  /// Suppression logique : le serveur garde la trace, les clients la retirent.
  Future<void> delete(String entryId) async {
    await (db.update(db.timeEntries)..where((t) => t.id.equals(entryId)))
        .write(TimeEntriesCompanion(deletedAt: Value(nowUtc())));
  }

  Future<List<String>> tagIdsOf(String entryId) async {
    final rows = await (db.select(db.timeEntryTags)..where((t) => t.timeEntryId.equals(entryId))).get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Ajuste le temps total d'un projet sur une journée (feuille de temps hebdomadaire).
  /// Ajout : nouvelle entrée placée après la dernière de la journée (09:00 par défaut).
  /// Retrait : raccourcit puis supprime les entrées les plus récentes de la cellule.
  Future<void> setDayTotal({
    required String workspaceId,
    required String userId,
    required String? projectId,
    required DateTime dayLocal,
    required int targetSeconds,
    required bool billable,
    int? hourlyRateCents,
  }) async {
    final dayStart = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final all = await (db.select(db.timeEntries)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) &
              t.userId.equals(userId) &
              t.deletedAt.isNull() &
              t.endAt.isNotNull() &
              epoch(t.startAt).isBiggerOrEqual(epochOf(dayStart)) &
              epoch(t.startAt).isSmallerThan(epochOf(dayEnd)))
          ..orderBy([(t) => OrderingTerm.asc(epoch(t.startAt))]))
        .get();
    final cell = all.where((e) => e.projectId == projectId).toList();
    final current = cell.fold<int>(0, (s, e) => s + e.endAt!.difference(e.startAt).inSeconds);
    var delta = targetSeconds - current;
    if (delta == 0) return;

    await db.transaction(() async {
      if (delta > 0) {
        final lastEnd = all.isEmpty ? null : all.map((e) => e.endAt!).reduce((a, b) => a.isAfter(b) ? a : b);
        var start = lastEnd?.toLocal() ?? dayStart.add(const Duration(hours: 9));
        if (!start.add(Duration(seconds: delta)).isBefore(dayEnd)) {
          start = dayEnd.subtract(Duration(seconds: delta));
        }
        await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
              workspaceId: workspaceId,
              userId: userId,
              projectId: Value(projectId),
              startAt: start.toUtc(),
              endAt: Value(start.add(Duration(seconds: delta)).toUtc()),
              durationSeconds: Value(delta),
              billable: Value(billable),
              hourlyRateCents: Value(hourlyRateCents),
            ));
      } else {
        var toRemove = -delta;
        for (final e in cell.reversed) {
          if (toRemove <= 0) break;
          final len = e.endAt!.difference(e.startAt).inSeconds;
          if (len <= toRemove) {
            await delete(e.id);
            toRemove -= len;
          } else {
            final newEnd = e.endAt!.subtract(Duration(seconds: toRemove));
            await (db.update(db.timeEntries)..where((t) => t.id.equals(e.id)))
                .write(TimeEntriesCompanion(endAt: Value(newEnd), durationSeconds: Value(len - toRemove)));
            toRemove = 0;
          }
        }
      }
    });
  }

  Future<void> _insertTags(String entryId, String workspaceId, String userId, List<String> tagIds) async {
    for (final tagId in tagIds.toSet()) {
      await db.into(db.timeEntryTags).insert(TimeEntryTagsCompanion.insert(
            workspaceId: workspaceId,
            userId: userId,
            timeEntryId: entryId,
            tagId: tagId,
          ));
    }
  }

  Future<void> _replaceTags(TimeEntry entry, List<String> tagIds) async {
    final existing = await (db.select(db.timeEntryTags)..where((t) => t.timeEntryId.equals(entry.id))).get();
    final wanted = tagIds.toSet();
    for (final row in existing) {
      if (!wanted.remove(row.tagId)) {
        await (db.delete(db.timeEntryTags)..where((t) => t.id.equals(row.id))).go();
      }
    }
    await _insertTags(entry.id, entry.workspaceId, entry.userId, wanted.toList());
  }
}
