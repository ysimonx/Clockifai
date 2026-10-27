import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/team_rights.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/teammates.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/ai_usage.dart';
import '../time_entries/entry_dialog.dart';
import '../time_entries/time_entries_page.dart';
import 'report_model.dart';
import 'report_questions.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  RangePreset _preset = RangePreset.thisWeek;
  DateTimeRange? _custom;
  GroupBy _groupBy = GroupBy.project;
  String? _userId; // null = toute l'équipe (managers) ; membres : forcé à soi
  MemberKind _kind = MemberKind.all;
  String? _projectId;
  String? _clientId;
  bool? _billable;
  bool _applyRounding = false;
  bool _detailed = false;
  // Rapports par questions (plan 13, lot 7).
  bool _compare = false;
  bool _toBill = false;

  /// Une question toute faite : règle la période, le regroupement et les filtres d'un geste.
  void _ask({required RangePreset preset, required GroupBy groupBy, MemberKind kind = MemberKind.all, bool toBill = false}) =>
      setState(() {
        _preset = preset;
        _groupBy = groupBy;
        _kind = kind;
        _toBill = toBill;
        _detailed = false;
        _projectId = null;
        _clientId = null;
        _billable = null;
        _userId = null;
      });
  DateTimeRange _range(int weekStart) {
    final now = DateTime.now();
    final ws = startOfWeek(now, weekStart);
    switch (_preset) {
      case RangePreset.thisWeek:
        return DateTimeRange(start: ws, end: ws.add(const Duration(days: 7)));
      case RangePreset.lastWeek:
        return DateTimeRange(start: ws.subtract(const Duration(days: 7)), end: ws);
      case RangePreset.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1));
      case RangePreset.lastMonth:
        return DateTimeRange(start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month));
      case RangePreset.thisYear:
        return DateTimeRange(start: DateTime(now.year), end: DateTime(now.year + 1));
      case RangePreset.custom:
        final c = _custom ?? DateTimeRange(start: ws, end: ws.add(const Duration(days: 6)));
        return DateTimeRange(start: startOfDay(c.start), end: startOfDay(c.end).add(const Duration(days: 1)));
    }
  }

  String _presetLabel(RangePreset p) {
    final l = context.l10n;
    return switch (p) {
      RangePreset.thisWeek => l.thisWeek,
      RangePreset.lastWeek => l.lastWeek,
      RangePreset.thisMonth => l.thisMonth,
      RangePreset.lastMonth => l.lastMonth,
      RangePreset.thisYear => l.thisYear,
      RangePreset.custom => l.customRange,
    };
  }

  String _groupLabel(GroupBy g) {
    final l = context.l10n;
    return switch (g) {
      GroupBy.project => l.project,
      GroupBy.client => l.client,
      GroupBy.user => l.user,
      GroupBy.tag => l.tag,
      GroupBy.day => l.day,
      GroupBy.description => l.description,
    };
  }

  /// Entrées par jour (heure locale), dans l'ordre reçu : les plus récentes d'abord.
  static Map<DateTime, List<EntryRow>> _byDay(List<EntryRow> rows) {
    final byDay = <DateTime, List<EntryRow>>{};
    for (final r in rows) {
      byDay.putIfAbsent(startOfDay(r.entry.startAt.toLocal()), () => []).add(r);
    }
    return byDay;
  }

  List<EntryRow> _filter(List<EntryRow> rows, CatalogController catalog) => rows.where((r) {
        final e = r.entry;
        if (_projectId != null && e.projectId != _projectId) return false;
        if (_clientId != null && catalog.project(e.projectId)?.clientId != _clientId) return false;
        if (_billable != null && e.billable != _billable) return false;
        if (!_kind.accepts(catalog.isAgent(e.userId))) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final ws = session.workspace!;
    final range = _range(ws.weekStart);
    // Managers : tout le workspace ; chef d'équipe : son périmètre ; membre : soi.
    final rights = TeamRights.of(context);
    final userFilter = rights.seesOthers ? _userId : session.userId;
    final locale = context.localeTag;

    return PageScaffold(
      title: l.reports,
      actions: [
        if (rights.canEditOthers)
          IconButton(
            tooltip: l.addTimeForOthers,
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => showEntryDialog(context, initialUserIds: {
              _userId != null && rights.canCreateTimeFor(_userId!) ? _userId! : session.userId!,
            }),
          ),
        PopupMenuButton<String>(
          tooltip: l.export,
          icon: const Icon(Icons.download),
          onSelected: (fmt) => _export(fmt, range, userFilter),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'csv-local', child: Text(l.exportCsvOffline)),
            const PopupMenuItem(value: 'csv', child: Text('CSV')),
            const PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
            const PopupMenuItem(value: 'pdf', child: Text('PDF')),
          ],
        ),
      ],
      child: StreamBuilder<List<EntryRow>>(
        // Période précédente (comparaison) ; flux vide sinon.
        stream: _compare
            ? entriesRepo.watchEntries(
                workspaceId: ws.id, userId: userFilter, from: previousRange(range, _preset).start, to: previousRange(range, _preset).end)
            : Stream.value(const <EntryRow>[]),
        builder: (context, prevSnap) => StreamBuilder<List<EntryRow>>(
        stream: entriesRepo.watchEntries(workspaceId: ws.id, userId: userFilter, from: range.start, to: range.end),
        builder: (context, snap) {
          bool visible(EntryRow r) => r.entry.userId == session.userId || rights.manages(r.entry.userId);
          final rows = _filter(snap.data ?? const [], catalog).where(visible).toList();
          final previous = _filter(prevSnap.data ?? const [], catalog).where(visible).toList();
          final calc = ReportCalculator(catalog: catalog, roundingMinutes: ws.roundingMinutes, applyRounding: _applyRounding);
          final totals = calc.totals(rows);
          final before = _compare ? calc.totals(previous) : null;
          String? vs(num now, num? then) => then == null ? null : deltaPercent(now, then);
          final groups = calc.group(
            rows,
            _groupBy,
            noProject: l.noProject,
            noClient: l.noClient,
            noTag: l.noTag,
            noDescription: l.noDescription,
            dayLabel: (d) => DateFormat.MMMEd(locale).format(d),
          );
          final previousGroups = {
            for (final g in calc.group(previous, _groupBy,
                noProject: l.noProject, noClient: l.noClient, noTag: l.noTag, noDescription: l.noDescription,
                dayLabel: (d) => DateFormat.MMMEd(locale).format(d)))
              g.key: g.seconds,
          };
          final hasAgents = rights.visibleMembers.any((m) => catalog.isAgent(m.userId)) || catalog.agentsOf(session.userId).isNotEmpty;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            // Questions toutes faites : un geste règle période, regroupement et filtres.
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(l.reportQuestions, style: Theme.of(context).textTheme.labelLarge),
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text(rights.seesOthers ? l.qTeamWeek : l.qMyWeek),
                onPressed: () => _ask(preset: RangePreset.thisWeek, groupBy: GroupBy.project),
              ),
              ActionChip(
                avatar: const Icon(Icons.business_outlined, size: 18),
                label: Text(l.qClientsMonth),
                onPressed: () => _ask(preset: RangePreset.thisMonth, groupBy: GroupBy.client),
              ),
              if (rights.seesOthers)
                ActionChip(
                  avatar: const Icon(Icons.groups_outlined, size: 18),
                  label: Text(l.qWhoWhat),
                  onPressed: () => _ask(preset: RangePreset.thisWeek, groupBy: GroupBy.user),
                ),
              if (session.isManager)
                ActionChip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(l.qReadyToBill),
                  onPressed: () => _ask(preset: RangePreset.thisMonth, groupBy: GroupBy.client, toBill: true),
                ),
              if (hasAgents)
                ActionChip(
                  avatar: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(l.qAiCost),
                  onPressed: () => _ask(preset: RangePreset.thisMonth, groupBy: GroupBy.project, kind: MemberKind.agents),
                ),
              FilterChip(
                label: Text(l.qCompare),
                selected: _compare,
                onSelected: (v) => setState(() => _compare = v),
              ),
            ]),
            const SizedBox(height: 8),
            if (_toBill && session.isManager) ...[const ReadyToBill(), const SizedBox(height: 12)],
            _filters(context, session, catalog, range),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _StatCard(label: l.totalTime, value: formatHm(totals.total), delta: vs(totals.total, before?.total)),
              _StatCard(label: l.billableTime, value: formatHm(totals.billable), delta: vs(totals.billable, before?.billable)),
              _StatCard(label: l.amount, value: formatMoney(totals.amount, ws.currency, locale), delta: vs(totals.amount, before?.amount)),
              // Entrées d'agent Claude : tokens et coût estimé au tarif de l'API (plan 10, D17).
              if (totals.aiTokens > 0)
                Tooltip(
                  message: l.aiUsageHelp,
                  child: _StatCard(
                    label: l.aiCostEstimated,
                    value: totals.aiCostMicros == null ? '—' : formatAiCost(totals.aiCostMicros!, locale),
                    caption: l.aiTokens(formatTokens(totals.aiTokens, locale)),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            if (rows.isNotEmpty) _DailyChart(rows: rows, range: range, calc: calc),
            const SizedBox(height: 16),
            Row(children: [
              SegmentedButton<bool>(
                segments: [ButtonSegment(value: false, label: Text(l.summary)), ButtonSegment(value: true, label: Text(l.detailed))],
                selected: {_detailed},
                onSelectionChanged: (s) => setState(() => _detailed = s.first),
              ),
              const Spacer(),
              if (!_detailed)
                DropdownButton<GroupBy>(
                  value: _groupBy,
                  underline: const SizedBox.shrink(),
                  items: [for (final g in GroupBy.values) DropdownMenuItem(value: g, child: Text('${l.groupBy} ${_groupLabel(g).toLowerCase()}'))],
                  onChanged: (g) => setState(() => _groupBy = g!),
                ),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              EmptyState(icon: Icons.bar_chart, title: l.noDataForPeriod)
            else if (_detailed)
              // Jour par jour, les entrées similaires d'une journée réunies sur une ligne dépliable.
              for (final day in _byDay(rows).entries)
                DayCard(day: day.key, rows: day.value, grouped: true, showUser: rights.seesOthers)
            else
              Card(
                child: Column(children: [
                  for (final g in groups)
                    ListTile(
                      leading: g.color == null ? null : ColorDot(g.color!, size: 12),
                      title: g.aiTokens == 0
                          ? Text(g.label)
                          : Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text(g.label),
                              AiUsageText(tokens: g.aiTokens, costMicros: g.aiCostMicros),
                            ]),
                      subtitle: LinearProgressIndicator(
                        value: totals.total == 0 ? 0 : g.seconds / totals.total,
                        color: g.color == null ? null : colorFromHex(g.color!),
                      ),
                      trailing: SizedBox(
                        width: _compare ? 280 : 180,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (g.amount > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(formatMoney(g.amount, ws.currency, locale), style: Theme.of(context).textTheme.bodySmall),
                            ),
                          if (_compare)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(l.qBefore(formatHm(previousGroups[g.key] ?? 0)),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                            ),
                          Text(formatHm(g.seconds), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                        ),
                      ),
                    ),
                ]),
              ),
          ]);
        },
      ),
      ),
    );
  }

  Widget _filters(BuildContext context, SessionController session, CatalogController catalog, DateTimeRange range) {
    final l = context.l10n;
    final locale = context.localeTag;
    final fmt = DateFormat.yMMMd(locale);
    final rights = TeamRights.of(context);
    final members = [for (final m in rights.visibleMembers) if (_kind.accepts(catalog.isAgent(m.userId))) m];
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      DropdownButton<RangePreset>(
        value: _preset,
        items: [for (final p in RangePreset.values) DropdownMenuItem(value: p, child: Text(_presetLabel(p)))],
        onChanged: (p) async {
          if (p == RangePreset.custom) {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDateRange: _custom,
            );
            if (r == null) return;
            setState(() => _custom = r);
          }
          setState(() => _preset = p!);
        },
      ),
      Text('${fmt.format(range.start)} – ${fmt.format(range.end.subtract(const Duration(days: 1)))}', style: Theme.of(context).textTheme.bodySmall),
      // Humains / agents : quand des agents Claude sont visibles (ou si le filtre est posé, pour pouvoir le retirer).
      if (rights.seesOthers && (_kind != MemberKind.all || rights.visibleMembers.any((m) => catalog.isAgent(m.userId))))
        DropdownButton<MemberKind>(
          value: _kind,
          items: [
            DropdownMenuItem(value: MemberKind.all, child: Text(l.humansAndAgents)),
            DropdownMenuItem(value: MemberKind.humans, child: Text(l.humans)),
            DropdownMenuItem(value: MemberKind.agents, child: Text(l.agents)),
          ],
          onChanged: (v) => setState(() {
            _kind = v!;
            if (_userId != null && !_kind.accepts(catalog.isAgent(_userId))) _userId = null;
          }),
        ),
      if (rights.seesOthers)
        DropdownButton<String?>(
          // La personne choisie peut sortir du périmètre entre-temps : on retombe sur « tous ».
          value: members.any((m) => m.userId == _userId) ? _userId : null,
          hint: Text(l.allMembers),
          items: [
            DropdownMenuItem(value: null, child: Text(l.allMembers)),
            for (final m in members) DropdownMenuItem(value: m.userId, child: Text(memberName(m))),
          ],
          onChanged: (v) => setState(() => _userId = v),
        ),
      DropdownButton<String?>(
        value: _clientId,
        items: [
          DropdownMenuItem(value: null, child: Text(l.allClients)),
          for (final c in catalog.clients) DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (v) => setState(() => _clientId = v),
      ),
      DropdownButton<String?>(
        value: _projectId,
        items: [
          DropdownMenuItem(value: null, child: Text(l.allProjects)),
          for (final p in catalog.projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (v) => setState(() => _projectId = v),
      ),
      DropdownButton<bool?>(
        value: _billable,
        items: [
          DropdownMenuItem(value: null, child: Text(l.billableAndNot)),
          DropdownMenuItem(value: true, child: Text(l.billable)),
          DropdownMenuItem(value: false, child: Text(l.nonBillable)),
        ],
        onChanged: (v) => setState(() => _billable = v),
      ),
      if (session.workspace!.roundingMinutes > 0)
        FilterChip(
          label: Text(l.applyRounding(session.workspace!.roundingMinutes)),
          selected: _applyRounding,
          onSelected: (v) => setState(() => _applyRounding = v),
        ),
    ]);
  }

  Future<void> _export(String fmt, DateTimeRange range, String? userId) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final from = DateFormat('yyyy-MM-dd').format(range.start);
    final to = DateFormat('yyyy-MM-dd').format(range.end.subtract(const Duration(days: 1)));
    final name = 'clockifai-$from-$to';
    try {
      if (fmt == 'csv-local') {
        final rights = TeamRights.read(context);
        final rows = _filter(
          await entriesRepo.watchEntries(workspaceId: session.workspaceId!, userId: userId, from: range.start, to: range.end).first,
          catalog,
        ).where((r) => r.entry.userId == session.userId || rights.manages(r.entry.userId)).toList();
        final csv = StringBuffer('﻿User;Type;Client;Project;Task;Description;Start;End;Hours;Billable;AI tokens;AI cost (USD)\n');
        String q(String s) => '"${s.replaceAll('"', '""')}"';
        for (final r in rows) {
          final e = r.entry;
          csv.writeln([
            q(catalog.memberOf(e.userId)?.displayName ?? ''),
            catalog.isAgent(e.userId) ? 'agent' : 'human',
            q(catalog.clientOfProject(e.projectId)?.name ?? ''),
            q(catalog.project(e.projectId)?.name ?? ''),
            q(catalog.task(e.taskId)?.name ?? ''),
            q(e.description),
            e.startAt.toLocal().toIso8601String(),
            e.endAt?.toLocal().toIso8601String() ?? '',
            (r.seconds / 3600).toStringAsFixed(2),
            e.billable ? '1' : '0',
            r.aiTokens == 0 ? '' : '${r.aiTokens}',
            r.aiCostMicros == null ? '' : (r.aiCostMicros! / 1e6).toStringAsFixed(4),
          ].join(';'));
        }
        await FileSaver.instance.saveFile(name: name, bytes: Uint8List.fromList(utf8.encode(csv.toString())), fileExtension: 'csv', mimeType: MimeType.csv);
      } else {
        final bytes = await ServicesApi.download('/api/exports/report', {
          'workspace_id': session.workspaceId!,
          'from': from,
          'to': to,
          'format': fmt,
          'user_id': ?userId,
          'project_id': ?_projectId,
          'client_id': ?_clientId,
          if (_billable != null) 'billable': '$_billable',
          'member_kind': ?_kind.param,
        });
        final mime = switch (fmt) { 'xlsx' => MimeType.microsoftExcel, 'pdf' => MimeType.pdf, _ => MimeType.csv };
        await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: fmt, mimeType: mime);
      }
      if (mounted) showSnack(context, l.exportDone);
    } catch (e) {
      if (mounted) showSnack(context, l.exportFailed('$e'));
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.caption, this.delta});
  final String label;
  final String value;
  final String? caption;

  /// Écart avec la période précédente (« +12 % »), quand on compare.
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (caption != null) Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            if (delta != null)
              Text(context.l10n.qDelta(delta!),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: delta!.startsWith('+') ? AppColors.of(context).success : (delta!.startsWith('−') ? theme.colorScheme.error : theme.colorScheme.outline))),
          ]),
        ),
      ),
    );
  }
}

/// Histogramme des heures par jour (ou par mois au-delà de 62 jours).
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.rows, required this.range, required this.calc});
  final List<EntryRow> rows;
  final DateTimeRange range;
  final ReportCalculator calc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final days = range.end.difference(range.start).inDays;
    final monthly = days > 62;
    final buckets = <DateTime>[];
    if (monthly) {
      for (var d = DateTime(range.start.year, range.start.month); d.isBefore(range.end); d = DateTime(d.year, d.month + 1)) {
        buckets.add(d);
      }
    } else {
      for (var i = 0; i < days; i++) {
        buckets.add(DateTime(range.start.year, range.start.month, range.start.day + i));
      }
    }
    final values = List<double>.filled(buckets.length, 0);
    for (final r in rows) {
      final d = r.entry.startAt.toLocal();
      final idx = monthly
          ? buckets.indexWhere((b) => b.year == d.year && b.month == d.month)
          : buckets.indexWhere((b) => sameDay(b, d));
      if (idx >= 0) values[idx] += calc.secondsOf(r) / 3600;
    }
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);
    // Graduations lisibles : quarts d'heure sous 1 h, sinon heures entières.
    final interval = maxY <= 1 ? 0.25 : (maxY / 4).ceilToDouble();
    final top = maxY == 0 ? 1.0 : ((maxY / interval).ceil() + 1) * interval;
    final labelEvery = (buckets.length / 12).ceil().clamp(1, 1000);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: SizedBox(
          height: 220,
          child: BarChart(BarChartData(
            maxY: top,
            gridData: FlGridData(drawVerticalLine: false, horizontalInterval: interval, getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${monthly ? DateFormat.yMMM(locale).format(buckets[group.x]) : DateFormat.MMMEd(locale).format(buckets[group.x])}\n${formatHm((rod.toY * 3600).round())}',
                  TextStyle(color: theme.colorScheme.onInverseSurface),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: interval,
                  getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(formatHm((v * 3600).round()), style: theme.textTheme.labelSmall),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i % labelEvery != 0 || i >= buckets.length) return const SizedBox.shrink();
                    final d = buckets[i];
                    return Text(monthly ? DateFormat.MMM(locale).format(d) : (days <= 7 ? DateFormat.E(locale).format(d) : DateFormat.d(locale).format(d)), style: theme.textTheme.labelSmall);
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: buckets.length > 20 ? 8 : 18,
                    color: theme.colorScheme.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ]),
            ],
          )),
        ),
      ),
    );
  }
}
