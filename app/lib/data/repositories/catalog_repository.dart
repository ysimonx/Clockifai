import 'package:drift/drift.dart';

import '../drift/database.dart';

/// Référentiel d'un workspace : clients, projets, tâches, tags.
/// Écritures soumises à la RLS côté serveur (manager+) : un refus remonte via
/// SyncService.rejections et la donnée locale est corrigée à la sync suivante.
class CatalogRepository {
  CatalogRepository(this.db);
  final AppDatabase db;

  // ------------------------------------------------------------------ lectures
  Stream<List<Project>> watchProjects(String workspaceId) => (db.select(db.projects)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
      .watch();

  Stream<List<ClientItem>> watchClients(String workspaceId) => (db.select(db.clients)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
      .watch();

  Stream<List<Task>> watchTasks(String workspaceId) => (db.select(db.tasks)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
      .watch();

  Stream<List<Tag>> watchTags(String workspaceId) => (db.select(db.tags)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
      .watch();

  // ------------------------------------------------------------------ clients
  Future<String> createClient(String workspaceId,
      {required String name, String? note, String? currency, String? address, String? email}) async {
    final id = newId();
    await db.into(db.clients).insert(ClientsCompanion.insert(
          id: Value(id),
          workspaceId: workspaceId,
          name: name.trim(),
          note: Value(_blankToNull(note)),
          currencyOverride: Value(_blankToNull(currency)),
          address: Value(_blankToNull(address)),
          email: Value(_blankToNull(email)),
        ));
    return id;
  }

  Future<void> updateClient(String id,
          {String? name, String? note, String? currency, String? address, String? email, bool? archived}) =>
      (db.update(db.clients)..where((t) => t.id.equals(id))).write(ClientsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        note: note == null ? const Value.absent() : Value(_blankToNull(note)),
        currencyOverride: currency == null ? const Value.absent() : Value(_blankToNull(currency)),
        address: address == null ? const Value.absent() : Value(_blankToNull(address)),
        email: email == null ? const Value.absent() : Value(_blankToNull(email)),
        archived: archived == null ? const Value.absent() : Value(archived),
      ));

  Future<void> deleteClient(String id) =>
      (db.update(db.clients)..where((t) => t.id.equals(id))).write(ClientsCompanion(deletedAt: Value(nowUtc())));

  /// Annuler la suppression de [before] (lu avant [deleteClient]).
  Future<void> restoreClient(ClientItem before) => db.transaction(() => db.restoreRow(db.clients, before.toCompanion(false)));

  // ------------------------------------------------------------------ projets
  Future<String> createProject(String workspaceId, ProjectsCompanion data) async {
    final id = newId();
    await db.into(db.projects).insert(data.copyWith(id: Value(id), workspaceId: Value(workspaceId)));
    return id;
  }

  Future<void> updateProject(String id, ProjectsCompanion data) =>
      (db.update(db.projects)..where((t) => t.id.equals(id))).write(data);

  Future<void> deleteProject(String id) =>
      (db.update(db.projects)..where((t) => t.id.equals(id))).write(ProjectsCompanion(deletedAt: Value(nowUtc())));

  /// Annuler la suppression de [before] (lu avant [deleteProject]).
  Future<void> restoreProject(Project before) => db.transaction(() => db.restoreRow(db.projects, before.toCompanion(false)));

  // ------------------------------------------------------------------ tâches
  Future<String> createTask(String workspaceId, String projectId, String name, {int? estimateSeconds}) async {
    final id = newId();
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: Value(id),
          workspaceId: workspaceId,
          projectId: projectId,
          name: name.trim(),
          estimateSeconds: Value(estimateSeconds),
        ));
    return id;
  }

  Future<void> updateTask(String id, {String? name, String? status, int? estimateSeconds}) =>
      (db.update(db.tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        status: status == null ? const Value.absent() : Value(status),
        estimateSeconds: estimateSeconds == null ? const Value.absent() : Value(estimateSeconds),
      ));

  Future<void> deleteTask(String id) =>
      (db.update(db.tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(deletedAt: Value(nowUtc())));

  // ------------------------------------------------------------------ tags
  Future<String> createTag(String workspaceId, String name, {String color = '#6B7280'}) async {
    final id = newId();
    await db.into(db.tags).insert(TagsCompanion.insert(
          id: Value(id),
          workspaceId: workspaceId,
          name: name.trim(),
          color: Value(color),
        ));
    return id;
  }

  Future<void> updateTag(String id, {String? name, String? color, bool? archived}) =>
      (db.update(db.tags)..where((t) => t.id.equals(id))).write(TagsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        color: color == null ? const Value.absent() : Value(color),
        archived: archived == null ? const Value.absent() : Value(archived),
      ));

  Future<void> deleteTag(String id) =>
      (db.update(db.tags)..where((t) => t.id.equals(id))).write(TagsCompanion(deletedAt: Value(nowUtc())));

  /// Annuler la suppression de [before] (lu avant [deleteTag]).
  Future<void> restoreTag(Tag before) => db.transaction(() => db.restoreRow(db.tags, before.toCompanion(false)));

  static String? _blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}
