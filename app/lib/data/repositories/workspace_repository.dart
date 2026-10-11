import 'package:drift/drift.dart';

import '../drift/database.dart';

class Membership {
  const Membership(this.member, this.workspace);
  final WorkspaceMember member;
  final Workspace workspace;
}

class WorkspaceRepository {
  WorkspaceRepository(this.db);
  final AppDatabase db;

  /// Workspaces dont l'utilisateur est membre actif.
  Stream<List<Membership>> watchMemberships(String userId) {
    final q = db.select(db.workspaceMembers).join([
      innerJoin(db.workspaces, db.workspaces.id.equalsExp(db.workspaceMembers.workspaceId)),
    ])
      ..where(db.workspaceMembers.userId.equals(userId) &
          db.workspaceMembers.status.equals('active') &
          db.workspaceMembers.deletedAt.isNull() &
          db.workspaces.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.workspaces.name.collate(Collate.noCase))]);
    return q.watch().map((rows) => rows
        .map((r) => Membership(r.readTable(db.workspaceMembers), r.readTable(db.workspaces)))
        .toList());
  }

  Stream<List<WorkspaceMember>> watchMembers(String workspaceId) => (db.select(db.workspaceMembers)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.displayName.collate(Collate.noCase))]))
      .watch();

  Stream<Profile?> watchProfile(String userId) =>
      (db.select(db.profiles)..where((t) => t.id.equals(userId))).watchSingleOrNull();

  /// Crée un workspace ; le serveur ajoute l'auteur comme owner (trigger) et
  /// l'adhésion redescend par la sync.
  Future<String> createWorkspace({required String name, required String userId, String currency = 'EUR'}) async {
    final id = newId();
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(
          id: Value(id),
          name: name.trim(),
          currency: Value(currency),
          createdBy: Value(userId),
        ));
    return id;
  }

  Future<void> updateWorkspace(String id, WorkspacesCompanion data) =>
      (db.update(db.workspaces)..where((t) => t.id.equals(id))).write(data);

  Future<void> updateMember(String memberId, WorkspaceMembersCompanion data) =>
      (db.update(db.workspaceMembers)..where((t) => t.id.equals(memberId))).write(data);

  Future<void> updateProfile(String userId, ProfilesCompanion data) =>
      (db.update(db.profiles)..where((t) => t.id.equals(userId))).write(data);

  Future<void> setDefaultWorkspace(String userId, String workspaceId) =>
      updateProfile(userId, ProfilesCompanion(defaultWorkspaceId: Value(workspaceId)));
}
