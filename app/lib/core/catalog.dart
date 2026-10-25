import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/drift/database.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/team_repository.dart';
import '../data/repositories/workspace_repository.dart';

/// Référentiel du workspace courant, gardé en mémoire et tenu à jour par les flux Drift.
/// Les écrans résolvent projets / clients / tags / membres par identifiant sans requête.
class CatalogController extends ChangeNotifier {
  CatalogController(this.repo, this.workspaces, this.teams);

  final CatalogRepository repo;
  final WorkspaceRepository workspaces;
  final TeamRepository teams;

  String? _workspaceId;
  final _subs = <StreamSubscription<dynamic>>[];

  List<Project> projects = const [];
  List<ClientItem> clients = const [];
  List<Task> tasks = const [];
  List<Tag> tags = const [];
  List<WorkspaceMember> members = const [];
  List<UserGroup> groups = const [];
  List<UserGroupMember> groupMembers = const [];
  List<TeamManagerAssignment> assignments = const [];
  List<TeamScopeRow> scope = const [];

  Map<String, Project> _projectById = const {};
  Map<String, ClientItem> _clientById = const {};
  Map<String, Task> _taskById = const {};
  Map<String, Tag> _tagById = const {};
  Map<String, WorkspaceMember> _memberByUser = const {};

  String? get workspaceId => _workspaceId;

  void bind(String? workspaceId) {
    if (workspaceId == _workspaceId) return;
    _workspaceId = workspaceId;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    projects = const [];
    clients = const [];
    tasks = const [];
    tags = const [];
    members = const [];
    groups = const [];
    groupMembers = const [];
    assignments = const [];
    scope = const [];
    _reindex();
    if (workspaceId == null) return;
    _subs
      ..add(repo.watchProjects(workspaceId).listen((v) => _set(() => projects = v)))
      ..add(repo.watchClients(workspaceId).listen((v) => _set(() => clients = v)))
      ..add(repo.watchTasks(workspaceId).listen((v) => _set(() => tasks = v)))
      ..add(repo.watchTags(workspaceId).listen((v) => _set(() => tags = v)))
      ..add(workspaces.watchMembers(workspaceId).listen((v) => _set(() => members = v)))
      ..add(teams.watchGroups(workspaceId).listen((v) => _set(() => groups = v)))
      ..add(teams.watchGroupMembers(workspaceId).listen((v) => _set(() => groupMembers = v)))
      ..add(teams.watchAssignments(workspaceId).listen((v) => _set(() => assignments = v)))
      ..add(teams.watchScope(workspaceId).listen((v) => _set(() => scope = v)));
  }

  void _set(void Function() apply) {
    apply();
    _reindex();
    notifyListeners();
  }

  void _reindex() {
    _projectById = {for (final p in projects) p.id: p};
    _clientById = {for (final c in clients) c.id: c};
    _taskById = {for (final t in tasks) t.id: t};
    _tagById = {for (final t in tags) t.id: t};
    _memberByUser = {for (final m in members) m.userId: m};
  }

  Project? project(String? id) => id == null ? null : _projectById[id];
  ClientItem? client(String? id) => id == null ? null : _clientById[id];
  Task? task(String? id) => id == null ? null : _taskById[id];
  Tag? tag(String id) => _tagById[id];
  WorkspaceMember? memberOf(String userId) => _memberByUser[userId];
  ClientItem? clientOfProject(String? projectId) => client(project(projectId)?.clientId);

  /// Agents Claude (plan 10) : membres techniques, un par pilote, qui ne pointent pas.
  bool isAgent(String? userId) => userId != null && memberOf(userId)?.kind == 'agent';
  List<WorkspaceMember> get humans => members.where((m) => m.kind != 'agent').toList();
  List<WorkspaceMember> get agents => members.where((m) => m.kind == 'agent').toList();
  List<WorkspaceMember> agentsOf(String? pilotId) =>
      pilotId == null ? const [] : members.where((m) => m.kind == 'agent' && m.agentOwnerId == pilotId).toList();

  List<Project> get activeProjects => projects.where((p) => !p.archived).toList();
  List<Tag> get activeTags => tags.where((t) => !t.archived).toList();
  List<Task> tasksOf(String? projectId) =>
      tasks.where((t) => t.projectId == projectId && t.status == 'active').toList();

  /// Membres actifs d'un groupe.
  List<WorkspaceMember> membersOfGroup(String groupId) => [
        for (final gm in groupMembers)
          if (gm.groupId == groupId) ?memberOf(gm.userId),
      ];

  /// Collaborateurs (humains) encadrés par [managerId] (périmètre calculé par le serveur).
  /// Les lignes qui visent un agent (pilote, ou chef du pilote) n'en font pas un chef d'équipe (plan 10, D15).
  Set<String> managedBy(String? managerId) => managerId == null
      ? const {}
      : {for (final s in scope) if (s.managerId == managerId && !isAgent(s.userId)) s.userId};

  /// Agents dont [userId] voit le temps : le sien, et ceux des personnes qu'il encadre (D15).
  Set<String> agentsSeenBy(String? userId) => userId == null
      ? const {}
      : {for (final s in scope) if (s.managerId == userId && isAgent(s.userId)) s.userId};

  /// Chefs d'équipe de [userId] (aucun pour un agent : il suit son pilote).
  List<WorkspaceMember> managersOf(String userId) => isAgent(userId)
      ? const []
      : [
          for (final s in scope)
            if (s.userId == userId) ?memberOf(s.managerId),
        ];

  /// Taux horaire applicable : projet, sinon membre.
  int? rateFor({required String? projectId, required String userId}) =>
      project(projectId)?.hourlyRateCents ?? memberOf(userId)?.hourlyRateCents;

  /// Taux d'une entrée : celui posé à la saisie, sinon le taux applicable aujourd'hui (entrée saisie avant que le
  /// projet ou le membre ait un taux). Même règle dans les factures et les exports.
  int? entryRate(TimeEntry e) => e.hourlyRateCents ?? rateFor(projectId: e.projectId, userId: e.userId);

  /// Facturable par défaut : selon le projet. Pour un agent Claude, l'exception du projet, sinon le réglage
  /// du workspace ([agentBilling] `never` : jamais), comme `entry_defaults` côté serveur (plan 10, D16).
  bool billableFor({required String? projectId, required String userId, String? agentBilling}) {
    final p = project(projectId);
    if (isAgent(userId) && p?.agentBillable != null) return p!.agentBillable!;
    if (isAgent(userId) && agentBilling == 'never') return false;
    return p?.billableDefault ?? true;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
