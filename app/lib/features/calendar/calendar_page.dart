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
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/entry_dialog.dart';

/// Vue calendrier (semaine sur grand écran, jour sur mobile) : les entrées sont des blocs
/// positionnés sur la grille horaire ; un clic sur un créneau vide crée une entrée.
/// Un chef d'équipe ou un manager choisit la personne affichée (bandeau « Collaborateur »).
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const _hourHeight = 56.0;
  DateTime _anchor = DateTime.now();
  String? _userId; // personne affichée (null = soi)
  final _scroll = ScrollController(initialScrollOffset: 7 * _hourHeight);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final rights = TeamRights.of(context);
    final userId = TeammateBar.resolve(rights, _userId);
    final editable = rights.canEditTimeOf(userId);
    final ws = session.workspace!;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final first = wide ? startOfWeek(_anchor, ws.weekStart) : startOfDay(_anchor);
    final count = wide ? 7 : 1;
    final days = [for (var i = 0; i < count; i++) DateTime(first.year, first.month, first.day + i)];
    final end = days.last.add(const Duration(days: 1));
    final locale = context.localeTag;

    return PageScaffold(
      title: l.calendar,
      maxWidth: 1400,
      actions: [
        IconButton(onPressed: () => setState(() => _anchor = _anchor.subtract(Duration(days: count))), icon: const Icon(Icons.chevron_left)),
        TextButton(
          onPressed: () => setState(() => _anchor = DateTime.now()),
          child: Text(wide
              ? '${DateFormat.MMMd(locale).format(days.first)} – ${DateFormat.MMMd(locale).format(days.last)}'
              : DateFormat.MMMEd(locale).format(days.first)),
        ),
        IconButton(onPressed: () => setState(() => _anchor = _anchor.add(Duration(days: count))), icon: const Icon(Icons.chevron_right)),
      ],
      child: StreamBuilder<List<EntryRow>>(
        stream: entriesRepo.watchEntries(workspaceId: ws.id, userId: userId, from: days.first, to: end, includeRunning: true),
        builder: (context, snap) {
          final rows = snap.data ?? const <EntryRow>[];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TeammateBar(userId: userId, onChanged: (v) => setState(() => _userId = v)),
            ),
            // En-têtes des jours avec total.
            Row(children: [
              const SizedBox(width: 48),
              for (final d in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      Text(DateFormat.E(locale).format(d), style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        DateFormat.d(locale).format(d),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: sameDay(d, DateTime.now()) ? Theme.of(context).colorScheme.primary : null,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        formatHm(rows.where((r) => sameDay(r.entry.startAt.toLocal(), d)).fold(0, (s, r) => s + r.seconds)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ]),
                  ),
                ),
            ]),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * _hourHeight,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 48,
                      child: Stack(children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * _hourHeight - 7,
                            right: 6,
                            child: Text('${h.toString().padLeft(2, '0')}:00', style: Theme.of(context).textTheme.labelSmall),
                          ),
                      ]),
                    ),
                    for (final d in days)
                      Expanded(
                        child: _DayColumn(
                          day: d,
                          rows: rows.where((r) => _overlaps(r, d)).toList(),
                          hourHeight: _hourHeight,
                          userId: userId,
                          editable: editable,
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  bool _overlaps(EntryRow r, DateTime day) {
    final s = r.entry.startAt.toLocal();
    final e = (r.entry.endAt ?? DateTime.now().toUtc()).toLocal();
    final dayEnd = day.add(const Duration(days: 1));
    return s.isBefore(dayEnd) && e.isAfter(day);
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.rows, required this.hourHeight, required this.userId, required this.editable});
  final DateTime day;
  final List<EntryRow> rows;
  final double hourHeight;
  final String userId;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final dayEnd = day.add(const Duration(days: 1));
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (!editable) return;
          final minutes = (details.localPosition.dy / hourHeight * 60).floor();
          final start = day.add(Duration(minutes: (minutes ~/ 15) * 15));
          showEntryDialog(context, initialStart: start, initialEnd: start.add(const Duration(hours: 1)), initialUserIds: {userId});
        },
        child: Stack(children: [
          for (var h = 0; h < 24; h++)
            Positioned(
              top: h * hourHeight,
              left: 0,
              right: 0,
              child: Container(height: hourHeight, decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)), left: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))))),
            ),
          if (sameDay(day, DateTime.now()))
            Positioned(
              top: (DateTime.now().hour * 60 + DateTime.now().minute) / 60 * hourHeight,
              left: 0,
              right: 0,
              child: Container(height: 2, color: theme.colorScheme.error),
            ),
          for (final r in rows) _block(context, r, catalog, dayEnd),
        ]),
      );
    });
  }

  Widget _block(BuildContext context, EntryRow r, CatalogController catalog, DateTime dayEnd) {
    final theme = Theme.of(context);
    var s = r.entry.startAt.toLocal();
    var e = (r.entry.endAt ?? DateTime.now().toUtc()).toLocal();
    if (s.isBefore(day)) s = day;
    if (e.isAfter(dayEnd)) e = dayEnd;
    final top = s.difference(day).inMinutes / 60 * hourHeight;
    final height = (e.difference(s).inMinutes / 60 * hourHeight).clamp(18.0, 24 * hourHeight);
    final project = catalog.project(r.entry.projectId);
    final color = project == null ? theme.colorScheme.outline : colorFromHex(project.color);
    final running = r.entry.endAt == null;
    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: Material(
        color: color.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: color, width: running ? 2 : 0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showEntryDialog(context, entry: r.entry, tagIds: r.tagIds),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: r.entry.description.isEmpty ? (project?.name ?? '') : r.entry.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (height > 34) TextSpan(text: '\n${project?.name ?? context.l10n.noProject} · ${formatHm(r.seconds)}'),
              ]),
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.fade,
            ),
          ),
        ),
      ),
    );
  }
}
