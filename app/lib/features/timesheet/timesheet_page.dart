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
import '../../core/widgets/teammates.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../approvals/submission_bar.dart';

/// Feuille de temps hebdomadaire : projets × jours, cellules éditables.
/// Un chef d'équipe ou un manager choisit la personne affichée (bandeau « Collaborateur »).
class TimesheetPage extends StatefulWidget {
  const TimesheetPage({super.key});

  @override
  State<TimesheetPage> createState() => _TimesheetPageState();
}

/// Clé de ligne : projet (null = sans projet).
class _RowKey {
  const _RowKey(this.projectId);
  final String? projectId;
  @override
  bool operator ==(Object other) => other is _RowKey && other.projectId == projectId;
  @override
  int get hashCode => projectId.hashCode;
}

class _TimesheetPageState extends State<TimesheetPage> {
  late DateTime _weekStart;
  String? _userId; // personne affichée (null = soi)
  final _extraRows = <_RowKey>{};
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _weekStart = startOfWeek(DateTime.now(), context.read<SessionController>().workspace!.weekStart);
      _init = true;
    }
  }

  void _shiftWeek(int weeks) => setState(() {
        _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks);
        _extraRows.clear();
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final rights = TeamRights.of(context);
    final userId = TeammateBar.resolve(rights, _userId);
    final editable = rights.canEditTimeOf(userId);
    final ws = session.workspace!;
    final days = [for (var i = 0; i < 7; i++) DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i)];
    final weekEnd = days.last.add(const Duration(days: 1));
    final locale = context.localeTag;

    return PageScaffold(
      title: l.timesheet,
      actions: [
        IconButton(onPressed: () => _shiftWeek(-1), icon: const Icon(Icons.chevron_left), tooltip: l.previousWeek),
        TextButton(
          onPressed: () => setState(() => _weekStart = startOfWeek(DateTime.now(), ws.weekStart)),
          child: Text('${DateFormat.MMMd(locale).format(days.first)} – ${DateFormat.MMMd(locale).format(days.last)}'),
        ),
        IconButton(onPressed: () => _shiftWeek(1), icon: const Icon(Icons.chevron_right), tooltip: l.nextWeek),
      ],
      child: StreamBuilder<List<EntryRow>>(
        stream: entriesRepo.watchEntries(workspaceId: ws.id, userId: userId, from: days.first, to: weekEnd),
        builder: (context, snap) {
          final rows = snap.data ?? const <EntryRow>[];
          final cells = <_RowKey, List<int>>{};
          for (final r in rows) {
            final key = _RowKey(r.entry.projectId);
            final day = startOfDay(r.entry.startAt.toLocal());
            final idx = day.difference(days.first).inDays;
            if (idx < 0 || idx > 6) continue;
            cells.putIfAbsent(key, () => List.filled(7, 0))[idx] += r.seconds;
          }
          for (final k in _extraRows) {
            cells.putIfAbsent(k, () => List.filled(7, 0));
          }
          final catalog = context.watch<CatalogController>();
          final keys = cells.keys.toList()
            ..sort((a, b) => (catalog.project(a.projectId)?.name ?? '').toLowerCase().compareTo((catalog.project(b.projectId)?.name ?? '').toLowerCase()));
          final dayTotals = List<int>.generate(7, (i) => cells.values.fold(0, (s, v) => s + v[i]));
          final grand = dayTotals.fold(0, (a, b) => a + b);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TeammateBar(
                userId: userId,
                onChanged: (v) => setState(() {
                  _userId = v;
                  _extraRows.clear();
                }),
              ),
              SubmissionBar(userId: userId, periodStart: days.first, periodEnd: days.last, totalSeconds: grand),
              const SizedBox(height: 12),
              Card(
              // Clé par personne : les cellules repartent de zéro quand on change de collaborateur.
              key: ValueKey(userId),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 860),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _headerRow(context, days),
                    const Divider(height: 1),
                    for (final k in keys) ...[
                      _TimesheetRow(rowKey: k, values: cells[k]!, days: days, userId: userId, readOnly: !editable),
                      const Divider(height: 1),
                    ],
                    if (editable)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(l.addRow),
                            onPressed: () async {
                              final pick = await showProjectPicker(context);
                              if (pick != null) setState(() => _extraRows.add(_RowKey(pick.projectId)));
                            },
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    _totalsRow(context, dayTotals, grand),
                  ]),
                ),
              ),
            ),
            ]),
          );
        },
      ),
    );
  }

  Widget _headerRow(BuildContext context, List<DateTime> days) {
    final theme = Theme.of(context);
    final locale = context.localeTag;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        SizedBox(width: 260, child: Padding(padding: const EdgeInsets.only(left: 16), child: Text(context.l10n.project, style: theme.textTheme.labelLarge))),
        for (final d in days)
          SizedBox(
            width: 76,
            child: Column(children: [
              Text(DateFormat.E(locale).format(d), style: theme.textTheme.labelMedium?.copyWith(
                color: sameDay(d, DateTime.now()) ? theme.colorScheme.primary : null,
                fontWeight: sameDay(d, DateTime.now()) ? FontWeight.bold : null,
              )),
              Text(DateFormat.MMMd(locale).format(d), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ]),
          ),
        SizedBox(width: 84, child: Text(context.l10n.total, textAlign: TextAlign.center, style: theme.textTheme.labelLarge)),
      ]),
    );
  }

  Widget _totalsRow(BuildContext context, List<int> totals, int grand) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        SizedBox(width: 260, child: Padding(padding: const EdgeInsets.only(left: 16), child: Text(context.l10n.total, style: theme.textTheme.titleSmall))),
        for (final t in totals) SizedBox(width: 76, child: Text(formatHm(t), textAlign: TextAlign.center, style: theme.textTheme.titleSmall)),
        SizedBox(width: 84, child: Text(formatHm(grand), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
      ]),
    );
  }
}

class _TimesheetRow extends StatelessWidget {
  const _TimesheetRow({required this.rowKey, required this.values, required this.days, required this.userId, required this.readOnly});
  final _RowKey rowKey;
  final List<int> values;
  final List<DateTime> days;
  final String userId;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final total = values.fold(0, (a, b) => a + b);
    return Row(children: [
      SizedBox(
        width: 260,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ProjectLabel(projectId: rowKey.projectId)),
      ),
      for (var i = 0; i < 7; i++)
        SizedBox(
          width: 76,
          child: _Cell(seconds: values[i], projectId: rowKey.projectId, day: days[i], userId: userId, readOnly: readOnly),
        ),
      SizedBox(width: 84, child: Text(formatHm(total), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]);
  }
}

class _Cell extends StatefulWidget {
  const _Cell({required this.seconds, required this.projectId, required this.day, required this.userId, required this.readOnly});
  final int seconds;
  final String? projectId;
  final DateTime day;
  final String userId;
  final bool readOnly;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.seconds));
  final _focus = FocusNode();

  String _fmt(int s) => s == 0 ? '' : formatHm(s);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _Cell old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.seconds != widget.seconds) _c.text = _fmt(widget.seconds);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    if (widget.readOnly) return;
    final secs = parseDuration(_c.text);
    if (secs == null) {
      showSnack(context, context.l10n.invalidDuration);
      _c.text = _fmt(widget.seconds);
      return;
    }
    if ((secs - widget.seconds).abs() < 60) {
      _c.text = _fmt(widget.seconds);
      return;
    }
    if (secs > 24 * 3600) {
      showSnack(context, context.l10n.invalidDuration);
      _c.text = _fmt(widget.seconds);
      return;
    }
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final project = catalog.project(widget.projectId);
    final ws = session.workspace!;
    final lock = DateTime.tryParse(ws.lockEntriesBefore ?? '');
    if (lock != null && widget.day.isBefore(lock) && !session.isAdmin) {
      showSnack(context, context.l10n.entryLocked);
      _c.text = _fmt(widget.seconds);
      return;
    }
    if (await modulesRepo.isDayApproved(ws.id, widget.userId, widget.day)) {
      if (!mounted) return;
      showSnack(context, context.l10n.approvedPeriodFor(memberName(catalog.memberOf(widget.userId))));
      _c.text = _fmt(widget.seconds);
      return;
    }
    await entriesRepo.setDayTotal(
      workspaceId: ws.id,
      userId: widget.userId,
      projectId: widget.projectId,
      dayLocal: widget.day,
      targetSeconds: secs,
      billable: project?.billableDefault ?? true,
      hourlyRateCents: catalog.rateFor(projectId: widget.projectId, userId: widget.userId),
      createdBy: session.userId,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: TextField(
          controller: _c,
          focusNode: _focus,
          readOnly: widget.readOnly,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(hintText: '–', contentPadding: EdgeInsets.symmetric(vertical: 10)),
          onSubmitted: (_) => _focus.unfocus(),
        ),
      );
}
