import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/time_entries_page.dart';
import '../timesheet/week_tools.dart' show plannedMinutes;
import '../today/day_plan.dart' show addDays;
import 'late_board.dart';
import 'submission_bar.dart';

/// Validation des feuilles de temps soumises : managers (tout le workspace), chefs d'équipe (leur périmètre).
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final rights = TeamRights.of(context);
    if (!rights.seesTeam) return EmptyState(icon: Icons.lock_outline, title: l.managersOnly);
    return PageScaffold(
      title: l.approvals,
      actions: [
        SegmentedButton<bool>(
          segments: [ButtonSegment(value: false, label: Text(l.pending)), ButtonSegment(value: true, label: Text(l.history))],
          selected: {_history},
          onSelectionChanged: (s) => setState(() => _history = s.first),
        ),
      ],
      child: StreamBuilder<List<TimesheetSubmission>>(
        stream: modulesRepo.watchSubmissions(session.workspaceId!, status: _history ? null : 'submitted'),
        builder: (context, snap) {
          final subs = (snap.data ?? const <TimesheetSubmission>[])
              .where((s) => rights.canApproveTimesheetOf(s.userId))
              .where((s) => _history ? s.status != 'submitted' : true)
              .toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            // Qui n'a pas soumis sa semaine dernière, et « Relancer » (plan 13, lot 8).
            if (!_history) ...[const LateBoard(), const SizedBox(height: 12)],
            if (subs.isEmpty)
              EmptyState(icon: Icons.task_alt, title: _history ? l.noHistory : l.nothingToApprove)
            else
              for (final s in subs) Padding(padding: const EdgeInsets.only(bottom: 8), child: _SubmissionCard(sub: s)),
          ]);
        },
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.sub});
  final TimesheetSubmission sub;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final member = catalog.memberOf(sub.userId);
    final fmt = DateFormat.MMMd(context.localeTag);
    final start = parseDay(sub.periodStart), end = parseDay(sub.periodEnd);
    final statusColor = switch (sub.status) {
      'approved' => AppColors.of(context).success,
      'rejected' => theme.colorScheme.error,
      'withdrawn' => theme.colorScheme.outline,
      _ => theme.colorScheme.tertiary,
    };
    final statusLabel = switch (sub.status) {
      'approved' => l.statusApproved,
      'rejected' => l.statusRejected,
      'withdrawn' => l.statusWithdrawn,
      _ => l.statusSubmitted,
    };
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(child: Text((member?.displayName.isNotEmpty ?? false) ? member!.displayName[0].toUpperCase() : '?')),
        title: Text(member?.displayName ?? sub.userId.substring(0, 8)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmt.format(start)} – ${fmt.format(end)} · ${formatHm(sub.totalSeconds ?? 0)}'),
          // Écart au planning de la période (plan 13, lot 8).
          StreamBuilder<List<ScheduleAssignment>>(
            stream: modulesRepo.watchAssignments(sub.workspaceId, userId: sub.userId, from: start, to: end),
            builder: (context, snap) {
              final plan = snap.data ?? const <ScheduleAssignment>[];
              final days = end.difference(start).inDays + 1;
              final planned = [
                for (var i = 0; i < days; i++)
                  for (final p in {for (final a in plan) a.projectId}) plannedMinutes(plan, p, addDays(start, i)),
              ].fold(0, (s, v) => s + v);
              if (planned == 0) return const SizedBox.shrink();
              final delta = (sub.totalSeconds ?? 0) - planned * 60;
              return Text(l.plannedVsSubmitted(formatHm(planned * 60), '${delta < 0 ? '−' : '+'}${formatHm(delta.abs())}'),
                  style: theme.textTheme.bodySmall?.copyWith(color: delta < 0 ? theme.colorScheme.error : null));
            },
          ),
          Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
          if (sub.note?.isNotEmpty ?? false) Text('« ${sub.note} »', style: theme.textTheme.bodySmall),
          if (sub.decisionNote?.isNotEmpty ?? false) Text('${l.decision} : ${sub.decisionNote}', style: theme.textTheme.bodySmall),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sub.status == 'submitted') ...[
            IconButton(
              tooltip: l.reject,
              icon: Icon(Icons.close, color: theme.colorScheme.error),
              onPressed: () async {
                final note = await askDecisionNote(context, l.reject);
                if (note != null) await modulesRepo.decideSubmission(sub.id, approve: false, note: note.isEmpty ? null : note);
              },
            ),
            FilledButton(onPressed: () => modulesRepo.decideSubmission(sub.id, approve: true), child: Text(l.approve)),
          ],
          if (sub.status == 'approved')
            TextButton(
              onPressed: () async {
                final note = await askDecisionNote(context, l.reopen);
                if (note != null) await modulesRepo.decideSubmission(sub.id, approve: false, note: note.isEmpty ? null : note);
              },
              child: Text(l.reopen),
            ),
        ]),
        children: [
          StreamBuilder<List<EntryRow>>(
            stream: entriesRepo.watchEntries(
              workspaceId: sub.workspaceId,
              userId: sub.userId,
              from: start,
              to: end.add(const Duration(days: 1)),
            ),
            builder: (context, snap) {
              final rows = snap.data ?? const <EntryRow>[];
              if (rows.isEmpty) return ListTile(title: Text(l.noEntriesInPeriod));
              return Column(children: [for (final r in rows) EntryTile(row: r)]);
            },
          ),
        ],
      ),
    );
  }
}
