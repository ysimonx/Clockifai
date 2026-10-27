part of 'today_page.dart';

// Colonne de droite d'« Aujourd'hui » : titres de section, bilan du jour et temps par projet (sortis de
// today_page.dart, plan 17).

TextStyle? _mono(BuildContext context, {bool muted = true}) {
  final theme = Theme.of(context);
  return theme.textTheme.bodySmall?.copyWith(
      fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()], color: muted ? theme.colorScheme.outline : null);
}

Widget _label(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Text(text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6, fontWeight: FontWeight.w600));
}

Widget _summary(BuildContext context,
    {required DateTime day,
    required DateTime now,
    required CatalogController catalog,
    required DayPlan plan,
    required List<EntryRow> mine,
    required int loggedMin,
    required int draftMin,
    required List<(TimeEntry, Span)> claude}) {
  final l = context.l10n;
  final theme = Theme.of(context);
  final target = plan.typical.target;
  final claudeMin = claude.fold(0, (a, c) => a + c.$2.length);
  Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.journalSummary.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(formatHm((loggedMin + draftMin) * 60),
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          Text(l.journalTarget(formatHm(target * 60)), style: theme.textTheme.bodyMedium),
        ]),
        const SizedBox(height: 10),
        Semantics(
          label: '${l.journalConfirmed} ${formatHm(loggedMin * 60)}, ${l.journalToConfirm} ${formatHm(draftMin * 60)}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Stack(children: [
                Container(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                FractionallySizedBox(
                    widthFactor: target == 0 ? 0 : ((loggedMin + draftMin) / target).clamp(0.0, 1.0),
                    child: Container(color: theme.colorScheme.tertiary.withValues(alpha: 0.45))),
                FractionallySizedBox(
                    widthFactor: target == 0 ? 0 : (loggedMin / target).clamp(0.0, 1.0),
                    child: Container(color: theme.colorScheme.onSurface)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        line(l.journalConfirmed, formatHm(loggedMin * 60)),
        line(l.journalToConfirm, formatHm(draftMin * 60)),
        if (claude.isNotEmpty) line('Claude', formatHm(claudeMin * 60)),
        ..._perProject(context, day, now, mine, claude),
        const SizedBox(height: 10),
        Text(
          plan.typical.fromProfile
              ? l.journalTypicalProfile(hm(plan.typical.start), hm(plan.typical.end))
              : plan.typical.fromHistory
                  ? l.journalTypicalDay(hm(plan.typical.start), hm(plan.typical.end))
                  : l.journalTypicalDefault(hm(plan.typical.start), hm(plan.typical.end)),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ]),
    ),
  );
}

/// Bilan par projet : vos minutes et celles de Claude, côte à côte.
List<Widget> _perProject(BuildContext context, DateTime day, DateTime now, List<EntryRow> mine, List<(TimeEntry, Span)> claude) {
  final l = context.l10n;
  final theme = Theme.of(context);
  final me = <String?, int>{}, agent = <String?, int>{};
  for (final r in mine) {
    if (spanOf(r.entry, day, now) case final sp?) me[r.entry.projectId] = (me[r.entry.projectId] ?? 0) + sp.length;
  }
  for (final (e, sp) in claude) {
    agent[e.projectId] = (agent[e.projectId] ?? 0) + sp.length;
  }
  final ids = {...me.keys, ...agent.keys}.toList()..sort((a, b) => ((me[b] ?? 0) + (agent[b] ?? 0)).compareTo((me[a] ?? 0) + (agent[a] ?? 0)));
  if (ids.length < 2 && agent.isEmpty) return const [];
  final mono = _mono(context, muted: false);
  final head = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline);
  Widget cell(String text, TextStyle? style) => SizedBox(width: 52, child: Text(text, textAlign: TextAlign.right, style: style));
  return [
    const SizedBox(height: 12),
    Row(children: [Expanded(child: Text(l.project, style: head)), cell(l.journalYou, head), if (agent.isNotEmpty) cell('Claude', head)]),
    for (final id in ids.take(6))
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(child: id == null ? Text(l.noProject, style: theme.textTheme.bodySmall) : ProjectLabel(projectId: id, dense: true)),
          cell(me[id] == null ? '–' : formatHm(me[id]! * 60), mono),
          if (agent.isNotEmpty) cell(agent[id] == null ? '–' : formatHm(agent[id]! * 60), mono),
        ]),
      ),
  ];
}
