import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import 'entry_dialog.dart';

/// Bandeau « Claude travaille » : chronomètres en cours des agents de l'utilisateur, une ligne par session
/// Claude Code (plans/10-suivi-claude-code.md, §8). Toucher une ligne ouvre l'entrée : projet, description,
/// « toujours rattacher ce dépôt ». Rien à afficher sans agent ou sans session en cours.
class AgentsWorkingBanner extends StatefulWidget {
  const AgentsWorkingBanner({super.key});

  @override
  State<AgentsWorkingBanner> createState() => _AgentsWorkingBannerState();
}

class _AgentsWorkingBannerState extends State<AgentsWorkingBanner> {
  // Flux gardé d'une reconstruction à l'autre, comme les chronomètres de la page des entrées.
  Stream<List<TimeEntry>>? _running;
  String? _runningKey;

  Stream<List<TimeEntry>> _runningOf(String workspaceId, List<String> agentIds) {
    final key = '$workspaceId:${agentIds.join(',')}';
    if (key != _runningKey || _running == null) {
      _runningKey = key;
      _running = entriesRepo.watchRunningOf(workspaceId, agentIds);
    }
    return _running!;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final theme = Theme.of(context);
    final agentIds = [for (final a in catalog.agentsOf(session.userId)) a.userId];
    if (agentIds.isEmpty || session.workspaceId == null) return const SizedBox.shrink();
    return StreamBuilder<List<TimeEntry>>(
      stream: _runningOf(session.workspaceId!, agentIds),
      builder: (context, snap) {
        final running = snap.data ?? const <TimeEntry>[];
        if (running.isEmpty) return const SizedBox.shrink();
        final onColor = theme.colorScheme.onSecondaryContainer;
        return Card(
          color: theme.colorScheme.secondaryContainer,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(Icons.smart_toy_outlined, size: 20, color: onColor),
                  const SizedBox(width: 8),
                  Text(l.agentsWorking, style: theme.textTheme.titleSmall?.copyWith(color: onColor)),
                  const SizedBox(width: 6),
                  Tooltip(message: l.agentsWorkingHelp, child: Icon(Icons.info_outline, size: 16, color: onColor)),
                ]),
              ),
              for (final e in running) _AgentSessionRow(key: ValueKey(e.id), entry: e),
            ]),
          ),
        );
      },
    );
  }
}

class _AgentSessionRow extends StatelessWidget {
  const _AgentSessionRow({super.key, required this.entry});
  final TimeEntry entry;

  Future<void> _edit(BuildContext context) async {
    final tagIds = await entriesRepo.tagIdsOf(entry.id);
    if (!context.mounted) return;
    await showEntryDialog(context, entry: entry, tagIds: tagIds);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 6, 12, 6),
        child: Row(children: [
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
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}
