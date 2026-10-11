import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart' show SyncStatus, SyncStreamSubscription;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/drift/database.dart';
import '../data/powersync/sync_service.dart';
import '../data/repositories/workspace_repository.dart';

/// État de session : utilisateur connecté, workspace courant, rôle, état de sync.
class SessionController extends ChangeNotifier {
  SessionController({required this.sync, required this.workspaces, required this.prefs}) {
    final auth = Supabase.instance.client.auth;
    _onUser(auth.currentUser);
    _authSub = auth.onAuthStateChange.listen((s) => _onUser(s.session?.user));
    _syncSub = sync.status.listen((s) {
      _status = s;
      notifyListeners();
    });
    _status = sync.currentStatus;
  }

  static const _prefKey = 'current_workspace_id';

  final SyncService sync;
  final WorkspaceRepository workspaces;
  final SharedPreferences prefs;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<SyncStatus>? _syncSub;
  StreamSubscription<List<Membership>>? _membershipSub;
  StreamSubscription<Profile?>? _profileSub;

  SyncStreamSubscription? _teamSub;
  String? _teamKey;

  User? _user;
  Profile? _profile;
  List<Membership> _memberships = const [];
  String? _workspaceId;
  SyncStatus? _status;

  User? get user => _user;
  String? get userId => _user?.id;
  bool get isSignedIn => _user != null;
  Profile? get profile => _profile;
  List<Membership> get memberships => _memberships;
  SyncStatus? get syncStatus => _status;

  /// Vrai tant que la première synchronisation n'a pas livré d'adhésion.
  bool get waitingForFirstSync => isSignedIn && _memberships.isEmpty && !(_status?.hasSynced ?? false);

  Membership? get current {
    for (final m in _memberships) {
      if (m.workspace.id == _workspaceId) return m;
    }
    return _memberships.isEmpty ? null : _memberships.first;
  }

  Workspace? get workspace => current?.workspace;
  WorkspaceMember? get member => current?.member;
  String? get workspaceId => current?.workspace.id;
  String get role => member?.role ?? 'member';
  bool get isManager => const {'owner', 'admin', 'manager'}.contains(role);
  bool get isAdmin => const {'owner', 'admin'}.contains(role);
  /// Miroir de `can_create_task` (0010) ; la RLS reste juge (projet actif du workspace).
  bool get canCreateTasks => isManager || (workspace?.taskCreation ?? 'everyone') == 'everyone';
  String get displayName => _profile?.displayName.isNotEmpty == true
      ? _profile!.displayName
      : (_user?.email ?? '');

  @override
  void notifyListeners() {
    _syncTeamSubscription();
    super.notifyListeners();
  }

  /// Les managers reçoivent en continu les données de l'équipe du workspace courant.
  void _syncTeamSubscription() {
    final key = isManager && workspaceId != null ? workspaceId : null;
    if (key == _teamKey) return;
    _teamKey = key;
    _teamSub?.unsubscribe();
    _teamSub = null;
    if (key == null) return;
    sync.subscribeTeam(key).then((s) {
      if (_teamKey == key) {
        _teamSub = s;
      } else {
        s.unsubscribe();
      }
    }).catchError((Object e) => debugPrint('team stream: $e'));
  }

  void _onUser(User? user) {
    if (user?.id == _user?.id) return;
    _user = user;
    _membershipSub?.cancel();
    _profileSub?.cancel();
    _memberships = const [];
    _profile = null;
    if (user != null) {
      _workspaceId = prefs.getString('$_prefKey:${user.id}');
      _membershipSub = workspaces.watchMemberships(user.id).listen((list) {
        _memberships = list;
        notifyListeners();
      });
      _profileSub = workspaces.watchProfile(user.id).listen((p) {
        _profile = p;
        _workspaceId ??= p?.defaultWorkspaceId;
        notifyListeners();
      });
    } else {
      _workspaceId = null;
    }
    notifyListeners();
  }

  Future<void> selectWorkspace(String id) async {
    _workspaceId = id;
    if (_user != null) {
      await prefs.setString('$_prefKey:${_user!.id}', id);
      await workspaces.setDefaultWorkspace(_user!.id, id);
    }
    notifyListeners();
  }

  Future<void> signOut() => Supabase.instance.client.auth.signOut();

  @override
  void dispose() {
    _teamSub?.unsubscribe();
    _authSub?.cancel();
    _syncSub?.cancel();
    _membershipSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
