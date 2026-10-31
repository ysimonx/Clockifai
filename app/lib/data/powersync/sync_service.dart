import 'dart:async';

import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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
  Timer? _watchdog;
  AppLifecycleListener? _lifecycle;
  DateTime? _lastReconnect;

  /// Sync sans point de contrôle depuis ce délai : reconnectée. Après une mise en veille, le flux HTTP de PowerSync
  /// peut rester ouvert sans plus rien recevoir (le SDK n'a pas de délai de lecture), et l'app montre des données
  /// figées : une entrée de Claude « en cours » depuis 3 h, fermée depuis longtemps sur le serveur. Une reconnexion
  /// ne coûte qu'un point de contrôle, qui rafraîchit aussi `lastSyncedAt` quand rien n'a changé.
  static const staleAfter = Duration(minutes: 10);

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
    service._watch();
    return service;
  }

  /// Vérifie la sync chaque minute (le minuteur reprend au réveil du Mac), et au retour de l'app au premier plan.
  void _watch() {
    _watchdog = Timer.periodic(const Duration(minutes: 1), (_) => refreshIfStale());
    _lifecycle = AppLifecycleListener(onResume: () => refreshIfStale(after: const Duration(minutes: 2)));
  }

  /// Reconnecte la sync si elle se croit connectée sans avoir rien reçu depuis [after] ([shouldReconnect]).
  void refreshIfStale({Duration after = staleAfter}) {
    final connector = _connector;
    final now = DateTime.now();
    if (connector == null || !shouldReconnect(powersync.currentStatus, now, after: after, lastReconnect: _lastReconnect)) {
      return;
    }
    _lastReconnect = now;
    powersync.connect(connector: connector); // remplace la connexion en cours
  }

  /// Vrai si la sync se dit connectée mais n'a pas terminé de point de contrôle depuis [after]. Jamais pendant la
  /// première synchronisation ni pendant un téléchargement, ni deux fois dans la même minute. Hors ligne, le SDK
  /// réessaie déjà de lui-même.
  static bool shouldReconnect(SyncStatus status, DateTime now, {Duration after = staleAfter, DateTime? lastReconnect}) {
    final last = status.lastSyncedAt;
    if (!status.connected || status.downloading || last == null) return false;
    if (lastReconnect != null && now.difference(lastReconnect) < const Duration(minutes: 1)) return false;
    return now.difference(last) >= after;
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
    _watchdog?.cancel();
    _lifecycle?.dispose();
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
