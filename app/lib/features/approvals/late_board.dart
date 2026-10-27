import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../timesheet/week_tools.dart' show plannedMinutes;
import '../today/day_plan.dart' show addDays;

/// Équipe (plans/13-ux-moderne.md, lot 8) : qui n'a pas soumis sa semaine dernière, son temps face au planning, et
/// « Relancer » (une relance par personne et par semaine, affichée dans son app).
class LateBoard extends StatelessWidget {
  const LateBoard({super.key, this.clock = DateTime.now});
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final rights = TeamRights.of(context);
    final ws = session.workspace!;
    final week = addDays(startOfWeek(clock(), ws.weekStart), -7);
    final weekEnd = addDays(week, 7);
    final people = [
      for (final m in rights.visibleMembers)
        if (!catalog.isAgent(m.userId) && m.userId != session.userId && rights.canApproveTimesheetOf(m.userId)) m,
    ];
    if (people.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<TimesheetSubmission>>(
      stream: modulesRepo.watchSubmissions(ws.id),
      builder: (context, subSnap) => StreamBuilder<List<EntryRow>>(
        stream: entriesRepo.watchEntries(workspaceId: ws.id, from: week, to: weekEnd),
        builder: (context, entrySnap) => StreamBuilder<List<ScheduleAssignment>>(
          stream: modulesRepo.watchAssignments(ws.id, from: week, to: addDays(weekEnd, -1)),
          builder: (context, planSnap) => StreamBuilder<List<Reminder>>(
            stream: modulesRepo.watchReminders(ws.id),
            builder: (context, remSnap) {
              final key = dayKey(week);
              final lines = <({WorkspaceMember m, int logged, int planned, String? status, bool reminded})>[];
              for (final m in people) {
                final status = (subSnap.data ?? const <TimesheetSubmission>[])
                    .where((s) => s.userId == m.userId && s.periodStart == key)
                    .firstOrNull
                    ?.status;
                if (status == 'submitted' || status == 'approved') continue;
                final logged = (entrySnap.data ?? const <EntryRow>[])
                    .where((r) => r.entry.userId == m.userId)
                    .fold(0, (s, r) => s + r.seconds);
                final mine = [for (final a in planSnap.data ?? const <ScheduleAssignment>[]) if (a.userId == m.userId) a];
                final planned = [
                  for (var i = 0; i < 7; i++)
                    for (final p in {for (final a in mine) a.projectId}) plannedMinutes(mine, p, addDays(week, i)),
                ].fold(0, (s, v) => s + v);
                final reminded = (remSnap.data ?? const <Reminder>[]).any((r) => r.userId == m.userId && r.periodStart == key);
                lines.add((m: m, logged: logged, planned: planned, status: status, reminded: reminded));
              }
              lines.sort((a, b) => a.logged.compareTo(b.logged));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.lateTitle, style: theme.textTheme.titleMedium),
                    Text(l.lateHelp(DateFormat.MMMd(context.localeTag).format(week)),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    if (lines.isEmpty)
                      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(l.lateAllGood))
                    else
                      for (final line in lines)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text(memberName(line.m).isEmpty ? '?' : memberName(line.m)[0].toUpperCase())),
                          title: Text(memberName(line.m)),
                          subtitle: Text([
                            line.planned > 0
                                ? l.lateLine(formatHm(line.logged), formatHm(line.planned * 60))
                                : l.lateLineNoPlan(formatHm(line.logged)),
                            switch (line.status) { 'rejected' => l.statusRejected, 'withdrawn' => l.statusWithdrawn, _ => l.lateNotSubmitted },
                          ].join(' · ')),
                          trailing: line.reminded
                              ? Chip(avatar: const Icon(Icons.check, size: 16), label: Text(l.reminded))
                              : OutlinedButton.icon(
                                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                                  label: Text(l.remind),
                                  onPressed: () async {
                                    await modulesRepo.remind(workspaceId: ws.id, userId: line.m.userId, periodStart: week, by: session.userId);
                                    if (context.mounted) showSnack(context, l.remindedSnack(memberName(line.m)));
                                  },
                                ),
                        ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
