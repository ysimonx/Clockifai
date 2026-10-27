import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:powersync/powersync.dart' show SyncStatus;
import 'package:provider/provider.dart';

import '../../data/powersync/sync_service.dart';
import '../di.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';

/// Erreur de réseau (pas de connexion, serveur injoignable) : rien à corriger pour l'utilisateur,
/// c'est l'état « hors ligne », et les saisies partiront au retour du réseau.
bool _isNetworkError(Object? e) {
  if (e == null) return false;
  if (e is TimeoutException) return true;
  final s = e.toString();
  return s.contains('ClientException') || s.contains('SocketException') || s.contains('Failed to fetch') || s.contains('XMLHttpRequest');
}

/// Hors ligne : flux de sync coupé, ou envoi impossible faute de réseau (le flux peut survivre un moment).
bool _isOffline(SyncStatus? status) => !(status?.connected ?? false) || _isNetworkError(status?.anyError);

/// Icône d'état de la synchronisation (connecté, en cours, hors ligne) + détail au clic. Un badge compte les
/// modifications qui attendent de partir (plans/13-ux-moderne.md, lot 9 : « hors ligne, rien n'est perdu »).
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  Timer? _poll;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    if (!getIt.isRegistered<SyncService>()) return;
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final n = (await syncService.powersync.getUploadQueueStats()).count;
      if (mounted && n != _pending) setState(() => _pending = n);
    } catch (_) {
      // base fermée (déconnexion) : le badge attend la prochaine lecture
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = context.select<SessionController, SyncStatus?>((s) => s.syncStatus);
    final busy = (status?.uploading ?? false) || (status?.downloading ?? false);
    final (icon, color, label) = _isOffline(status)
        ? (Icons.cloud_off, Theme.of(context).colorScheme.error, l.offline)
        : busy
            ? (Icons.cloud_sync, Theme.of(context).colorScheme.primary, l.syncing)
            : (Icons.cloud_done, AppColors.of(context).success, l.synced);
    return IconButton(
      tooltip: _pending > 0 ? '$label · ${l.pendingCount(_pending)}' : label,
      icon: Badge(
        isLabelVisible: _pending > 0,
        label: Text('$_pending'),
        child: Icon(icon, color: color),
      ),
      onPressed: () => showDialog<void>(context: context, builder: (_) => const _SyncDetails()),
    );
  }
}

class _SyncDetails extends StatelessWidget {
  const _SyncDetails();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final status = session.syncStatus;
    final last = status?.lastSyncedAt;
    final error = status?.anyError;
    return AlertDialog(
      title: Text(l.syncStatus),
      content: FutureBuilder(
        future: syncService.powersync.getUploadQueueStats(),
        builder: (context, snap) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(l.connection, _isOffline(status) ? l.offline : l.online),
          _row(l.lastSync, last == null ? '—' : DateFormat.yMd(context.localeTag).add_Hms().format(last.toLocal())),
          _row(l.pendingChanges, snap.data?.count.toString() ?? '…'),
          if (error != null && !_isNetworkError(error)) ...[
            const SizedBox(height: 8),
            Text('$error', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Text(l.offlineExplanation, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close))],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
