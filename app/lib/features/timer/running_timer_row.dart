import 'package:flutter/material.dart';

import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../time_entries/entry_dialog.dart';
import 'timer_rules.dart';

/// Ligne compacte d'un chronomètre en cours, sous la barre, quand le workspace
/// autorise plusieurs chronomètres simultanés (`max_running_timers` ≠ 1).
class RunningTimerRow extends StatelessWidget {
  const RunningTimerRow({super.key, required this.entry});
  final TimeEntry entry;

  Future<void> _edit(BuildContext context) async {
    final tagIds = await entriesRepo.tagIdsOf(entry.id);
    if (!context.mounted) return;
    await showEntryDialog(context, entry: entry, tagIds: tagIds);
  }

  Future<void> _discard(BuildContext context) async {
    final l = context.l10n;
    if (await confirm(context, title: l.discardTimer, message: l.discardTimerMessage)) {
      await entriesRepo.delete(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(children: [
          Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(
                  entry.description.isEmpty ? l.noDescription : entry.description,
                  style: entry.description.isEmpty ? TextStyle(color: theme.colorScheme.outline) : null,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(child: ProjectLabel(projectId: entry.projectId, taskId: entry.taskId, dense: true)),
            ]),
          ),
          const SizedBox(width: 8),
          ElapsedText(entry.startAt,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
          IconButton(
            tooltip: l.stop,
            onPressed: () => stopTimer(context, entry),
            icon: Icon(Icons.stop_circle, color: theme.colorScheme.error),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _edit(context);
                case 'discard':
                  _discard(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(l.editTimer)),
              PopupMenuItem(value: 'discard', child: Text(l.discardTimer)),
            ],
          ),
        ]),
      ),
    );
  }
}
