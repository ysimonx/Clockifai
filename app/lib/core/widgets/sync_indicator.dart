import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:powersync/powersync.dart' show SyncStatus;
import 'package:provider/provider.dart';

import '../di.dart';
import '../l10n.dart';
import '../session.dart';

/// Icône d'état de la synchronisation (connecté, en cours, hors ligne) + détail au clic.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = context.select<SessionController, SyncStatus?>((s) => s.syncStatus);
    final connected = status?.connected ?? false;
    final busy = (status?.uploading ?? false) || (status?.downloading ?? false);
    final (icon, color, label) = !connected
        ? (Icons.cloud_off, Theme.of(context).colorScheme.error, l.offline)
        : busy
            ? (Icons.cloud_sync, Theme.of(context).colorScheme.primary, l.syncing)
            : (Icons.cloud_done, Colors.green, l.synced);
    return IconButton(
      tooltip: label,
      icon: Icon(icon, color: color),
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
    return AlertDialog(
      title: Text(l.syncStatus),
      content: FutureBuilder(
        future: syncService.powersync.getUploadQueueStats(),
        builder: (context, snap) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(l.connection, (status?.connected ?? false) ? l.online : l.offline),
          _row(l.lastSync, last == null ? '—' : DateFormat.yMd(context.localeTag).add_Hms().format(last.toLocal())),
          _row(l.pendingChanges, snap.data?.count.toString() ?? '…'),
          if (status?.anyError != null) ...[
            const SizedBox(height: 8),
            Text('${status!.anyError}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
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
