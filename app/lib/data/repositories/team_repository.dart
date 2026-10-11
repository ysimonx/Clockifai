import 'package:drift/drift.dart';

import '../drift/database.dart';

/// Groupes d'utilisateurs et chefs d'équipe (écritures réservées aux admins, vérifiées par la RLS).
/// Le périmètre effectif (`team_scope`) est recalculé par le serveur et redescend par la sync.
class TeamRepository {
  TeamRepository(this.db);
  final AppDatabase db;

  Stream<List<UserGroup>> watchGroups(String workspaceId) => (db.select(db.userGroups)
        ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))]))
      .watch();

  Stream<List<UserGroupMember>> watchGroupMembers(String workspaceId) =>
      (db.select(db.userGroupMembers)..where((t) => t.workspaceId.equals(workspaceId))).watch();

  Stream<List<TeamManagerAssignment>> watchAssignments(String workspaceId) =>
      (db.select(db.teamManagerAssignments)..where((t) => t.workspaceId.equals(workspaceId))).watch();

  Stream<List<TeamScopeRow>> watchScope(String workspaceId) =>
      (db.select(db.teamScope)..where((t) => t.workspaceId.equals(workspaceId))).watch();

  Future<String> createGroup(String workspaceId, String name) async {
    final id = newId();
    await db.into(db.userGroups).insert(UserGroupsCompanion.insert(id: Value(id), workspaceId: workspaceId, name: name.trim()));
    return id;
  }

  Future<void> renameGroup(String id, String name) =>
      (db.update(db.userGroups)..where((t) => t.id.equals(id))).write(UserGroupsCompanion(name: Value(name.trim())));

  /// Suppression logique du groupe ; ses membres et les affectations qui le visent sont retirés.
  Future<void> deleteGroup(String id) => db.transaction(() async {
        await (db.update(db.userGroups)..where((t) => t.id.equals(id))).write(UserGroupsCompanion(deletedAt: Value(nowUtc())));
        await (db.delete(db.userGroupMembers)..where((t) => t.groupId.equals(id))).go();
        await (db.delete(db.teamManagerAssignments)..where((t) => t.groupId.equals(id))).go();
      });

  /// Remplace les membres d'un groupe (seules les différences sont écrites).
  Future<void> setGroupMembers({required String workspaceId, required String groupId, required Set<String> userIds}) =>
      db.transaction(() async {
        final existing = await (db.select(db.userGroupMembers)..where((t) => t.groupId.equals(groupId))).get();
        final wanted = {...userIds};
        for (final row in existing) {
          if (!wanted.remove(row.userId)) {
            await (db.delete(db.userGroupMembers)..where((t) => t.id.equals(row.id))).go();
          }
        }
        for (final uid in wanted) {
          await db.into(db.userGroupMembers).insert(
              UserGroupMembersCompanion.insert(workspaceId: workspaceId, groupId: groupId, userId: uid));
        }
      });

  /// Remplace ce qu'encadre un chef d'équipe : utilisateurs et groupes (seules les différences sont écrites).
  Future<void> setManagerAssignments({
    required String workspaceId,
    required String managerId,
    required Set<String> userIds,
    required Set<String> groupIds,
  }) =>
      db.transaction(() async {
        final existing = await (db.select(db.teamManagerAssignments)
              ..where((t) => t.workspaceId.equals(workspaceId) & t.managerId.equals(managerId)))
            .get();
        final users = {...userIds}..remove(managerId);
        final groups = {...groupIds};
        for (final row in existing) {
          final keep = row.userId != null ? users.remove(row.userId) : groups.remove(row.groupId);
          if (!keep) {
            await (db.delete(db.teamManagerAssignments)..where((t) => t.id.equals(row.id))).go();
          }
        }
        for (final uid in users) {
          await db.into(db.teamManagerAssignments).insert(TeamManagerAssignmentsCompanion.insert(
              workspaceId: workspaceId, managerId: managerId, userId: Value(uid)));
        }
        for (final gid in groups) {
          await db.into(db.teamManagerAssignments).insert(TeamManagerAssignmentsCompanion.insert(
              workspaceId: workspaceId, managerId: managerId, groupId: Value(gid)));
        }
      });
}
