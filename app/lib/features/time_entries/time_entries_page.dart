import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/teammates.dart';
import '../../data/repositories/time_entry_repository.dart';
import 'entry_dialog.dart';

/// Page d'accueil : entrées terminées de l'utilisateur, groupées par jour.
class TimeEntriesPage extends StatefulWidget {
  const TimeEntriesPage({super.key});

  @override
  State<TimeEntriesPage> createState() => _TimeEntriesPageState();
}

class _TimeEntriesPageState extends State<TimeEntriesPage> {
  int _weeks = 2;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final ws = session.workspace!;
    final weekStart = startOfWeek(DateTime.now(), ws.weekStart);
    final from = weekStart.subtract(Duration(days: 7 * (_weeks - 1)));
    final to = DateTime.now().add(const Duration(days: 2));

    return StreamBuilder<List<EntryRow>>(
      stream: entriesRepo.watchEntries(workspaceId: ws.id, userId: session.userId, from: from, to: to),
      builder: (context, snap) {
        final rows = snap.data ?? const <EntryRow>[];
        if (snap.connectionState == ConnectionState.waiting && rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return EmptyState(
            icon: Icons.timer_outlined,
            title: l.noEntriesYet,
            message: l.noEntriesYetMessage,
            action: FilledButton.tonal(onPressed: () => showEntryDialog(context), child: Text(l.addManualEntry)),
          );
        }

        // Regroupement par semaine puis par jour (heure locale).
        final byDay = <DateTime, List<EntryRow>>{};
        for (final r in rows) {
          byDay.putIfAbsent(startOfDay(r.entry.startAt.toLocal()), () => []).add(r);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
        final weekTotals = <DateTime, int>{};
        for (final d in days) {
          final w = startOfWeek(d, ws.weekStart);
          weekTotals[w] = (weekTotals[w] ?? 0) + byDay[d]!.fold<int>(0, (s, r) => s + r.seconds);
        }

        final children = <Widget>[];
        DateTime? currentWeek;
        for (final d in days) {
          final w = startOfWeek(d, ws.weekStart);
          if (w != currentWeek) {
            currentWeek = w;
            children.add(_WeekHeader(weekStart: w, total: weekTotals[w] ?? 0));
          }
          children.add(_DayCard(day: d, rows: byDay[d]!));
        }
        children.add(Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: OutlinedButton(onPressed: () => setState(() => _weeks += 4), child: Text(l.loadMore)),
          ),
        ));

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: children),
          ),
        );
      },
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.weekStart, required this.total});
  final DateTime weekStart;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final thisWeek = startOfWeek(DateTime.now(), context.read<SessionController>().workspace!.weekStart);
    final label = weekStart == thisWeek
        ? l.thisWeek
        : weekStart == thisWeek.subtract(const Duration(days: 7))
            ? l.lastWeek
            : l.weekOf(MaterialLocalizations.of(context).formatShortDate(weekStart));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(children: [
        Text(label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
        const Spacer(),
        Text('${l.weekTotal}: ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        Text(formatClock(total), style: theme.textTheme.titleSmall),
      ]),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.rows});
  final DateTime day;
  final List<EntryRow> rows;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final total = rows.fold<int>(0, (s, r) => s + r.seconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Text(dayLabel(context, day, today: l.today, yesterday: l.yesterday), style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('${l.total}: ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              Text(formatClock(total), style: theme.textTheme.titleSmall),
            ]),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            EntryTile(row: rows[i]),
          ],
        ]),
      ),
    );
  }
}

/// Ligne d'entrée de temps (réutilisée par les rapports détaillés).
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.row, this.showUser = false});
  final EntryRow row;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final e = row.entry;
    final session = context.read<SessionController>();
    final catalog = context.watch<CatalogController>();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final times = '${timeLabel(context, e.startAt)} – ${e.endAt == null ? '…' : timeLabel(context, e.endAt!)}';
    final isMine = e.userId == session.userId;
    final canEdit = TeamRights.of(context).canEditTimeOf(e.userId);
    final author = e.createdBy;

    final description = Text(
      e.description.isEmpty ? l.noDescription : e.description,
      style: e.description.isEmpty ? TextStyle(color: theme.colorScheme.outline) : null,
      overflow: TextOverflow.ellipsis,
    );

    final meta = Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (showUser) Text(catalog.memberOf(e.userId)?.displayName ?? '?', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ProjectLabel(projectId: e.projectId, taskId: e.taskId, dense: true),
      TagChips(row.tagIds),
      if (author != null && author != e.userId)
        Text(l.enteredBy(memberName(catalog.memberOf(author))),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontStyle: FontStyle.italic)),
    ]);

    final trailing = Row(mainAxisSize: MainAxisSize.min, children: [
      if (e.locked) Icon(Icons.lock, size: 16, color: theme.colorScheme.outline),
      Icon(Icons.attach_money, size: 18, color: e.billable ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      if (wide) ...[
        const SizedBox(width: 12),
        Text(times, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(width: 12),
      SizedBox(
        width: 72,
        child: Text(formatClock(row.seconds), textAlign: TextAlign.right, style: theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      if (isMine)
        IconButton(
          tooltip: l.continueEntry,
          icon: const Icon(Icons.play_arrow),
          onPressed: () => entriesRepo.start(
            workspaceId: e.workspaceId,
            userId: e.userId,
            draft: EntryDraft(
              description: e.description,
              projectId: e.projectId,
              taskId: e.taskId,
              billable: e.billable,
              hourlyRateCents: e.hourlyRateCents,
              tagIds: row.tagIds,
            ),
          ),
        ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'edit':
              await showEntryDialog(context, entry: e, tagIds: row.tagIds);
            case 'duplicate':
              await entriesRepo.createManual(
                workspaceId: e.workspaceId,
                userId: e.userId,
                start: e.startAt,
                end: e.endAt ?? DateTime.now(),
                createdBy: session.userId,
                draft: EntryDraft(
                  description: e.description,
                  projectId: e.projectId,
                  taskId: e.taskId,
                  billable: e.billable,
                  hourlyRateCents: e.hourlyRateCents,
                  tagIds: row.tagIds,
                ),
              );
            case 'delete':
              if (await confirm(context, title: l.deleteEntry, message: l.deleteEntryMessage)) {
                await entriesRepo.delete(e.id);
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(canEdit ? l.edit : l.view)),
          if (canEdit) ...[
            PopupMenuItem(value: 'duplicate', child: Text(l.duplicate)),
            PopupMenuItem(value: 'delete', child: Text(l.delete)),
          ],
        ],
      ),
    ]);

    return InkWell(
      onTap: () => showEntryDialog(context, entry: e, tagIds: row.tagIds),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              description,
              const SizedBox(height: 4),
              meta,
              if (!wide) ...[const SizedBox(height: 2), Text(times, style: theme.textTheme.bodySmall)],
            ]),
          ),
          trailing,
        ]),
      ),
    );
  }
}
