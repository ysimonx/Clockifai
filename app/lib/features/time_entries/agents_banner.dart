import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../timer/timer_control.dart' show showPanel;
import 'entry_dialog.dart';

/// Bandeau « Claude travaille » : chronomètres en cours des agents de l'utilisateur, une ligne par session
/// Claude Code (plans/10-suivi-claude-code.md, §8). Toucher une ligne ouvre l'entrée : projet, description,
/// « toujours rattacher ce dépôt ». Rien à afficher sans agent ou sans session en cours.
class AgentsWorkingBanner extends StatefulWidget {
  const AgentsWorkingBanner({super.key});

  @override
  State<AgentsWorkingBanner> createState() => _AgentsWorkingBannerState();
}

/// Sessions en cours des agents de l'utilisateur connecté, les plus anciennes d'abord ; null sans agent.
mixin _AgentSessions<T extends StatefulWidget> on State<T> {
  // Flux gardé d'une reconstruction à l'autre, comme les chronomètres de la page des entrées.
  Stream<List<TimeEntry>>? _running;
  String? _runningKey;

  Stream<List<TimeEntry>>? runningSessions(BuildContext context) {
    final session = context.watch<SessionController>();
    final agentIds = [for (final a in context.watch<CatalogController>().agentsOf(session.userId)) a.userId];
    final workspaceId = session.workspaceId;
    if (agentIds.isEmpty || workspaceId == null) return null;
    final key = '$workspaceId:${agentIds.join(',')}';
    if (key != _runningKey || _running == null) {
      _runningKey = key;
      _running = entriesRepo.watchRunningOf(workspaceId, agentIds);
    }
    return _running!;
  }
}

class _AgentsWorkingBannerState extends State<AgentsWorkingBanner> with _AgentSessions {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final stream = runningSessions(context);
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<TimeEntry>>(
      stream: stream,
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

/// Pastille « Claude » de la barre du haut, à côté du chronomètre : les sessions en cours de l'agent, visibles de
/// toutes les pages. La plus récente, sa durée et « + 1 autre » ; un clic les liste. Rien sans session en cours.
class AgentsWorkingChip extends StatefulWidget {
  const AgentsWorkingChip({super.key, this.compact = false});

  /// Téléphone : l'icône seule, le détail au toucher.
  final bool compact;

  @override
  State<AgentsWorkingChip> createState() => _AgentsWorkingChipState();
}

class _AgentsWorkingChipState extends State<AgentsWorkingChip> with _AgentSessions {
  @override
  Widget build(BuildContext context) {
    final stream = runningSessions(context);
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<TimeEntry>>(
      stream: stream,
      builder: (context, snap) {
        final running = snap.data ?? const <TimeEntry>[];
        if (running.isEmpty) return const SizedBox.shrink();
        return _chip(context, running, stream);
      },
    );
  }

  Widget _chip(BuildContext context, List<TimeEntry> running, Stream<List<TimeEntry>> stream) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final latest = running.last;
    final project = context.watch<CatalogController>().project(latest.projectId);
    final title = latest.description.isEmpty ? (project?.name ?? l.noDescription) : latest.description;
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: monoFont, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    void open() => showPanel<void>(context, title: l.agentsWorking, builder: (ctx) => _SessionsPanel(stream: stream, initial: running));
    if (widget.compact) {
      return IconButton(
        tooltip: l.agentsWorking,
        onPressed: open,
        icon: Badge(isLabelVisible: running.length > 1, label: Text('${running.length}'), child: const Icon(Icons.smart_toy_outlined)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: l.agentsWorking,
        child: Material(
          color: theme.colorScheme.secondaryContainer,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy_outlined, size: 18, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(title, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                ),
                if (running.length > 1) ...[
                  const SizedBox(width: 8),
                  Text(l.otherRunningTimers(running.length - 1), style: theme.textTheme.bodySmall),
                ],
                const SizedBox(width: 10),
                ElapsedText(latest.startAt, style: mono),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Les sessions en cours, dans le panneau de la pastille ; il se ferme quand la dernière se termine.
class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({required this.stream, required this.initial});
  final Stream<List<TimeEntry>> stream;
  final List<TimeEntry> initial;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<List<TimeEntry>>(
      stream: stream,
      initialData: initial,
      builder: (context, snap) {
        final rows = snap.data ?? const <TimeEntry>[];
        if (rows.isEmpty && snap.connectionState == ConnectionState.active) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final route = context.mounted ? ModalRoute.of(context) : null;
            if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
          });
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.agentsWorkingHelp, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final e in rows.reversed) _AgentSessionRow(key: ValueKey(e.id), entry: e, inset: 0),
        ]);
      },
    );
  }
}

class _AgentSessionRow extends StatelessWidget {
  const _AgentSessionRow({super.key, required this.entry, this.inset = 40});
  final TimeEntry entry;

  /// Retrait à gauche : sous le titre du bandeau, rien dans le panneau.
  final double inset;

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
        padding: EdgeInsets.fromLTRB(inset, 6, inset == 0 ? 0 : 12, 6),
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
