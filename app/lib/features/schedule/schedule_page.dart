import 'package:drift/drift.dart' show Value;
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
import '../../core/widgets/pickers.dart';
import '../../core/widgets/teammates.dart' show memberName;
import '../../data/drift/database.dart';

/// Planning : affectations (projet × membre × jours), absences approuvées, jours fériés,
/// et charge prévue au regard de la capacité quotidienne de chaque membre.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime? _weekStart;
  int _weeks = 2;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final ws = session.workspace!;
    final start = _weekStart ??= startOfWeek(DateTime.now(), ws.weekStart);
    final days = [for (var i = 0; i < 7 * _weeks; i++) DateTime(start.year, start.month, start.day + i)];
    // Lecture comme les absences et les rapports : un chef d'équipe voit aussi ses collaborateurs (flux managed_team) ;
    // l'édition reste aux managers.
    final rights = TeamRights.of(context);
    final members = rights.seesTeam
        ? rights.visibleMembers.where((m) => m.status == 'active' && !catalog.isAgent(m.userId)).toList()
        : catalog.members.where((m) => m.userId == session.userId).toList();
    final locale = context.localeTag;

    return PageScaffold(
      title: l.schedule,
      maxWidth: 1600,
      actions: [
        IconButton(onPressed: () => setState(() => _weekStart = addDays(start, -7)), icon: const Icon(Icons.chevron_left)),
        TextButton(
          onPressed: () => setState(() => _weekStart = startOfWeek(DateTime.now(), ws.weekStart)),
          child: Text('${DateFormat.MMMd(locale).format(days.first)} – ${DateFormat.MMMd(locale).format(days.last)}'),
        ),
        IconButton(onPressed: () => setState(() => _weekStart = addDays(start, 7)), icon: const Icon(Icons.chevron_right)),
        DropdownButton<int>(
          value: _weeks,
          underline: const SizedBox.shrink(),
          items: [for (final w in const [1, 2, 4]) DropdownMenuItem(value: w, child: Text(l.weeksCount(w)))],
          onChanged: (v) => setState(() => _weeks = v!),
        ),
        if (session.isManager) ...[
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: () => showAssignmentDialog(context, initialDay: days.first), icon: const Icon(Icons.add), label: Text(l.newAssignment)),
        ],
      ],
      child: StreamBuilder<List<ScheduleAssignment>>(
        stream: modulesRepo.watchAssignments(ws.id, userId: rights.seesTeam ? null : session.userId, from: days.first, to: days.last),
        builder: (context, aSnap) => StreamBuilder<List<TimeOffRequest>>(
          stream: modulesRepo.watchRequests(ws.id, userId: rights.seesTeam ? null : session.userId),
          builder: (context, rSnap) => StreamBuilder<List<Holiday>>(
            stream: modulesRepo.watchHolidays(ws.id),
            builder: (context, hSnap) => StreamBuilder<List<TimeOffPolicy>>(
              stream: modulesRepo.watchPolicies(ws.id),
              builder: (context, pSnap) {
                final assignments = aSnap.data ?? const <ScheduleAssignment>[];
                final timeOff = (rSnap.data ?? const <TimeOffRequest>[]).where((r) => r.status == 'approved').toList();
                final holidays = {for (final h in hSnap.data ?? const <Holiday>[]) h.date: h.name};
                final policies = {for (final p in pSnap.data ?? const <TimeOffPolicy>[]) p.id: p};
                if (members.isEmpty) return EmptyState(icon: Icons.view_timeline_outlined, title: l.noMembers);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _header(context, days, holidays),
                        const Divider(height: 1),
                        for (final m in members) ...[
                          _MemberRow(
                            member: m,
                            days: days,
                            assignments: assignments.where((a) => a.userId == m.userId).toList(),
                            timeOff: timeOff.where((r) => r.userId == m.userId).toList(),
                            policies: policies,
                            holidays: holidays,
                          ),
                          const Divider(height: 1),
                        ],
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, List<DateTime> days, Map<String, String> holidays) {
    final theme = Theme.of(context);
    final locale = context.localeTag;
    return Row(children: [
      const SizedBox(width: _MemberRow.nameWidth),
      for (final d in days)
        Container(
          width: _MemberRow.dayWidth,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: d.weekday >= 6 || holidays.containsKey(dayKey(d)) ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6) : null,
          child: Column(children: [
            Text(DateFormat.E(locale).format(d), style: theme.textTheme.labelSmall),
            Text(DateFormat.d(locale).format(d),
                style: theme.textTheme.titleSmall?.copyWith(color: sameDay(d, DateTime.now()) ? theme.colorScheme.primary : null)),
            if (holidays.containsKey(dayKey(d)))
              Text(holidays[dayKey(d)]!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline), overflow: TextOverflow.ellipsis),
          ]),
        ),
    ]);
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.days,
    required this.assignments,
    required this.timeOff,
    required this.policies,
    required this.holidays,
  });

  static const nameWidth = 180.0;
  static const dayWidth = 92.0;

  final WorkspaceMember member;
  final List<DateTime> days;
  final List<ScheduleAssignment> assignments;
  final List<TimeOffRequest> timeOff;
  final Map<String, TimeOffPolicy> policies;
  final Map<String, String> holidays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final capacity = member.capacityHoursPerDay;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: nameWidth,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text('${capacity.toStringAsFixed(capacity % 1 == 0 ? 0 : 1)} h/${context.l10n.daysShort}', style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
        for (final d in days)
          () {
            final key = dayKey(d);
            final off = d.weekday >= 6 || holidays.containsKey(key);
            final dayAssign = assignments.where((a) => a.startDate.compareTo(key) <= 0 && a.endDate.compareTo(key) >= 0).toList();
            final dayOff = timeOff.where((r) => r.startDate.compareTo(key) <= 0 && r.endDate.compareTo(key) >= 0).toList();
            final planned = off ? 0.0 : dayAssign.fold<double>(0, (s, a) => s + a.hoursPerDay);
            final over = planned > capacity + 0.01;
            return InkWell(
              onTap: session.isManager && !off ? () => showAssignmentDialog(context, initialDay: d, userId: member.userId) : null,
              child: Container(
                width: dayWidth,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: off ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6) : null,
                  border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final r in dayOff)
                    _Chip(
                      color: policies[r.policyId]?.color ?? '#10B981',
                      text: policies[r.policyId]?.name ?? '',
                      striped: true,
                    ),
                  if (!off)
                    for (final a in dayAssign)
                      _Chip(
                        color: catalog.project(a.projectId)?.color ?? '#64748B',
                        text: '${catalog.project(a.projectId)?.name ?? context.l10n.noProject} · ${a.hoursPerDay.toStringAsFixed(a.hoursPerDay % 1 == 0 ? 0 : 1)}h',
                        onTap: session.isManager ? () => showAssignmentDialog(context, assignment: a) : null,
                      ),
                  if (planned > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${planned.toStringAsFixed(planned % 1 == 0 ? 0 : 1)}/${capacity.toStringAsFixed(capacity % 1 == 0 ? 0 : 1)}h',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(color: over ? theme.colorScheme.error : theme.colorScheme.outline, fontWeight: over ? FontWeight.bold : null),
                      ),
                    ),
                ]),
              ),
            );
          }(),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.text, this.onTap, this.striped = false});
  final String color;
  final String text;
  final VoidCallback? onTap;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: c.withValues(alpha: striped ? 0.12 : 0.22),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 3))),
            child: Text(text, style: Theme.of(context).textTheme.labelSmall, overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ),
      ),
    );
  }
}

Future<void> showAssignmentDialog(BuildContext context, {ScheduleAssignment? assignment, DateTime? initialDay, String? userId}) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final a = assignment;
  final active = catalog.humans.where((m) => m.status == 'active').toList();
  var user = a?.userId ?? userId ?? (active.isNotEmpty ? active.first.userId : session.userId!);
  // Affectation d'une personne désactivée depuis : elle reste dans la liste pour que le champ garde sa valeur.
  final choices = [...active, if (!active.any((m) => m.userId == user)) ?catalog.memberOf(user)];
  var projectId = a?.projectId;
  var range = DateTimeRange(
    start: a == null ? (initialDay ?? DateTime.now()) : parseDay(a.startDate),
    end: a == null ? (initialDay ?? DateTime.now()) : parseDay(a.endDate),
  );
  final hours = TextEditingController(text: (a?.hoursPerDay ?? catalog.memberOf(user)?.capacityHoursPerDay ?? 7).toString());
  final note = TextEditingController(text: a?.note ?? '');
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final fmt = DateFormat.yMMMEd(ctx.localeTag);
      return AlertDialog(
        title: Text(a == null ? l.newAssignment : l.editAssignment),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              initialValue: user,
              decoration: InputDecoration(labelText: l.member),
              items: [for (final m in choices) DropdownMenuItem(value: m.userId, child: Text(memberName(m)))],
              onChanged: (v) => setState(() => user = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final pick = await showProjectPicker(ctx, projectId: projectId);
                if (pick != null) setState(() => projectId = pick.projectId);
              },
              child: Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: ProjectLabel(projectId: projectId))),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(range.start == range.end ? fmt.format(range.start) : '${fmt.format(range.start)} → ${fmt.format(range.end)}'),
              onPressed: () async {
                final r = await showDateRangePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: range);
                if (r != null) setState(() => range = r);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.hoursPerDay)),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: InputDecoration(labelText: l.noteOptional)),
          ]),
        ),
        actions: [
          if (a != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              child: Text(l.delete),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(l.save)),
        ],
      );
    }),
  );
  if (res == 'delete' && a != null) return modulesRepo.deleteAssignment(a.id);
  if (res != 'save') return;
  final h = double.tryParse(hours.text.replaceAll(',', '.'));
  if (h == null || h <= 0 || h > 24) {
    if (context.mounted) showSnack(context, l.invalidHours);
    return;
  }
  final data = ScheduleAssignmentsCompanion(
    userId: Value(user),
    projectId: Value(projectId),
    startDate: Value(dayKey(range.start)),
    endDate: Value(dayKey(range.end)),
    hoursPerDay: Value(h),
    note: Value(note.text.trim().isEmpty ? null : note.text.trim()),
    createdBy: a == null ? Value(session.userId) : const Value.absent(),
  );
  await modulesRepo.saveAssignment(session.workspaceId!, data, id: a?.id);
}
