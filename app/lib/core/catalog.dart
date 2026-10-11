import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/drift/database.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/workspace_repository.dart';

/// Référentiel du workspace courant, gardé en mémoire et tenu à jour par les flux Drift.
/// Les écrans résolvent projets / clients / tags / membres par identifiant sans requête.
class CatalogController extends ChangeNotifier {
  CatalogController(this.repo, this.workspaces);

  final CatalogRepository repo;
  final WorkspaceRepository workspaces;

  String? _workspaceId;
  final _subs = <StreamSubscription<dynamic>>[];

  List<Project> projects = const [];
  List<ClientItem> clients = const [];
  List<Task> tasks = const [];
  List<Tag> tags = const [];
  List<WorkspaceMember> members = const [];

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
    _reindex();
    if (workspaceId == null) return;
    _subs
      ..add(repo.watchProjects(workspaceId).listen((v) => _set(() => projects = v)))
      ..add(repo.watchClients(workspaceId).listen((v) => _set(() => clients = v)))
      ..add(repo.watchTasks(workspaceId).listen((v) => _set(() => tasks = v)))
      ..add(repo.watchTags(workspaceId).listen((v) => _set(() => tags = v)))
      ..add(workspaces.watchMembers(workspaceId).listen((v) => _set(() => members = v)));
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

  List<Project> get activeProjects => projects.where((p) => !p.archived).toList();
  List<Tag> get activeTags => tags.where((t) => !t.archived).toList();
  List<Task> tasksOf(String? projectId) =>
      tasks.where((t) => t.projectId == projectId && t.status == 'active').toList();

  /// Taux horaire applicable : projet, sinon membre.
  int? rateFor({required String? projectId, required String userId}) =>
      project(projectId)?.hourlyRateCents ?? memberOf(userId)?.hourlyRateCents;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
