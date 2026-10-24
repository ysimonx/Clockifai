import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/team_rights.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/reports/report_model.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';

WorkspaceMember member(String userId, {String role = 'member', String status = 'active', String? pilot}) =>
    WorkspaceMember(
      id: 'm-$userId',
      workspaceId: ws,
      userId: userId,
      role: role,
      status: status,
      displayName: userId,
      capacityHoursPerDay: 7,
      kind: pilot == null ? 'human' : 'agent',
      agentOwnerId: pilot,
    );

TeamRights rights({
  String me = 'chef',
  String role = 'member',
  String? timeForOthers = 'admins',
  Set<String> managed = const {'o1', 'o2'},
}) =>
    TeamRights(
      me: me,
      role: role,
      timeForOthers: timeForOthers,
      members: [member('chef'), member('o1'), member('o2'), member('autre'), member('parti', status: 'inactive')],
      managed: managed,
    );

void main() {
  group('TeamRights (miroir des règles serveur 0009)', () {
    test('un membre sans périmètre ne voit et ne saisit que pour lui', () {
      final r = rights(me: 'autre', managed: const {});
      expect(r.seesTeam, isFalse);
      expect(r.canEditOthers, isFalse);
      expect(r.visibleMembers.map((m) => m.userId), ['autre']);
      expect(r.canEditTimeOf('autre'), isTrue);
      expect(r.canEditTimeOf('o1'), isFalse);
    });

    test('chef d\'équipe : voit son périmètre, saisit seulement si le workspace l\'autorise', () {
      final strict = rights();
      expect(strict.isTeamManager, isTrue);
      expect(strict.visibleMembers.map((m) => m.userId), ['chef', 'o1', 'o2']);
      expect(strict.canEditTimeOf('o1'), isFalse);
      expect(strict.canEditOthers, isFalse);

      final open = rights(timeForOthers: 'admins_and_team_managers');
      expect(open.canEditTimeOf('o1'), isTrue);
      expect(open.canEditTimeOf('autre'), isFalse);
      expect(open.editableMembers.map((m) => m.userId), ['chef', 'o1', 'o2']);
    });

    test('chef d\'équipe : approuve son périmètre, jamais sa propre feuille', () {
      final r = rights();
      expect(r.canApproveTimesheetOf('o1'), isTrue);
      expect(r.canApproveTimesheetOf('chef'), isFalse);
      expect(r.canApproveTimesheetOf('autre'), isFalse);
    });

    test('manager : tout le workspace, saisie selon le réglage ; admin : toujours', () {
      final manager = rights(me: 'chef', role: 'manager', managed: const {});
      expect(manager.manages('autre'), isTrue);
      expect(manager.canEditTimeOf('autre'), isFalse);
      expect(rights(me: 'chef', role: 'manager', managed: const {}, timeForOthers: 'admins_and_team_managers').canEditTimeOf('autre'), isTrue);
      // Membre désactivé : plus de saisie pour lui, sauf par un admin.
      expect(rights(me: 'chef', role: 'manager', managed: const {}, timeForOthers: 'admins_and_team_managers').canEditTimeOf('parti'), isFalse);
      expect(rights(me: 'chef', role: 'admin', managed: const {}).canEditTimeOf('parti'), isTrue);
    });

    test('absences : le chef décide seulement si la politique l\'autorise', () {
      final r = rights();
      TimeOffPolicy policy(String approvers) => TimeOffPolicy(
            id: 'p',
            workspaceId: ws,
            name: 'Congés',
            color: '#10B981',
            unit: 'days',
            paid: true,
            requiresApproval: true,
            approvers: approvers,
            archived: false,
          );
      expect(r.canDecideTimeOff('o1', policy('managers')), isFalse);
      expect(r.canDecideTimeOff('o1', policy('managers_and_team_managers')), isTrue);
      expect(r.canDecideTimeOff('autre', policy('managers_and_team_managers')), isFalse);
    });
  });

  group('Agents Claude (plan 10, D15)', () {
    // « pilote » a son agent « claude-p » ; « chef » encadre « pilote », donc voit aussi son agent.
    TeamRights agentRights(String me, {String role = 'member', String timeForOthers = 'admins',
        Set<String> managed = const {}, Set<String> agentsSeen = const {}}) =>
        TeamRights(
          me: me,
          role: role,
          timeForOthers: timeForOthers,
          members: [member('chef'), member('pilote'), member('autre'), member('claude-p', pilot: 'pilote')],
          managed: managed,
          agentsSeen: agentsSeen,
        );

    test('le pilote corrige le temps de son agent sans en créer, et n\'est pas chef d\'équipe', () {
      final r = agentRights('pilote', agentsSeen: {'claude-p'});
      expect(r.isTeamManager, isFalse);
      expect(r.seesTeam, isFalse);
      expect(r.seesOthers, isTrue);
      expect(r.visibleMembers.map((m) => m.userId), ['pilote', 'claude-p']);
      expect(r.pilots('claude-p'), isTrue);
      expect(r.canEditTimeOf('claude-p'), isTrue);
      expect(r.canCreateTimeFor('claude-p'), isFalse);
      expect(r.editableMembers.map((m) => m.userId), ['pilote']);
      expect(r.canEditOthers, isFalse, reason: 'pas de « Pointage d\'équipe » pour son seul agent');
      expect(r.canApproveTimesheetOf('claude-p'), isFalse);
    });

    test('le chef du pilote lit le temps de l\'agent ; un autre membre non', () {
      final chef = agentRights('chef', managed: {'pilote'}, agentsSeen: {'claude-p'});
      expect(chef.manages('claude-p'), isTrue);
      expect(chef.visibleMembers.map((m) => m.userId), ['chef', 'claude-p', 'pilote']);
      expect(chef.canEditTimeOf('claude-p'), isFalse);
      expect(chef.canApproveTimesheetOf('claude-p'), isFalse);
      // Saisie pour autrui ouverte aux chefs : le serveur (can_edit_others_time) laisse corriger, jamais créer.
      final open = agentRights('chef', timeForOthers: 'admins_and_team_managers', managed: {'pilote'}, agentsSeen: {'claude-p'});
      expect(open.canEditTimeOf('claude-p'), isTrue);
      expect(open.canCreateTimeFor('claude-p'), isFalse);
      expect(open.editableMembers.map((m) => m.userId), ['chef', 'pilote']);

      final autre = agentRights('autre');
      expect(autre.manages('claude-p'), isFalse);
      expect(autre.canEditTimeOf('claude-p'), isFalse);
      expect(autre.visibleMembers.map((m) => m.userId), ['autre']);
    });

    test('un admin corrige les entrées d\'un agent mais n\'en crée pas', () {
      final admin = agentRights('chef', role: 'admin');
      expect(admin.canEditTimeOf('claude-p'), isTrue);
      expect(admin.canCreateTimeFor('claude-p'), isFalse);
      expect(admin.editableMembers.map((m) => m.userId), ['chef', 'autre', 'pilote']);
    });

    test('rapports : filtre « Humains / Agents » et paramètre de l\'export', () {
      expect([for (final k in MemberKind.values) (k.accepts(false), k.accepts(true), k.param)], [
        (true, true, null),
        (true, false, 'human'),
        (false, true, 'agent'),
      ]);
    });
  });

  group('TeamRepository', () {
    late TestDb db;
    late TeamRepository repo;

    setUp(() {
      db = TestDb();
      repo = TeamRepository(db);
    });
    tearDown(() => db.close());

    test('membres d\'un groupe : seules les différences sont écrites', () async {
      final g = await repo.createGroup(ws, ' Équipe A ');
      await repo.setGroupMembers(workspaceId: ws, groupId: g, userIds: {'o1', 'o2'});
      final before = await db.select(db.userGroupMembers).get();
      await repo.setGroupMembers(workspaceId: ws, groupId: g, userIds: {'o2', 'o3'});
      final after = await db.select(db.userGroupMembers).get();
      expect(after.map((r) => r.userId).toSet(), {'o2', 'o3'});
      // La ligne de o2 est conservée telle quelle (même id : pas de resynchronisation).
      expect(after.firstWhere((r) => r.userId == 'o2').id, before.firstWhere((r) => r.userId == 'o2').id);
      expect((await repo.watchGroups(ws).first).single.name, 'Équipe A');
    });

    test('affectations d\'un chef : utilisateurs et groupes, jamais lui-même', () async {
      final g = await repo.createGroup(ws, 'Équipe A');
      await repo.setManagerAssignments(workspaceId: ws, managerId: 'chef', userIds: {'o1', 'chef'}, groupIds: {g});
      var rows = await repo.watchAssignments(ws).first;
      expect(rows.where((a) => a.userId != null).map((a) => a.userId), ['o1']);
      expect(rows.where((a) => a.groupId != null).map((a) => a.groupId), [g]);

      await repo.setManagerAssignments(workspaceId: ws, managerId: 'chef', userIds: {'o2'}, groupIds: {});
      rows = await repo.watchAssignments(ws).first;
      expect(rows.map((a) => a.userId), ['o2']);
    });

    test('supprimer un groupe retire ses membres et les affectations qui le visent', () async {
      final g = await repo.createGroup(ws, 'Équipe A');
      await repo.setGroupMembers(workspaceId: ws, groupId: g, userIds: {'o1'});
      await repo.setManagerAssignments(workspaceId: ws, managerId: 'chef', userIds: {}, groupIds: {g});
      await repo.deleteGroup(g);
      expect(await repo.watchGroups(ws).first, isEmpty);
      expect(await db.select(db.userGroupMembers).get(), isEmpty);
      expect(await db.select(db.teamManagerAssignments).get(), isEmpty);
    });

    test('le référentiel expose le périmètre calculé par le serveur', () async {
      final g = await repo.createGroup(ws, 'Équipe A');
      await repo.setGroupMembers(workspaceId: ws, groupId: g, userIds: {'o1'});
      // team_scope est écrit par le serveur : on simule ce qui redescend par la sync.
      await db.into(db.teamScope).insert(TeamScopeCompanion.insert(workspaceId: ws, managerId: 'chef', userId: 'o1'));
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(workspaceId: ws, userId: 'o1', displayName: const Value('Ouvrier 1')));
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(workspaceId: ws, userId: 'chef', displayName: const Value('Chef')));
      final catalog = CatalogController(CatalogRepository(db), WorkspaceRepository(db), repo)..bind(ws);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(catalog.managedBy('chef'), {'o1'});
      expect(catalog.managersOf('o1').map((m) => m.displayName), ['Chef']);
      expect(catalog.membersOfGroup(g).map((m) => m.displayName), ['Ouvrier 1']);
      catalog.dispose();
    });

    test('les lignes du périmètre qui visent un agent ne font pas de chef d\'équipe (D15)', () async {
      for (final (manager, user) in [('chef', 'pilote'), ('pilote', 'claude-p'), ('chef', 'claude-p')]) {
        await db.into(db.teamScope).insert(TeamScopeCompanion.insert(workspaceId: ws, managerId: manager, userId: user));
      }
      for (final (user, name) in [('chef', 'Chef'), ('pilote', 'Pilote')]) {
        await db.into(db.workspaceMembers).insert(
            WorkspaceMembersCompanion.insert(workspaceId: ws, userId: user, displayName: Value(name), kind: const Value('human')));
      }
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(
          workspaceId: ws, userId: 'claude-p', displayName: const Value('Claude · Pilote'),
          kind: const Value('agent'), agentOwnerId: const Value('pilote')));
      final catalog = CatalogController(CatalogRepository(db), WorkspaceRepository(db), repo)..bind(ws);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(catalog.humans.map((m) => m.userId), unorderedEquals(['chef', 'pilote']));
      expect(catalog.agents.map((m) => m.userId), ['claude-p']);
      expect(catalog.agentsOf('pilote').map((m) => m.userId), ['claude-p']);
      expect(catalog.managedBy('pilote'), isEmpty);
      expect(catalog.managedBy('chef'), {'pilote'});
      expect(catalog.agentsSeenBy('pilote'), {'claude-p'});
      expect(catalog.agentsSeenBy('chef'), {'claude-p'});
      expect(catalog.managersOf('claude-p'), isEmpty);
      expect(catalog.managersOf('pilote').map((m) => m.displayName), ['Chef']);
      catalog.dispose();
    });
  });

  group('Saisie groupée', () {
    late TestDb db;
    late TimeEntryRepository entries;

    setUp(() {
      db = TestDb();
      entries = TimeEntryRepository(db);
    });
    tearDown(() => db.close());

    test('une entrée par personne, avec ses horaires, son taux, ses tags et l\'auteur', () async {
      final day = DateTime.utc(2026, 10, 12);
      final ids = await entries.createForMembers(
        workspaceId: ws,
        createdBy: 'chef',
        draft: EntryDraft(description: 'Montage', projectId: 'p1', tagIds: ['montage']),
        slots: [
          MemberSlot(userId: 'o1', start: day.add(const Duration(hours: 8)), end: day.add(const Duration(hours: 16)), hourlyRateCents: 4000),
          MemberSlot(userId: 'o2', start: day.add(const Duration(hours: 9)), end: day.add(const Duration(hours: 12))),
        ],
      );
      expect(ids, hasLength(2));
      final rows = await entries.watchEntries(workspaceId: ws, from: day, to: day.add(const Duration(days: 1))).first;
      final byUser = {for (final r in rows) r.entry.userId: r};
      expect(byUser['o1']!.seconds, 8 * 3600);
      expect(byUser['o1']!.entry.hourlyRateCents, 4000);
      expect(byUser['o2']!.seconds, 3 * 3600);
      expect(byUser['o2']!.entry.hourlyRateCents, isNull);
      expect(rows.every((r) => r.entry.createdBy == 'chef' && r.entry.description == 'Montage'), isTrue);
      expect(rows.every((r) => r.tagIds.single == 'montage'), isTrue);
      // Les liens de tags portent le propriétaire de l'entrée (RLS et Sync Streams s'en servent).
      final tags = await db.select(db.timeEntryTags).get();
      expect(tags.map((t) => t.userId).toSet(), {'o1', 'o2'});
    });

    test('saisie manuelle pour soi : l\'auteur est la personne elle-même', () async {
      final id = await entries.createManual(
        workspaceId: ws,
        userId: 'o1',
        draft: EntryDraft(),
        start: DateTime.utc(2026, 10, 12, 8),
        end: DateTime.utc(2026, 10, 12, 9),
      );
      final e = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
      expect(e.createdBy, 'o1');
    });
  });
}
