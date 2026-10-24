import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../timer/timer_rules.dart';
import 'agents_banner.dart';
import 'entry_dialog.dart';
import 'entry_group_dialog.dart';
import 'entry_groups.dart';

/// Page d'accueil : entrées terminées de l'utilisateur, groupées par jour.
class TimeEntriesPage extends StatefulWidget {
  const TimeEntriesPage({super.key});

  @override
  State<TimeEntriesPage> createState() => _TimeEntriesPageState();
}

class _TimeEntriesPageState extends State<TimeEntriesPage> {
  int _weeks = 2;
  // Chronomètres en cours (▶ devient ■) : flux gardé d'une reconstruction à l'autre, sans clignotement.
  Stream<List<TimeEntry>>? _running;
  String? _runningKey;

  Stream<List<TimeEntry>> _runningOf(String workspaceId, String? userId) {
    final key = '$workspaceId:$userId';
    if (key != _runningKey || _running == null) {
      _runningKey = key;
      _running = userId == null ? Stream.value(const []) : entriesRepo.watchRunningAll(workspaceId, userId);
    }
    return _running!;
  }

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
          return Column(children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 0), child: AgentsWorkingBanner()),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.timer_outlined,
                title: l.noEntriesYet,
                message: l.noEntriesYetMessage,
                action: FilledButton.tonal(onPressed: () => showEntryDialog(context), child: Text(l.addManualEntry)),
              ),
            ),
          ]);
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

        return StreamBuilder<List<TimeEntry>>(
          stream: _runningOf(ws.id, session.userId),
          initialData: const [],
          builder: (context, runningSnap) {
            final running = runningSnap.data ?? const <TimeEntry>[];
            final children = <Widget>[const AgentsWorkingBanner()];
            DateTime? currentWeek;
            for (final d in days) {
              final w = startOfWeek(d, ws.weekStart);
              if (w != currentWeek) {
                currentWeek = w;
                children.add(_WeekHeader(weekStart: w, total: weekTotals[w] ?? 0));
              }
              children.add(_DayCard(day: d, rows: byDay[d]!, running: running));
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
  const _DayCard({required this.day, required this.rows, required this.running});
  final DateTime day;
  final List<EntryRow> rows;
  final List<TimeEntry> running;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final total = rows.fold<int>(0, (s, r) => s + r.seconds);
    final lines = context.watch<DisplayPrefs>().groupSimilarEntries
        ? [
            for (final g in groupSimilar(rows))
              g.isSingle
                  ? EntryTile(row: g.first, running: running)
                  : EntryGroupTile(key: ValueKey('$day ${g.key}'), group: g, day: day, running: running),
          ]
        : [for (final r in rows) EntryTile(row: r, running: running)];
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
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            lines[i],
          ],
        ]),
      ),
    );
  }
}

/// Ligne d'entrée de temps (réutilisée par les rapports détaillés).
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.row, this.showUser = false, this.running = const [], this.showContinue = true});
  final EntryRow row;
  final bool showUser;

  /// Chronomètres en cours de l'utilisateur : si l'un vise la même tâche, ▶ devient ■.
  final List<TimeEntry> running;

  /// Faux pour une entrée dépliée d'un groupe : on relance depuis la ligne du groupe.
  final bool showContinue;

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
    final rights = TeamRights.of(context);
    final canEdit = rights.canEditTimeOf(e.userId);
    final canDuplicate = rights.canCreateTimeFor(e.userId);
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
      if (author != null && author != e.userId && e.source != 'agent')
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
      if (isMine && showContinue) _ContinueButton(row: row, running: running),
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
          if (canDuplicate) PopupMenuItem(value: 'duplicate', child: Text(l.duplicate)),
          if (canEdit) PopupMenuItem(value: 'delete', child: Text(l.delete)),
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

/// ▶ « Continuer » ; ■ « Arrêter » si un chronomètre tourne déjà sur la même tâche ([sameTimerTarget]).
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.row, required this.running});
  final EntryRow row;
  final List<TimeEntry> running;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final e = row.entry;
    final current = running
        .where((r) => sameTimerTarget(r, description: e.description, projectId: e.projectId, taskId: e.taskId))
        .firstOrNull;
    if (current != null) {
      return IconButton(
        tooltip: l.stop,
        icon: Icon(Icons.stop_circle, color: Theme.of(context).colorScheme.error),
        onPressed: () => stopTimer(context, current),
      );
    }
    return IconButton(tooltip: l.continueEntry, icon: const Icon(Icons.play_arrow), onPressed: () => _continue(context, row));
  }
}

/// Relance l'activité d'une entrée, sauf si sa tâche a déjà un chronomètre en cours.
/// Vérifie la base locale : la liste [EntryTile.running] n'est pas fournie partout (rapports, approbations).
Future<void> _continue(BuildContext context, EntryRow row) async {
  final session = context.read<SessionController>();
  final l = context.l10n;
  final e = row.entry;
  final running = await entriesRepo.watchRunningAll(e.workspaceId, e.userId).first;
  if (!context.mounted) return;
  final blocked = alreadyRunningViolation(l, running, description: e.description, projectId: e.projectId, taskId: e.taskId);
  if (blocked != null) return showSnack(context, blocked);
  await entriesRepo.start(
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
    maxRunning: session.runningTimersLimit,
  );
}

/// Groupe d'entrées similaires d'une journée (plans/08-regroupement-entrees.md) : une ligne résumée
/// (nombre, plage, durée cumulée) qui se déplie sur ses entrées.
class EntryGroupTile extends StatefulWidget {
  const EntryGroupTile({super.key, required this.group, required this.day, this.running = const []});
  final EntryGroup group;
  final DateTime day;
  final List<TimeEntry> running;

  @override
  State<EntryGroupTile> createState() => _EntryGroupTileState();
}

class _EntryGroupTileState extends State<EntryGroupTile> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final g = widget.group;
    final e = g.first.entry;
    final count = g.rows.length;
    final session = context.read<SessionController>();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final end = g.endAt;
    final times = '${timeLabel(context, g.startAt)} – ${end == null ? '…' : timeLabel(context, end)}';
    final isMine = e.userId == session.userId;
    // Mêmes règles que le dialogue d'entrée : le serveur refuserait la modification d'une entrée verrouillée.
    final lockDate = DateTime.tryParse(session.workspace?.lockEntriesBefore ?? '');
    final inLockedPeriod = lockDate != null && widget.day.isBefore(lockDate) && !session.isAdmin;
    final locked = (g.anyLocked && !session.isAdmin) || inLockedPeriod;
    final canEdit = !locked && TeamRights.of(context).canEditTimeOf(e.userId);

    final badge = Tooltip(
      message: _expanded ? l.hideSimilarEntries : l.showSimilarEntries(count),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: _expanded ? theme.colorScheme.primary : null,
            border: Border.all(color: _expanded ? theme.colorScheme.primary : theme.colorScheme.outline),
          ),
          child: Text('$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: _expanded ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      ),
    );

    final summary = InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          badge,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                e.description.isEmpty ? l.noDescription : e.description,
                style: e.description.isEmpty ? TextStyle(color: theme.colorScheme.outline) : null,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ProjectLabel(projectId: e.projectId, taskId: e.taskId, dense: true),
                TagChips(g.first.tagIds),
              ]),
              if (!wide) ...[const SizedBox(height: 2), Text(times, style: theme.textTheme.bodySmall)],
            ]),
          ),
          if (locked) Tooltip(message: l.similarEntriesLocked, child: Icon(Icons.lock, size: 16, color: theme.colorScheme.outline)),
          Icon(Icons.attach_money, size: 18, color: e.billable ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
          if (wide) ...[
            const SizedBox(width: 12),
            Text(times, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(formatClock(g.seconds),
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (isMine) _ContinueButton(row: g.first, running: widget.running),
          PopupMenuButton<String>(
            enabled: canEdit,
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await showEntryGroupDialog(context, g);
                case 'delete':
                  if (await confirm(context, title: l.deleteSimilarEntries(count), message: l.deleteSimilarEntriesMessage(count))) {
                    await entriesRepo.deleteMany([for (final r in g.rows) r.entry.id]);
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(l.editSimilarEntries(count))),
              PopupMenuItem(value: 'delete', child: Text(l.deleteSimilarEntries(count))),
            ],
          ),
        ]),
      ),
    );

    if (!_expanded) return summary;
    return Column(children: [
      summary,
      for (final r in g.rows) ...[
        const Divider(height: 1, indent: 52),
        Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          padding: const EdgeInsets.only(left: 36),
          child: EntryTile(row: r, showContinue: false),
        ),
      ],
    ]);
  }
}
