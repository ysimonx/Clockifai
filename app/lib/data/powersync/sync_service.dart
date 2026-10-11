import 'dart:async';

import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../drift/database.dart';
import 'connector.dart';
import 'schema.dart';

/// Ouvre la base locale (PowerSync + Drift) et pilote la connexion de sync
/// au rythme de l'authentification Supabase.
class SyncService {
  SyncService._(this.powersync, this.db);

  final PowerSyncDatabase powersync;
  final AppDatabase db;

  final _rejections = StreamController<UploadRejection>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  SupabaseConnector? _connector;

  /// Modifications locales refusées par le serveur (RLS, verrouillage…), à afficher.
  Stream<UploadRejection> get rejections => _rejections.stream;

  Stream<SyncStatus> get status => powersync.statusStream;
  SyncStatus get currentStatus => powersync.currentStatus;

  static Future<SyncService> open() async {
    final powersync = PowerSyncDatabase(schema: schema, path: await _dbPath());
    await powersync.initialize();
    final db = AppDatabase(SqliteAsyncDriftConnection(powersync));
    final service = SyncService._(powersync, db);
    service._listenAuth();
    return service;
  }

  void _listenAuth() {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) _connect();
    _authSub = auth.onAuthStateChange.listen((data) async {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          _connect();
        case AuthChangeEvent.signedOut:
          _connector = null;
          // Efface les données locales : un autre utilisateur peut se connecter sur l'appareil.
          await powersync.disconnectAndClear();
        case AuthChangeEvent.tokenRefreshed:
          _connector?.prefetchCredentials();
        default:
          break;
      }
    });
  }

  void _connect() {
    if (_connector != null) return;
    _connector = SupabaseConnector(onRejected: _rejections.add);
    powersync.connect(connector: _connector!);
  }

  /// Synchronise les données de toute l'équipe d'un workspace (rôles manager+) :
  /// entrées, feuilles soumises, absences, planning, factures.
  /// Le serveur filtre : un simple membre ne reçoit rien de plus.
  Future<SyncStreamSubscription> subscribeTeam(String workspaceId) {
    return powersync
        .syncStream('team_data', {'workspace_id': workspaceId})
        .subscribe(ttl: const Duration(days: 7));
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _rejections.close();
    await db.close();
    await powersync.close();
  }

  static Future<String> _dbPath() async {
    const name = 'clockifai.db';
    if (kIsWeb) return name;
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, name);
  }
}
