import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/text_search.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/entry_dialog.dart';
import 'day_plan.dart';
import 'quick_entry.dart';

/// « Aujourd'hui », le journal automatique (plans/13-ux-moderne.md, lot 11) : la journée sur une frise, les entrées
/// saisies, les créneaux vides et les propositions tirées des habitudes, du planning et des sessions de Claude, à
/// confirmer d'un geste. Glisser sur le vide crée un bloc ; tirer un bloc ou ses bords l'ajuste.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.clock = DateTime.now});

  /// Heure courante (remplacée dans les tests).
  final DateTime Function() clock;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

enum _Kind { logged, draft, fresh }

/// Un bloc de la ligne « Vous » : entrée saisie, proposition ou nouvelle entrée en cours de création.
class _Block {
  _Block({required this.id, required this.kind, required this.span, required this.title, this.projectId, this.taskId, this.entry, this.draft});
  final String id;
  final _Kind kind;
  final Span span;
  final String title;
  final String? projectId;
  final String? taskId;
  final TimeEntry? entry;
  final Draft? draft;

  bool get running => entry != null && entry!.endAt == null;
  bool get movable => kind != _Kind.logged || (!running && !entry!.locked);
}

class _DraftEdit {
  const _DraftEdit({this.span, this.title, this.projectId, this.taskId, this.projectSet = false});
  final Span? span;
  final String? title;
  final String? projectId;
  final String? taskId;
  final bool projectSet;
  _DraftEdit copyWith({Span? span, String? title, String? projectId, String? taskId, bool? projectSet}) => _DraftEdit(
        span: span ?? this.span,
        title: title ?? this.title,
        projectId: projectSet == true ? projectId : this.projectId,
        taskId: projectSet == true ? taskId : this.taskId,
        projectSet: projectSet ?? this.projectSet,
      );
}

enum _Drag { create, move, left, right }

class _TodayPageState extends State<TodayPage> {
  late DateTime _day = _midnight(widget.clock());
  String? _sel;
  final Map<String, _DraftEdit> _edits = {};
  final Map<String, Span> _override = {};
  Span? _fresh;
  String _freshTitle = '';
  String? _freshProject;
  String? _freshTask;
  _Drag? _drag;
  int _anchor = 0;
  Span? _dragOrigin;
  double _dragDx = 0;
  final _focus = FocusNode(debugLabel: 'journal');
  final _title = TextEditingController();
  final _quick = TextEditingController();
  final _quickFocus = FocusNode(debugLabel: 'saisie express');
  String? _titleFor;
  Timer? _tick;

  /// Flux Drift du jour affiché, gardés d'une construction à l'autre : un glisser reconstruit la page à chaque
  /// mouvement, il ne doit pas relancer les requêtes.
  String? _streamsKey;
  late Stream<List<EntryRow>> _mineStream;
  late Stream<List<EntryRow>> _agentStream;
  late Stream<List<ScheduleAssignment>> _planStream;

  void _ensureStreams(String ws, String me, String? agentId) {
    final key = '$ws|$me|$agentId|${_day.toIso8601String()}';
    if (key == _streamsKey) return;
    _streamsKey = key;
    final next = addDays(_day, 1);
    _mineStream = entriesRepo.watchEntries(
        workspaceId: ws, userId: me, from: addDays(_day, -35), to: next, includeRunning: true);
    _agentStream = agentId == null
        ? Stream.value(const <EntryRow>[])
        : entriesRepo.watchEntries(workspaceId: ws, userId: agentId, from: _day, to: next, includeRunning: true);
    _planStream = modulesRepo.watchAssignments(ws, userId: me, from: _day, to: next);
  }

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focus.dispose();
    _title.dispose();
    _quick.dispose();
    _quickFocus.dispose();
    super.dispose();
  }

  DateTime _at(int minutes) => atMinute(_day, minutes);

  void _goTo(DateTime day) => setState(() {
        _day = _midnight(day);
        _sel = null;
        _fresh = null;
        _edits.clear();
        _override.clear();
      });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final prefs = context.watch<DisplayPrefs>();
    final ws = session.workspaceId!;
    final me = session.userId!;
    final agents = catalog.agentsOf(me);
    _ensureStreams(ws, me, agents.firstOrNull?.userId);
    return StreamBuilder<List<EntryRow>>(
      stream: _mineStream,
      builder: (context, mineSnap) => StreamBuilder<List<EntryRow>>(
        stream: _agentStream,
        builder: (context, agentSnap) => StreamBuilder<List<ScheduleAssignment>>(
          stream: _planStream,
          builder: (context, planSnap) => _page(
            context,
            catalog: catalog,
            prefs: prefs,
            me: me,
            ws: ws,
            rows: mineSnap.data ?? const [],
            agentRows: agentSnap.data ?? const [],
            planning: planSnap.data ?? const [],
            loading: !mineSnap.hasData,
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context,
      {required CatalogController catalog,
      required DisplayPrefs prefs,
      required String me,
      required String ws,
      required List<EntryRow> rows,
      required List<EntryRow> agentRows,
      required List<ScheduleAssignment> planning,
      required bool loading}) {
    final l = context.l10n;
    final now = widget.clock();
    final dayEnd = addDays(_day, 1);
    final mineRows = rows.where((r) => !r.entry.startAt.toLocal().isBefore(_day) && r.entry.startAt.toLocal().isBefore(dayEnd)).toList();
    final history = [for (final r in rows) if (r.entry.startAt.toLocal().isBefore(_day)) r.entry];
    final plan = planDay(
      day: _day,
      now: now,
      mine: [for (final r in mineRows) r.entry],
      history: history,
      agentEntries: [for (final r in agentRows) r.entry],
      planning: planning,
      dismissed: prefs.dismissedSuggestions,
    );

    final blocks = <_Block>[
      for (final r in mineRows)
        if (spanOf(r.entry, _day, now) case final sp?)
          _Block(
            id: 'e:${r.entry.id}',
            kind: _Kind.logged,
            span: _override['e:${r.entry.id}'] ?? sp,
            title: r.entry.description,
            projectId: r.entry.projectId,
            taskId: r.entry.taskId,
            entry: r.entry,
          ),
      for (final d in plan.drafts)
        _Block(
          id: 'd:${d.key}',
          kind: _Kind.draft,
          span: _edits[d.key]?.span ?? d.span,
          title: _edits[d.key]?.title ?? d.description,
          projectId: _edits[d.key]?.projectSet == true ? _edits[d.key]!.projectId : d.projectId,
          taskId: _edits[d.key]?.projectSet == true ? _edits[d.key]!.taskId : d.taskId,
          draft: d,
        ),
      if (_fresh != null)
        _Block(id: 'new', kind: _Kind.fresh, span: _fresh!, title: _freshTitle, projectId: _freshProject, taskId: _freshTask),
    ]..sort((a, b) => a.span.start.compareTo(b.span.start));
    final drafts = blocks.where((b) => b.kind == _Kind.draft).toList();
    final gaps = subtract(plan.windows, [for (final b in blocks) b.span], min: 15);
    final selected = blocks.where((b) => b.id == _sel).firstOrNull;
    if (selected?.id != _titleFor) {
      _titleFor = selected?.id;
      _title.text = selected?.title ?? '';
    }

    final loggedMin = plan.loggedMinutes;
    final draftMin = drafts.fold(0, (a, b) => a + b.span.length);
    final claudeSpans = [for (final r in agentRows) if (spanOf(r.entry, _day, now) case final sp?) (r.entry, sp)];

    // Plage affichée : au moins 7:00 – 19:00, élargie à ce qui est saisi.
    final starts = [420, for (final w in plan.windows) w.start, for (final b in blocks) b.span.start, for (final c in claudeSpans) c.$2.start];
    final ends = [1140, for (final w in plan.windows) w.end, for (final b in blocks) b.span.end, for (final c in claudeSpans) c.$2.end];
    final range = Span((starts.reduce(math.min) ~/ 60) * 60, math.min(1440, ((ends.reduce(math.max) + 59) ~/ 60) * 60));

    Future<void> confirmDrafts(List<_Block> list) async {
      final ids = <String>[];
      for (final b in list) {
        ids.add(await entriesRepo.createManual(
          workspaceId: ws,
          userId: me,
          start: _at(b.span.start),
          end: _at(b.span.end),
          createdBy: me,
          draft: EntryDraft(
            description: b.title,
            projectId: b.projectId,
            taskId: b.taskId,
            billable: catalog.billableFor(projectId: b.projectId, userId: me),
            hourlyRateCents: catalog.rateFor(projectId: b.projectId, userId: me),
          ),
        ));
      }
      if (!mounted) return;
      final next = drafts.where((d) => !list.contains(d)).firstOrNull;
      setState(() {
        for (final b in list) {
          _edits.remove(b.draft!.key);
        }
        _sel = next?.id;
      });
      final minutes = list.fold(0, (a, b) => a + b.span.length);
      showUndo(this.context, l.journalAdded(list.length, formatHm(minutes * 60)), () => entriesRepo.deleteMany(ids));
    }

    Future<void> dismiss(_Block b) async {
      final key = b.draft!.key;
      final next = drafts.where((d) => d.id != b.id).firstOrNull;
      await prefs.dismissSuggestion(key);
      if (!mounted) return;
      setState(() => _sel = next?.id);
      showUndo(this.context, l.journalIgnored, () => prefs.restoreSuggestion(key));
    }

    Future<void> saveFresh() async {
      final sp = _fresh;
      if (sp == null) return;
      final id = await entriesRepo.createManual(
        workspaceId: ws,
        userId: me,
        start: _at(sp.start),
        end: _at(sp.end),
        createdBy: me,
        draft: EntryDraft(
          description: _freshTitle,
          projectId: _freshProject,
          taskId: _freshTask,
          billable: catalog.billableFor(projectId: _freshProject, userId: me),
          hourlyRateCents: catalog.rateFor(projectId: _freshProject, userId: me),
        ),
      );
      if (!mounted) return;
      setState(() {
        _fresh = null;
        _freshTitle = '';
        _freshProject = null;
        _freshTask = null;
        _sel = 'e:$id';
      });
      showUndo(this.context, l.journalAdded(1, formatHm(sp.length * 60)), () => entriesRepo.delete(id));
    }

    Future<void> commitSpan(_Block b, Span sp) async {
      if (b.kind == _Kind.draft) {
        setState(() => _edits[b.draft!.key] = (_edits[b.draft!.key] ?? const _DraftEdit()).copyWith(span: sp));
      } else if (b.kind == _Kind.fresh) {
        setState(() => _fresh = sp);
      } else if (b.entry != null) {
        setState(() => _override[b.id] = sp);
        await entriesRepo.update(b.entry!, start: _at(sp.start), end: _at(sp.end));
        if (mounted) setState(() => _override.remove(b.id));
      }
    }

    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final b = selected;
      final key = event.logicalKey;
      if (b == null) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.enter) {
        if (b.kind == _Kind.draft) confirmDrafts([b]);
        if (b.kind == _Kind.fresh) saveFresh();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
        if (b.kind == _Kind.draft) dismiss(b);
        if (b.kind == _Kind.fresh) setState(() => _fresh = null);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) && b.movable) {
        final step = key == LogicalKeyboardKey.arrowLeft ? -5 : 5;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final sp = shift
            ? Span(b.span.start, math.max(b.span.start + 10, math.min(1440, b.span.end + step)))
            : Span(math.max(0, b.span.start + step), math.min(1440, b.span.end + step));
        commitSpan(b, sp);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        final i = blocks.indexOf(b);
        final j = (key == LogicalKeyboardKey.arrowUp ? i - 1 : i + 1).clamp(0, blocks.length - 1);
        setState(() => _sel = blocks[j].id);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final hero = _hero(context, plan: plan, drafts: drafts, gaps: gaps, loggedMin: loggedMin, draftMin: draftMin,
        onConfirmAll: () => confirmDrafts(drafts), onReview: () => setState(() => _sel = drafts.firstOrNull?.id));
    final quick = _quickEntry(context,
        catalog: catalog, rows: rows, proposed: [for (final b in blocks) if (b.kind != _Kind.logged) b.span], now: now, me: me, ws: ws);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _header(context, rows: rows, target: plan.typical.target, now: now),
              const SizedBox(height: 16),
              hero,
              const SizedBox(height: 16),
              quick,
              const SizedBox(height: 16),
              Focus(
                focusNode: _focus,
                onKeyEvent: onKey,
                child: _timeline(
                  context,
                  catalog: catalog,
                  range: range,
                  blocks: blocks,
                  gaps: gaps,
                  claude: claudeSpans,
                  isToday: _day == _midnight(now),
                  nowMin: minuteOf(now, _day),
                  commitSpan: commitSpan,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, c) {
                final inspector = _inspector(context, catalog: catalog, b: selected,
                    onConfirm: (b) => confirmDrafts([b]), onDismiss: dismiss, onSaveFresh: saveFresh);
                final summary = _summary(context, plan: plan, loggedMin: loggedMin, draftMin: draftMin, claude: claudeSpans);
                if (c.maxWidth < 900) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [inspector, const SizedBox(height: 16), summary]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: inspector),
                  const SizedBox(width: 16),
                  Expanded(child: summary),
                ]);
              }),
              if (loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
            ]),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ saisie express (lot 3)
  /// Où ranger [q] : sa plage, sinon le premier créneau vide assez grand de son jour, en laissant d'abord en place
  /// les propositions affichées ([proposed], jour affiché seulement), puis à leur place, sinon après la dernière entrée.
  ({DateTime day, Span span, bool inGap})? _slotFor(QuickEntry q, List<EntryRow> rows, DateTime now, List<Span> proposed) {
    final day = addDays(now, q.dayOffset);
    if (q.hasRange) return (day: day, span: Span(q.startMinute!, q.endMinute!), inGap: false);
    final d = q.minutes;
    if (d == null || d <= 0) return null;
    final end = addDays(day, 1);
    final plan = planDay(
      day: day,
      now: now,
      mine: [for (final r in rows) if (!r.entry.startAt.toLocal().isBefore(day) && r.entry.startAt.toLocal().isBefore(end)) r.entry],
      history: [for (final r in rows) if (r.entry.startAt.toLocal().isBefore(day)) r.entry],
    );
    Span? fit(List<Span> taken) => subtract(plan.windows, taken, min: 5).where((g) => g.length >= d).firstOrNull;
    if (fit([...plan.busy, if (day == _day) ...proposed]) case final g?) return (day: day, span: Span(g.start, g.start + d), inGap: true);
    if (fit(plan.busy) case final g?) return (day: day, span: Span(g.start, g.start + d), inGap: false);
    final from = plan.busy.isEmpty ? plan.typical.start : plan.busy.map((s) => s.end).reduce(math.max);
    return (day: day, span: Span(from, math.min(1440, from + d)), inGap: false);
  }

  List<String> _examples(CatalogController catalog) {
    String word(String name) => name.split(RegExp(r'\s+')).firstWhere((w) => w.length >= 5, orElse: () => name.split(' ').last).toLowerCase();
    final tasks = catalog.tasks.where((t) => t.status == 'active' && catalog.project(t.projectId)?.archived == false).toList();
    final projects = catalog.activeProjects;
    return [
      if (tasks.isNotEmpty) '1h30 ${tasks.first.name.toLowerCase()} ${word(catalog.project(tasks.first.projectId)!.name)}',
      if (projects.isNotEmpty) '9h-10h30 ${word(projects.last.name)} hier',
      '45min appel #nf',
    ];
  }

  Widget _quickEntry(BuildContext context,
      {required CatalogController catalog,
      required List<EntryRow> rows,
      required List<Span> proposed,
      required DateTime now,
      required String me,
      required String ws}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final q = parseQuickEntry(
      _quick.text,
      weekday: now.weekday,
      projects: [for (final p in catalog.activeProjects) QuickProject(p.id, p.name, client: catalog.client(p.clientId)?.name)],
      tasks: [for (final t in catalog.tasks) if (t.status == 'active') QuickTask(t.id, t.name, t.projectId)],
      tags: [for (final t in catalog.activeTags) QuickTag(t.id, t.name)],
    );
    final slot = q == null ? null : _slotFor(q, rows, now, proposed);
    final ready = q != null && q.isComplete && slot != null;
    final project = catalog.project(q?.projectId);
    final task = catalog.task(q?.taskId);

    Future<void> save() async {
      if (!ready) return;
      final billable = q.billable ?? catalog.billableFor(projectId: q.projectId, userId: me);
      final added = l.quickAdded(q.description.isEmpty ? (project?.name ?? '') : q.description,
          dayLabel(context, slot.day, today: l.today, yesterday: l.yesterday, now: now), '${hm(slot.span.start)} → ${hm(slot.span.end)}');
      final id = await entriesRepo.createManual(
        workspaceId: ws,
        userId: me,
        start: atMinute(slot.day, slot.span.start),
        end: atMinute(slot.day, slot.span.end),
        createdBy: me,
        draft: EntryDraft(
          description: q.description,
          projectId: q.projectId,
          taskId: q.taskId,
          billable: billable,
          hourlyRateCents: catalog.rateFor(projectId: q.projectId, userId: me),
          tagIds: q.tagIds,
        ),
      );
      if (!mounted) return;
      _quick.clear();
      setState(() {});
      _quickFocus.requestFocus();
      showUndo(this.context, added, () => entriesRepo.delete(id));
    }

    Widget chip(String text, {Color? dot, bool missing = false, bool mono = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: missing ? theme.colorScheme.errorContainer.withValues(alpha: 0.5) : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(text, style: theme.textTheme.labelMedium?.copyWith(fontFeatures: mono ? const [FontFeature.tabularFigures()] : null)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => setState(_quick.clear)},
                child: TextField(
                  controller: _quick,
                  focusNode: _quickFocus,
                  textInputAction: TextInputAction.done,
                  style: theme.textTheme.titleMedium,
                  decoration: InputDecoration(
                    labelText: l.quickEntry,
                    hintText: l.quickEntryHint,
                    prefixIcon: const Icon(Icons.add),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => save(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: ready ? save : null, child: Text(l.save)),
          ]),
          const SizedBox(height: 8),
          if (q == null)
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(l.quickEntryTry, style: theme.textTheme.bodySmall),
              for (final ex in _examples(catalog))
                ActionChip(
                  label: Text(ex),
                  onPressed: () => setState(() {
                    _quick.text = ex;
                    _quick.selection = TextSelection.collapsed(offset: ex.length);
                    _quickFocus.requestFocus();
                  }),
                ),
            ])
          else
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              chip(q.duration == null ? l.quickDurationMissing : formatHm(q.duration! * 60), missing: q.duration == null, mono: true),
              chip(project?.name ?? l.quickProjectMissing, dot: project == null ? null : colorFromHex(project.color), missing: project == null && q.description.isEmpty),
              if (task != null) chip(task.name),
              // La description seule quand elle dit autre chose que le nom de la tâche.
              if (q.description.isNotEmpty && fold(q.description) != fold(task?.name ?? '')) chip('« ${q.description} »'),
              for (final id in q.tagIds) chip('#${catalog.tag(id)?.name ?? ''}'),
              if (slot != null) ...[
                chip(dayLabel(context, slot.day, today: l.today, yesterday: l.yesterday, now: now)),
                chip('${hm(slot.span.start)} → ${hm(slot.span.end)}${slot.inGap ? ' · ${l.quickInGap}' : ''}', mono: true),
              ],
              chip((q.billable ?? catalog.billableFor(projectId: q.projectId, userId: me)) ? l.billable : l.nonBillable),
            ]),
          const SizedBox(height: 6),
          Text(l.quickEntryHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ en-tête : jour et semaine en anneaux
  Widget _header(BuildContext context, {required List<EntryRow> rows, required int target, required DateTime now}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final today = _midnight(now);
    final days = [for (var i = 6; i >= 0; i--) addDays(_day, -i)];
    int minutesOn(DateTime d) {
      final end = addDays(d, 1);
      return rows
          .where((r) => !r.entry.startAt.toLocal().isBefore(d) && r.entry.startAt.toLocal().isBefore(end))
          .fold(0, (a, r) => a + ((r.entry.endAt ?? now).difference(r.entry.startAt).inMinutes));
    }

    final title = toBeginningOfSentenceCase(DateFormat.yMMMMEEEEd(locale).format(_day));
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: () => _goTo(addDays(_day, -1)),
            icon: const Icon(Icons.chevron_left),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_day == today ? l.today.toUpperCase() : DateFormat.EEEE(locale).format(_day).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6)),
            Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: _day.isBefore(today) ? () => _goTo(addDays(_day, 1)) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          if (_day != today) TextButton(onPressed: () => _goTo(today), child: Text(l.journalBackToToday)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (final d in days)
            Builder(builder: (context) {
              final weekend = d.weekday > DateTime.friday;
              final m = minutesOn(d);
              final pct = target == 0 ? 0.0 : (m / target).clamp(0.0, 1.0);
              final selected = d == _day;
              return Semantics(
                button: true,
                label: l.journalDayRing(DateFormat.MMMMEEEEd(locale).format(d), (pct * 100).round()),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: d.isAfter(today) ? null : () => _goTo(d),
                  child: Container(
                    width: 46,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: selected ? theme.colorScheme.surfaceContainerHighest : null,
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(
                            value: weekend && m == 0 ? 0 : pct,
                            strokeWidth: 3,
                            backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                            color: pct >= 1 ? Colors.green.shade700 : theme.colorScheme.onSurface,
                          ),
                          Text('${d.day}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(height: 2),
                      ExcludeSemantics(
                        child: Text(DateFormat.E(locale).format(d),
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------------ bandeau d'état
  Widget _hero(BuildContext context,
      {required DayPlan plan,
      required List<_Block> drafts,
      required List<Span> gaps,
      required int loggedMin,
      required int draftMin,
      required VoidCallback onConfirmAll,
      required VoidCallback onReview}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final String title;
    final String text;
    final IconData icon;
    final Color tint;
    if (drafts.isNotEmpty) {
      title = l.journalHeroPending;
      text = l.journalHeroPendingText(formatHm((loggedMin + draftMin) * 60), formatHm(draftMin * 60), drafts.length);
      icon = Icons.auto_awesome;
      tint = theme.colorScheme.tertiaryContainer;
    } else if (gaps.isNotEmpty) {
      title = l.journalHeroGaps;
      text = l.journalHeroGapsText;
      icon = Icons.more_time;
      tint = theme.colorScheme.secondaryContainer;
    } else if (plan.windows.isEmpty) {
      title = l.journalHeroNothing;
      text = l.journalHeroNothingText(formatHm(loggedMin * 60));
      icon = Icons.event_available;
      tint = theme.colorScheme.surfaceContainerHighest;
    } else {
      title = l.journalHeroDone;
      text = l.journalHeroDoneText(formatHm(loggedMin * 60));
      icon = Icons.check_circle;
      tint = Colors.green.withValues(alpha: 0.15);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  Text(text, style: theme.textTheme.bodyMedium),
                ]),
              ),
            ]),
            if (drafts.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: onReview, child: Text(l.journalReviewOne)),
                FilledButton(onPressed: onConfirmAll, child: Text(l.journalConfirmAll(drafts.length))),
              ]),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ frise
  Widget _timeline(BuildContext context,
      {required CatalogController catalog,
      required Span range,
      required List<_Block> blocks,
      required List<Span> gaps,
      required List<(TimeEntry, Span)> claude,
      required bool isToday,
      required int nowMin,
      required Future<void> Function(_Block, Span) commitSpan}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    const labelWidth = 84.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth - labelWidth - 12;
          double x(int m) => (m - range.start) / range.length * width;
          int minuteAt(double dx) => ((range.start + dx / width * range.length) / 5).round() * 5;
          int deltaMinutes(double dx) => (dx / width * range.length / 5).round() * 5;
          final hours = [for (var h = range.start ~/ 60; h <= range.end ~/ 60; h++) h];

          Widget lane({required double height, required List<Widget> children, GestureDragStartCallback? onStart,
              GestureDragUpdateCallback? onUpdate, GestureDragEndCallback? onEnd, GestureTapUpCallback? onTap}) {
            return SizedBox(
              width: width,
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: onStart,
                onHorizontalDragUpdate: onUpdate,
                onHorizontalDragEnd: onEnd,
                onTapUp: onTap,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: CustomPaint(painter: _GridPainter(hours: [for (final h in hours) x(h * 60)], color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)))),
                  ...children,
                  if (isToday && nowMin > range.start && nowMin < range.end)
                    Positioned(left: x(nowMin) - 1, top: -4, bottom: -4, child: Container(width: 2, color: theme.colorScheme.primary)),
                ]),
              ),
            );
          }

          Widget blockView(_Block b) {
            final p = catalog.project(b.projectId);
            final color = p == null ? theme.colorScheme.outline : colorFromHex(p.color);
            final selected = b.id == _sel;
            final left = x(b.span.start);
            final w = math.max(6.0, x(b.span.end) - left);
            final draft = b.kind != _Kind.logged;
            final title = b.title.isEmpty ? (p?.name ?? l.noDescription) : b.title;
            final semantic = '$title, ${hm(b.span.start)} – ${hm(b.span.end)}, '
                '${b.kind == _Kind.draft ? l.journalProposed : (b.kind == _Kind.fresh ? l.journalNew : (b.running ? l.journalRunning : l.journalLogged))}';

            void startDrag(_Drag mode, DragStartDetails d) {
              _focus.requestFocus();
              setState(() {
                _sel = b.id;
                _drag = mode;
                _dragOrigin = b.span;
                _dragDx = d.globalPosition.dx;
              });
            }

            void updateDrag(DragUpdateDetails d) {
              final o = _dragOrigin;
              if (o == null) return;
              final dm = deltaMinutes(d.globalPosition.dx - _dragDx);
              final Span sp = switch (_drag) {
                _Drag.left => Span(math.min(o.start + dm, o.end - 10), o.end),
                _Drag.right => Span(o.start, math.max(o.end + dm, o.start + 10)),
                _ => Span(o.start + dm, o.end + dm),
              };
              final clamped = Span(math.max(0, sp.start), math.min(1440, sp.end));
              setState(() {
                if (b.kind == _Kind.draft) {
                  _edits[b.draft!.key] = (_edits[b.draft!.key] ?? const _DraftEdit()).copyWith(span: clamped);
                } else if (b.kind == _Kind.fresh) {
                  _fresh = clamped;
                } else {
                  _override[b.id] = clamped;
                }
              });
            }

            void endDrag(DragEndDetails _) {
              final sp = b.kind == _Kind.logged ? _override[b.id] : null;
              setState(() {
                _drag = null;
                _dragOrigin = null;
              });
              if (sp != null && sp != _dragOrigin) commitSpan(b, sp);
            }

            Widget handle(_Drag side) => Positioned(
                  left: side == _Drag.left ? -6 : null,
                  right: side == _Drag.right ? -6 : null,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onHorizontalDragStart: (d) => startDrag(side, d),
                      onHorizontalDragUpdate: updateDrag,
                      onHorizontalDragEnd: endDrag,
                      child: Center(
                        child: Container(width: 4, height: 24, decoration: BoxDecoration(color: theme.colorScheme.onSurface, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
                );

            return Positioned(
              left: left,
              width: w,
              top: 8,
              bottom: 8,
              child: Tooltip(
                message: semantic,
                excludeFromSemantics: true,
                waitDuration: const Duration(milliseconds: 400),
                child: Semantics(
                button: true,
                selected: selected,
                label: semantic,
                child: MouseRegion(
                  cursor: b.movable ? SystemMouseCursors.grab : SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onTap: () {
                      _focus.requestFocus();
                      setState(() => _sel = b.id);
                    },
                    onHorizontalDragStart: b.movable ? (d) => startDrag(_Drag.move, d) : (_) {},
                    onHorizontalDragUpdate: b.movable ? updateDrag : (_) {},
                    onHorizontalDragEnd: b.movable ? endDrag : (_) {},
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BlockPainter(
                            fill: color.withValues(alpha: draft ? 0.10 : 0.18),
                            border: color.withValues(alpha: draft ? 0.9 : 0.55),
                            dashed: draft,
                            selected: selected ? theme.colorScheme.primary : null,
                            runningEdge: b.running ? color : null,
                          ),
                        ),
                      ),
                      if (w >= 44)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: ExcludeSemantics(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const Spacer(),
                              Row(children: [
                                if (b.kind == _Kind.draft) ...[
                                  Icon(Icons.auto_awesome, size: 11, color: theme.colorScheme.tertiary),
                                  const SizedBox(width: 3),
                                ],
                                Flexible(
                                  child: Text(formatHm(b.span.length * 60), maxLines: 1,
                                      style: theme.textTheme.labelSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                      if (selected && b.movable) ...[handle(_Drag.left), handle(_Drag.right)],
                    ]),
                  ),
                ),
              ),
              ),
            );
          }

          final ruler = SizedBox(
            width: width,
            height: 18,
            child: Stack(clipBehavior: Clip.none, children: [
              for (final h in hours)
                Positioned(
                  left: (x(h * 60) - 18).clamp(0.0, math.max(0.0, width - 36)),
                  width: 36,
                  child: Text('${h.toString().padLeft(2, '0')}:00', textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
            ]),
          );

          final mineLane = lane(
            height: 92,
            onStart: (d) {
              _focus.requestFocus();
              final m = minuteAt(d.localPosition.dx);
              setState(() {
                _anchor = m;
                _drag = _Drag.create;
                _fresh = Span(m, math.min(1440, m + 15));
                _freshTitle = '';
                _freshProject = null;
                _freshTask = null;
                _sel = 'new';
              });
            },
            onUpdate: (d) {
              if (_drag != _Drag.create) return;
              final m = minuteAt(d.localPosition.dx);
              var s = math.min(_anchor, m), e = math.max(_anchor, m);
              if (e - s < 15) e = s + 15;
              setState(() => _fresh = Span(math.max(0, s), math.min(1440, e)));
            },
            onEnd: (_) => setState(() => _drag = null),
            onTap: (_) => setState(() => _sel = null),
            children: [
              for (final g in gaps)
                Positioned(
                  left: x(g.start),
                  width: x(g.end) - x(g.start),
                  top: 10,
                  bottom: 10,
                  child: Semantics(
                    button: true,
                    label: '${l.journalToFill(formatHm(g.length * 60))}, ${hm(g.start)} – ${hm(g.end)}',
                    child: InkWell(
                      onTap: () {
                        _focus.requestFocus();
                        setState(() {
                          _fresh = g;
                          _freshTitle = '';
                          _freshProject = null;
                          _freshTask = null;
                          _sel = 'new';
                        });
                      },
                      child: CustomPaint(
                        painter: _BlockPainter(fill: Colors.transparent, border: theme.colorScheme.outline, dashed: true, hatch: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
                        child: Center(
                          child: ExcludeSemantics(
                            child: Text(x(g.end) - x(g.start) > 70 ? l.journalToFill(formatHm(g.length * 60)) : '',
                                maxLines: 1, overflow: TextOverflow.clip, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final b in blocks) blockView(b),
            ],
          );

          final claudeLane = lane(
            height: 64,
            children: [
              for (final (e, sp) in claude)
                Positioned(
                  left: x(sp.start),
                  width: math.max(6.0, x(sp.end) - x(sp.start)),
                  top: 8,
                  bottom: 8,
                  child: Tooltip(
                    message: 'Claude : ${e.description}, ${hm(sp.start)} – ${hm(sp.end)}',
                    excludeFromSemantics: true,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Semantics(
                    button: true,
                    label: 'Claude : ${e.description}, ${hm(sp.start)} – ${hm(sp.end)}',
                    child: InkWell(
                      onTap: () => showEntryDialog(context, entry: e),
                      child: CustomPaint(
                        painter: _BlockPainter(
                          fill: theme.colorScheme.surface,
                          border: _projectColor(catalog, e.projectId, theme).withValues(alpha: 0.6),
                          hatch: _projectColor(catalog, e.projectId, theme).withValues(alpha: 0.22),
                        ),
                        child: x(sp.end) - x(sp.start) < 44
                            ? const SizedBox.expand()
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: ExcludeSemantics(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(formatHm(sp.length * 60), style: theme.textTheme.labelSmall),
                                  ]),
                                ),
                              ),
                      ),
                    ),
                  ),
                  ),
                ),
            ],
          );

          Widget row(Widget label, Widget content) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  SizedBox(width: labelWidth, child: label),
                  const SizedBox(width: 12),
                  content,
                ]),
              );

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const SizedBox(width: labelWidth + 12), ruler]),
            row(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.journalYou, style: theme.textTheme.titleSmall),
              ]),
              mineLane,
            ),
            if (claude.isNotEmpty)
              row(
                Row(children: [
                  Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Text('Claude', style: theme.textTheme.titleSmall),
                ]),
                claudeLane,
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: labelWidth + 12),
              child: Text(l.journalHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ),
          ]);
        }),
      ),
    );
  }

  Color _projectColor(CatalogController catalog, String? projectId, ThemeData theme) {
    final p = catalog.project(projectId);
    return p == null ? theme.colorScheme.outline : colorFromHex(p.color);
  }

  // ------------------------------------------------------------------ panneau du bloc choisi
  Widget _inspector(BuildContext context,
      {required CatalogController catalog,
      required _Block? b,
      required Future<void> Function(_Block) onConfirm,
      required Future<void> Function(_Block) onDismiss,
      required Future<void> Function() onSaveFresh}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (b == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.touch_app_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(l.journalSelectHint, style: theme.textTheme.bodyMedium)),
          ]),
        ),
      );
    }
    final badge = switch (b.kind) {
      _Kind.draft => l.journalProposed,
      _Kind.fresh => l.journalNew,
      _Kind.logged => b.running ? l.journalRunning : l.journalLogged,
    };
    final source = switch (b.draft?.source) {
      DraftSource.claude => l.journalSourceClaude,
      DraftSource.habit => l.journalSourceHabit,
      DraftSource.planning => l.journalSourcePlanning,
      null => '',
    };
    final reasons = <String>[
      for (final r in b.draft?.reasons ?? const <DraftReason>[])
        switch (r.kind) {
          ReasonKind.claudeSession => l.journalReasonClaudeSession(hm(r.a), hm(r.b)),
          ReasonKind.claudePilot => l.journalReasonClaudePilot,
          ReasonKind.habitWeekday => l.journalReasonHabitWeekday(r.count, r.of, hm(r.a)),
          ReasonKind.habitDaily => l.journalReasonHabitDaily(r.count, r.of, hm(r.a)),
          ReasonKind.planned => l.journalReasonPlanned(formatHm(r.count * 60)),
          ReasonKind.alreadyLogged => l.journalReasonAlreadyLogged(formatHm(r.count * 60)),
        },
      if (b.kind == _Kind.fresh) l.journalReasonNew,
    ];
    final editable = b.kind != _Kind.logged;

    Future<void> pickProject() async {
      final pick = await showProjectPicker(context, projectId: b.projectId, taskId: b.taskId);
      if (pick == null || !mounted) return;
      setState(() {
        if (b.kind == _Kind.draft) {
          _edits[b.draft!.key] = (_edits[b.draft!.key] ?? const _DraftEdit())
              .copyWith(projectId: pick.projectId, taskId: pick.taskId, projectSet: true);
        } else {
          _freshProject = pick.projectId;
          _freshTask = pick.taskId;
        }
      });
    }

    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Chip(
          label: Text(badge),
          avatar: b.kind == _Kind.draft ? Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.tertiary) : null,
          visualDensity: VisualDensity.compact,
        ),
        if (source.isNotEmpty) Text(source, style: theme.textTheme.bodySmall),
        Text('${hm(b.span.start)} → ${hm(b.span.end)} · ${formatHm(b.span.length * 60)}',
            style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 10),
      if (editable)
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: l.description, hintText: l.journalDescriptionHint),
          onChanged: (v) => setState(() {
            if (b.kind == _Kind.draft) {
              _edits[b.draft!.key] = (_edits[b.draft!.key] ?? const _DraftEdit()).copyWith(title: v);
            } else {
              _freshTitle = v;
            }
          }),
          onSubmitted: (_) => b.kind == _Kind.draft ? onConfirm(b) : onSaveFresh(),
        )
      else
        Text(b.title.isEmpty ? l.noDescription : b.title, style: theme.textTheme.titleMedium),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: editable ? pickProject : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: b.projectId == null ? Text(l.selectProject) : ProjectLabel(projectId: b.projectId, taskId: b.taskId),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (b.kind == _Kind.draft) ...[
          FilledButton(onPressed: () => onConfirm(b), child: Text(l.journalConfirm)),
          OutlinedButton(onPressed: () => onDismiss(b), child: Text(l.journalIgnore)),
        ],
        if (b.kind == _Kind.fresh) ...[
          FilledButton(onPressed: onSaveFresh, child: Text(l.save)),
          OutlinedButton(onPressed: () => setState(() => _fresh = null), child: Text(l.cancel)),
        ],
        if (b.kind == _Kind.logged) OutlinedButton(onPressed: () => showEntryDialog(context, entry: b.entry), child: Text(l.journalEditEntry)),
      ]),
    ]);

    final why = reasons.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.journalWhy.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 5, color: theme.colorScheme.outline)),
                    Expanded(child: Text(r, style: theme.textTheme.bodySmall)),
                  ]),
                ),
              if (b.kind == _Kind.draft) ...[
                const SizedBox(height: 6),
                Text(l.journalPrivacy, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ]),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, c) {
          if (why == null) return details;
          if (c.maxWidth < 620) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, const SizedBox(height: 12), why]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: details),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: why),
          ]);
        }),
      ),
    );
  }

  // ------------------------------------------------------------------ bilan
  Widget _summary(BuildContext context, {required DayPlan plan, required int loggedMin, required int draftMin, required List<(TimeEntry, Span)> claude}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final target = plan.typical.target;
    final claudeMin = claude.fold(0, (a, c) => a + c.$2.length);
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
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
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
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
          const SizedBox(height: 10),
          Text(
            plan.typical.fromHistory
                ? l.journalTypicalDay(hm(plan.typical.start), hm(plan.typical.end))
                : l.journalTypicalDefault(hm(plan.typical.start), hm(plan.typical.end)),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ]),
      ),
    );
  }
}

/// Lignes des heures sur une piste de la frise.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.hours, required this.color});
  final List<double> hours;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(r, Paint()
      ..color = color
      ..style = PaintingStyle.stroke);
    for (final x in hours) {
      if (x <= 0 || x >= size.width) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.hours != hours || old.color != color;
}

/// Bloc de la frise : fond, bord plein ou pointillé, trame hachurée (Claude, créneau vide), contour de sélection.
class _BlockPainter extends CustomPainter {
  _BlockPainter({required this.fill, required this.border, this.dashed = false, this.hatch, this.selected, this.runningEdge});
  final Color fill;
  final Color border;
  final bool dashed;
  final Color? hatch;
  final Color? selected;
  final Color? runningEdge;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawRRect(rrect, Paint()..color = fill);
    if (hatch != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      final hp = Paint()
        ..color = hatch!
        ..strokeWidth = 3;
      for (double x = -size.height; x < size.width; x += 9) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
      }
      canvas.restore();
    }
    final bp = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.5 : 1;
    if (dashed) {
      final path = Path()..addRRect(rrect.deflate(0.75));
      for (final metric in path.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 9) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), bp);
        }
      }
    } else {
      canvas.drawRRect(rrect.deflate(0.5), bp);
    }
    if (runningEdge != null) {
      final ep = Paint()
        ..color = runningEdge!
        ..strokeWidth = 2;
      for (double y = 4; y < size.height - 4; y += 7) {
        canvas.drawLine(Offset(size.width - 1, y), Offset(size.width - 1, math.min(y + 4, size.height - 4)), ep);
      }
    }
    if (selected != null) {
      canvas.drawRRect(
          rrect.inflate(1.5),
          Paint()
            ..color = selected!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_BlockPainter old) =>
      old.fill != fill || old.border != border || old.dashed != dashed || old.hatch != hatch || old.selected != selected || old.runningEdge != runningEdge;
}
