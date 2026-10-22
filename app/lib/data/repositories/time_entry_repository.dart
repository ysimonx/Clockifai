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

/// Un seul chronomètre en cours par tâche (une tâche joue le rôle d'un ticket, plan 04) :
/// [running] vise la même cible si l'un des deux a une tâche et que c'est la même, quelle que soit
/// la description ; sans tâche, s'il a le même projet (ou aucun) et la même description.
bool sameTimerTarget(TimeEntry running, {required String description, String? projectId, String? taskId}) {
  if (taskId != null || running.taskId != null) return running.taskId == taskId;
  return running.projectId == projectId && running.description.trim() == description.trim();
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

/// Une personne et ses horaires dans une saisie groupée (pointage d'équipe, « ajouter du temps pour d'autres »).
class MemberSlot {
  const MemberSlot({required this.userId, required this.start, required this.end, this.hourlyRateCents});
  final String userId;
  final DateTime start;
  final DateTime end;
  final int? hourlyRateCents;
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

  /// Chronomètres en cours de l'utilisateur dans le workspace, les plus récents d'abord
  /// (plusieurs quand `workspaces.max_running_timers` le permet).
  Stream<List<TimeEntry>> watchRunningAll(String workspaceId, String userId) {
    final q = db.select(db.timeEntries)
      ..where((t) =>
          t.workspaceId.equals(workspaceId) & t.userId.equals(userId) & t.endAt.isNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(epoch(t.startAt))]);
    return q.watch();
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

  /// Dernières entrées terminées de l'utilisateur, une par couple description / projet / tâche
  /// (la plus récente) : ce qu'on relance d'un clic (« Continuer »).
  Stream<List<EntryRow>> watchRecent(String workspaceId, String userId, {int limit = 5}) {
    return db
        .customSelect(
          'SELECT te.*, (SELECT group_concat(tet.tag_id) FROM time_entry_tags tet '
          'WHERE tet.time_entry_id = te.id) AS tag_ids '
          'FROM time_entries te WHERE te.workspace_id = ?1 AND te.user_id = ?2 AND te.deleted_at IS NULL '
          'AND te.end_at IS NOT NULL ORDER BY unixepoch(te.start_at) DESC LIMIT 100',
          variables: [Variable<String>(workspaceId), Variable<String>(userId)],
          readsFrom: {db.timeEntries, db.timeEntryTags},
        )
        .watch()
        .map((rows) {
      final seen = <String>{};
      return [
        for (final row in rows.map(_toEntryRow))
          if (seen.add('${row.entry.description}\u0000${row.entry.projectId}\u0000${row.entry.taskId}')) row,
      ].take(limit).toList();
    });
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

  /// Démarre un chronomètre. Au-delà de [maxRunning] chronomètres en cours (0 = illimité),
  /// les plus anciens sont arrêtés dans la même transaction, comme le fait le trigger serveur (0011).
  /// Si la même tâche tourne déjà ([sameTimerTarget]), rien ne change et son id est renvoyé.
  Future<String> start({
    required String workspaceId,
    required String userId,
    required EntryDraft draft,
    DateTime? at,
    int maxRunning = 1,
  }) async {
    final now = (at ?? DateTime.now()).toUtc();
    var id = newId();
    await db.transaction(() async {
      final running = await (db.select(db.timeEntries)
            ..where((t) =>
                t.workspaceId.equals(workspaceId) &
                t.userId.equals(userId) &
                t.endAt.isNull() &
                t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(epoch(t.startAt))]))
          .get();
      // Filet : la tâche tourne déjà, on la laisse tourner (l'interface prévient avant d'arriver ici).
      final same = running
          .where((r) => sameTimerTarget(r, description: draft.description, projectId: draft.projectId, taskId: draft.taskId))
          .firstOrNull;
      if (same != null) {
        id = same.id;
        return;
      }
      final toStop = maxRunning == 0 ? const <TimeEntry>[] : running.skip(maxRunning - 1);
      for (final r in toStop) {
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
            createdBy: Value(userId),
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

  /// Entrée saisie manuellement (déjà terminée). [createdBy] : auteur de la saisie
  /// (affichage immédiat de « saisi par » ; le serveur pose la valeur définitive).
  Future<String> createManual({
    required String workspaceId,
    required String userId,
    required EntryDraft draft,
    required DateTime start,
    required DateTime end,
    String? createdBy,
  }) async {
    final ids = await createForMembers(
      workspaceId: workspaceId,
      slots: [MemberSlot(userId: userId, start: start, end: end, hourlyRateCents: draft.hourlyRateCents)],
      draft: draft,
      createdBy: createdBy,
    );
    return ids.single;
  }

  /// Une entrée terminée par personne (hors ligne compris). Une transaction locale par personne :
  /// le connecteur envoie chaque transaction à part, un refus du serveur (période approuvée,
  /// périmètre modifié entre-temps…) n'emporte donc que l'entrée de la personne concernée.
  Future<List<String>> createForMembers({
    required String workspaceId,
    required List<MemberSlot> slots,
    required EntryDraft draft,
    String? createdBy,
  }) async {
    final ids = <String>[];
    for (final slot in slots) {
      final id = newId();
      ids.add(id);
      await db.transaction(() async {
        await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
              id: Value(id),
              workspaceId: workspaceId,
              userId: slot.userId,
              projectId: Value(draft.projectId),
              taskId: Value(draft.taskId),
              description: Value(draft.description.trim()),
              startAt: slot.start.toUtc(),
              endAt: Value(slot.end.toUtc()),
              durationSeconds: Value(slot.end.difference(slot.start).inSeconds),
              billable: Value(draft.billable),
              hourlyRateCents: Value(slot.hourlyRateCents),
              createdBy: Value(createdBy ?? slot.userId),
            ));
        await _insertTags(id, workspaceId, slot.userId, draft.tagIds);
      });
    }
    return ids;
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
  }) =>
      db.transaction(() => _updateOne(entry,
          description: description,
          projectId: projectId,
          clearProject: clearProject,
          taskId: taskId,
          clearTask: clearTask,
          billable: billable,
          hourlyRateCents: hourlyRateCents,
          start: start,
          end: end,
          tagIds: tagIds));

  /// Même modification pour plusieurs entrées (groupe d'entrées similaires), sans toucher aux horaires.
  /// [hourlyRateFor] : nouveau taux d'une entrée dont le projet change (null : taux inchangé).
  Future<void> updateMany(
    List<TimeEntry> entries, {
    required String description,
    String? projectId,
    String? taskId,
    required bool billable,
    required List<String> tagIds,
    int? Function(TimeEntry entry)? hourlyRateFor,
  }) =>
      db.transaction(() async {
        for (final e in entries) {
          await _updateOne(e,
              description: description,
              projectId: projectId,
              clearProject: projectId == null,
              taskId: taskId,
              clearTask: taskId == null,
              billable: billable,
              hourlyRateCents: projectId != e.projectId ? hourlyRateFor?.call(e) : null,
              tagIds: tagIds);
        }
      });

  Future<void> _updateOne(
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
  }

  /// Suppression logique : le serveur garde la trace, les clients la retirent.
  Future<void> delete(String entryId) async {
    await (db.update(db.timeEntries)..where((t) => t.id.equals(entryId)))
        .write(TimeEntriesCompanion(deletedAt: Value(nowUtc())));
  }

  /// Suppression logique de plusieurs entrées (groupe d'entrées similaires).
  Future<void> deleteMany(List<String> entryIds) async {
    await (db.update(db.timeEntries)..where((t) => t.id.isIn(entryIds)))
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
    String? createdBy,
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
              createdBy: Value(createdBy ?? userId),
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
