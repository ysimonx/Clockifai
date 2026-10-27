import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/dictation.dart';
import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/text_search.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../presence/presence.dart' show PresenceTracker;
import '../time_entries/entry_dialog.dart';
import '../timesheet/week_tools.dart' show copyDay;
import 'day_plan.dart';
import 'quick_place.dart';
import 'traces.dart';

/// « Aujourd'hui », le journal automatique (plans/13-ux-moderne.md, lot 11) : la journée sur une frise, les entrées
/// saisies, les créneaux vides et les propositions tirées des habitudes, du planning et des sessions de Claude, à
/// confirmer d'un geste. Glisser sur le vide crée un bloc ; tirer un bloc ou ses bords l'ajuste.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.clock = DateTime.now, this.initialDay});

  /// Jour affiché à l'ouverture (lien « Voir la journée », `/today?day=2026-10-23`) ; par défaut aujourd'hui.
  final DateTime? initialDay;

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
  late DateTime _day = _midnight(widget.initialDay ?? widget.clock());
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

  // Traces (agenda, commits) du jour affiché ; relues toutes les 5 minutes pour aujourd'hui.
  DayTraces _traces = DayTraces.empty;
  String? _tracesKey;

  void _ensureTraces(String ws, DateTime now) {
    final key = '$ws ${dayKey(_day)} ${_day == _midnight(now) ? now.minute ~/ 5 + now.hour * 12 : ''}';
    if (key == _tracesKey) return;
    final sameDay = _tracesKey?.startsWith('$ws ${dayKey(_day)} ') ?? false;
    _tracesKey = key;
    if (!sameDay) _traces = DayTraces.empty;
    TracesApi.day(ws, _day).then((t) {
      if (mounted && _tracesKey == key) setState(() => _traces = t);
    }, onError: (Object _) {}); // hors ligne, ou serveur injoignable : la journée se propose sans traces
  }

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
    PresenceTracker.instance.log.addListener(_onPresence);
  }

  /// Arrivée ou départ noté par le téléphone (lot 13) : la journée se recalcule.
  void _onPresence() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    PresenceTracker.instance.log.removeListener(_onPresence);
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
    _ensureTraces(ws, widget.clock());
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
    final typical = TypicalDay.ofProfile(context.read<SessionController>().profile);
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
      typical: typical,
      calendar: _traces.events,
      commits: _traces.commits,
      presence: [for (final v in PresenceTracker.instance.log.value.visitsOn(_day)) if (catalog.project(v.projectId) != null) v],
      presenceRounding: context.read<SessionController>().workspace?.presenceRounding,
      guessProject: (text) {
        final q = parseQuick(text, catalog, now);
        return q?.projectId == null ? null : (projectId: q!.projectId, taskId: q.taskId);
      },
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
    final traceSpans = [for (final ev in _traces.events) if (_traceSpan(ev.start, ev.end) case final sp?) (ev, sp)];
    final commitMinutes = [for (final c in _traces.commits) (c, minuteOf(c.at, _day))];
    final starts = [420, for (final w in plan.windows) w.start, for (final b in blocks) b.span.start, for (final c in claudeSpans) c.$2.start,
      for (final t in traceSpans) t.$2.start, for (final c in commitMinutes) if (c.$2 >= 0) c.$2 - 15];
    final ends = [1140, for (final w in plan.windows) w.end, for (final b in blocks) b.span.end, for (final c in claudeSpans) c.$2.end,
      for (final t in traceSpans) t.$2.end, for (final c in commitMinutes) if (c.$2 < 1440) c.$2 + 15];
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

    // Journée vide : « Comme vendredi » recopie la dernière journée travaillée (lot 9).
    final copyFrom = mineRows.isEmpty && !_day.isAfter(_midnight(now)) ? lastWorkedDay(history, _day) : null;
    final copyRows = copyFrom == null
        ? const <TimeEntry>[]
        : ([for (final r in rows) if (_midnight(r.entry.startAt.toLocal()) == copyFrom && r.entry.endAt != null) r.entry]
          ..sort((a, b) => a.startAt.compareTo(b.startAt)));
    final planned = drafts.where((d) => d.draft?.source == DraftSource.planning).toList();
    final quick = _quickEntry(context,
        catalog: catalog, rows: rows, proposed: [for (final b in blocks) if (b.kind != _Kind.logged) b.span], now: now, me: me, ws: ws);
    Widget? start(bool phone) => copyFrom == null
        ? null
        : _startCard(context,
            catalog: catalog,
            from: copyFrom,
            entries: copyRows,
            now: now,
            onCopy: () => copyDay(context, userId: me, from: copyFrom, to: _day),
            onPlanned: planned.isEmpty ? null : () => confirmDrafts(planned),
            onOther: phone ? () => showEntryDialog(context) : () => _quickFocus.requestFocus());
    final toComplete = _toComplete(context,
        catalog: catalog,
        plan: plan,
        drafts: drafts,
        gaps: gaps,
        loggedMin: loggedMin,
        draftMin: draftMin,
        onConfirm: (b) => confirmDrafts([b]),
        onConfirmAll: () => confirmDrafts(drafts),
        onReview: () => setState(() => _sel = drafts.firstOrNull?.id),
        onFill: (g) {
          _focus.requestFocus();
          setState(() {
            _fresh = g;
            _freshTitle = '';
            _freshProject = null;
            _freshTask = null;
            _sel = 'new';
          });
        });
    final timeline = Focus(
      focusNode: _focus,
      onKeyEvent: onKey,
      child: _timeline(
        context,
        catalog: catalog,
        range: range,
        blocks: blocks,
        gaps: gaps,
        claude: claudeSpans,
        events: traceSpans,
        commits: [for (final c in commitMinutes) if (c.$2 >= 0 && c.$2 < 1440) c],
        isToday: _day == _midnight(now),
        nowMin: minuteOf(now, _day),
        commitSpan: commitSpan,
      ),
    );
    final inspector = selected == null
        ? null
        : _inspector(context, catalog: catalog, b: selected, onConfirm: (b) => confirmDrafts([b]), onDismiss: dismiss, onSaveFresh: saveFresh);
    final summary = _summary(context, catalog: catalog, plan: plan, mine: mineRows, loggedMin: loggedMin, draftMin: draftMin, claude: claudeSpans);
    const gap = SizedBox(height: 16);

    return LayoutBuilder(builder: (context, c) {
      final phone = c.maxWidth < 600;
      final wide = c.maxWidth >= 980;
      final List<Widget> children;
      if (wide) {
        // Ordinateur (maquette « Aujourd'hui ») : la frise à gauche, ce qui reste à faire et le bilan à droite.
        children = [
          _header(context, rows: rows, target: plan.typical.target, now: now),
          gap,
          quick,
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [timeline, if (inspector != null) ...[gap, inspector]]),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 360,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Journée vide à reprendre : « Rien à proposer » n'ajouterait rien.
                if (copyFrom != null) ...[start(false)!, gap],
                if (copyFrom == null || drafts.isNotEmpty || gaps.isNotEmpty) ...[toComplete, gap],
                summary,
              ]),
            ),
          ]),
        ];
      } else if (phone) {
        // Téléphone (maquette « la journée en un geste ») : reprendre une journée d'un bouton, puis la liste du jour.
        children = [
          _header(context, rows: rows, target: plan.typical.target, now: now, compact: true),
          gap,
          if (copyFrom != null) ...[start(true)!, gap],
          if (drafts.isNotEmpty) ...[toComplete, gap],
          if (mineRows.isNotEmpty) ...[_dayList(context, mineRows, now), gap],
          quick,
          gap,
          timeline,
          if (inspector != null) ...[gap, inspector],
          gap,
          summary,
        ];
      } else {
        children = [
          _header(context, rows: rows, target: plan.typical.target, now: now),
          gap,
          if (copyFrom != null) ...[start(false)!, gap],
          quick,
          gap,
          timeline,
          if (inspector != null) ...[gap, inspector],
          gap,
          toComplete,
          gap,
          summary,
        ];
      }
      return ListView(
        padding: EdgeInsets.fromLTRB(phone ? 16 : 24, phone ? 12 : 8, phone ? 16 : 24, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ...children,
                if (loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
              ]),
            ),
          ),
        ],
      );
    });
  }

  // ------------------------------------------------------------------ saisie express (lot 3)
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
    final q = parseQuick(_quick.text, catalog, now);
    final slot = q == null
        ? null
        : placeQuick(q,
            now: now,
            entries: [for (final r in rows) r.entry],
            typical: TypicalDay.ofProfile(context.read<SessionController>().profile),
            proposedOn: (day) => day == _day ? proposed : const []);
    final ready = q != null && q.isComplete && slot != null;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final project = catalog.project(q?.projectId);
    final task = catalog.task(q?.taskId);

    Future<void> save() async {
      if (!ready) return;
      final added = quickAddedMessage(context, q, slot, catalog, now);
      final id = await saveQuick(q, slot, catalog: catalog, workspaceId: ws, userId: me);
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
      // Un nœud d'accessibilité par champ et par bouton, pas toute la carte fondue en un seul.
      semanticContainer: false,
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
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400, fontSize: phone ? 16 : 18),
                  decoration: InputDecoration(
                    labelText: l.quickEntry,
                    hintText: l.quickEntryHint,
                    prefixIcon: const Icon(Icons.add),
                    suffixIcon: Dictation.supported ? _dictateButton(context) : null,
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => save(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: ready ? save : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.save),
                if (!phone) ...[const SizedBox(width: 8), Text('⏎', style: TextStyle(fontFamily: monoFont, color: ready ? null : theme.disabledColor))],
              ]),
            ),
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
          if (!phone) ...[
            const SizedBox(height: 6),
            Text(l.quickEntryHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ]),
      ),
    );
  }

  /// Micro de la saisie express (lot 9) : la phrase dite remplit le champ, analysée comme si elle était tapée.
  Widget _dictateButton(BuildContext context) {
    final l = context.l10n;
    final dictation = Dictation.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: dictation.listening,
      builder: (context, listening, _) => IconButton(
        tooltip: listening ? l.dictationStop : l.dictate,
        icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Theme.of(context).colorScheme.error : null),
        onPressed: () async {
          if (listening) return dictation.stop();
          final ok = await dictation.start(context.localeTag, (text, done) {
            if (!mounted) return;
            setState(() {
              _quick.text = text;
              _quick.selection = TextSelection.collapsed(offset: text.length);
            });
            if (done) _quickFocus.requestFocus();
          });
          if (!ok && context.mounted) showSnack(context, l.dictationUnavailable);
        },
      ),
    );
  }

  // ------------------------------------------------------------------ en-tête : jour et semaine en anneaux
  Widget _header(BuildContext context, {required List<EntryRow> rows, required int target, required DateTime now, bool compact = false}) {
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
            Text(title, style: (compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)?.copyWith(fontWeight: FontWeight.w600)),
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
                            color: pct >= 1 ? AppColors.of(context).success : theme.colorScheme.onSurface,
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

  // ------------------------------------------------------------------ à compléter (maquette « Aujourd'hui »)
  Widget _label(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6, fontWeight: FontWeight.w600));
  }

  TextStyle? _mono(BuildContext context, {bool muted = true}) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
        fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()], color: muted ? theme.colorScheme.outline : null);
  }

  /// Ce qui reste à faire : les propositions à confirmer (une à une ou d'un geste), sinon les créneaux vides à
  /// remplir, sinon « Journée complète ».
  Widget _toComplete(BuildContext context,
      {required CatalogController catalog,
      required DayPlan plan,
      required List<_Block> drafts,
      required List<Span> gaps,
      required int loggedMin,
      required int draftMin,
      required Future<void> Function(_Block) onConfirm,
      required VoidCallback onConfirmAll,
      required VoidCallback onReview,
      required void Function(Span) onFill}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    if (drafts.isEmpty && gaps.isEmpty) {
      final done = plan.windows.isNotEmpty;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: done ? colors.successContainer : theme.colorScheme.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(done ? Icons.check : Icons.event_available, color: done ? colors.success : theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done ? l.journalHeroDone : l.journalHeroNothing, style: theme.textTheme.titleMedium),
                Text(done ? l.journalHeroDoneText(formatHm(loggedMin * 60)) : l.journalHeroNothingText(formatHm(loggedMin * 60)),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      );
    }
    final List<Widget> lines;
    if (drafts.isNotEmpty) {
      lines = [
        Text(l.journalHeroPending, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(l.journalHeroPendingText(formatHm((loggedMin + draftMin) * 60), formatHm(draftMin * 60), drafts.length),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final b in drafts) ...[
          const Divider(height: 17),
          InkWell(
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: () {
              _focus.requestFocus();
              setState(() => _sel = b.id);
            },
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, children: [
                    Text(_sourceLabel(l, b.draft?.source), style: theme.textTheme.labelSmall?.copyWith(color: colors.link, fontWeight: FontWeight.w600)),
                    Text('${hm(b.span.start)} – ${hm(b.span.end)}', style: _mono(context)),
                  ]),
                  const SizedBox(height: 2),
                  Text(b.title.isEmpty ? (catalog.project(b.projectId)?.name ?? l.noDescription) : b.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (b.projectId != null) ProjectLabel(projectId: b.projectId, taskId: b.taskId, dense: true),
                ]),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => onConfirm(b), child: Text(l.add)),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton(onPressed: onReview, child: Text(l.journalReviewOne)),
          FilledButton(onPressed: onConfirmAll, child: Text(l.journalConfirmAll(drafts.length))),
        ]),
      ];
    } else {
      lines = [
        Text(l.journalHeroGaps, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(l.journalHeroGapsText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (final g in gaps.take(5)) ...[
          const Divider(height: 17),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.journalToFill(formatHm(g.length * 60)), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('${hm(g.start)} – ${hm(g.end)}', style: _mono(context)),
              ]),
            ),
            OutlinedButton(onPressed: () => onFill(g), child: Text(l.journalFill)),
          ]),
        ],
      ];
    }
    return Card(
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label(context, l.journalToComplete),
          const SizedBox(height: 6),
          ...lines,
        ]),
      ),
    );
  }

  /// Journée vide : « Comme vendredi ? », la journée à reprendre et un bouton pour la reprendre d'un geste
  /// (maquette « Téléphone : la journée en un geste »).
  Widget _startCard(BuildContext context,
      {required CatalogController catalog,
      required DateTime from,
      required List<TimeEntry> entries,
      required DateTime now,
      required VoidCallback onCopy,
      required VoidCallback onOther,
      VoidCallback? onPlanned}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final total = entries.fold(0, (a, e) => a + e.endAt!.difference(e.startAt).inMinutes);
    return Card(
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_day == _midnight(now) ? l.journalNothingToday : l.journalNothingThatDay,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          Text(l.likeDayQuestion(_likeDay(context, from, now)), style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final e in entries.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                ColorDot(catalog.project(e.projectId)?.color ?? '#9AA3B2', size: 9),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.description.isEmpty ? (catalog.project(e.projectId)?.name ?? l.noDescription) : e.description,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('${hm(minuteOf(e.startAt, from))}–${hm(minuteOf(e.endAt!, from))}', style: _mono(context)),
              ]),
            ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: theme.textTheme.titleMedium),
            onPressed: onCopy,
            child: Text(l.resumeDay(formatHm(total * 60))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (onPlanned != null) ...[
              Expanded(child: OutlinedButton(onPressed: onPlanned, child: Text(l.journalFromPlanning))),
              const SizedBox(width: 8),
            ],
            Expanded(child: OutlinedButton(onPressed: onOther, child: Text(l.journalSomethingElse))),
          ]),
        ]),
      ),
    );
  }

  /// Téléphone : les entrées du jour, à toucher pour les modifier.
  Widget _dayList(BuildContext context, List<EntryRow> rows, DateTime now) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final sorted = [...rows]..sort((a, b) => a.entry.startAt.compareTo(b.entry.startAt));
    final total = sorted.fold(0, (a, r) => a + (r.entry.endAt ?? now.toUtc()).difference(r.entry.startAt).inMinutes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Row(children: [
          Expanded(child: Text(l.journalYourDay, style: theme.textTheme.titleSmall)),
          Text(formatHm(total * 60), style: _mono(context, muted: false)),
        ]),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, r) in sorted.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              minTileHeight: 64,
              leading: ColorDot(catalog.project(r.entry.projectId)?.color ?? '#9AA3B2', size: 9),
              minLeadingWidth: 12,
              title: Text(r.entry.description.isEmpty ? (catalog.project(r.entry.projectId)?.name ?? l.noDescription) : r.entry.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${hm(minuteOf(r.entry.startAt, _day))} – ${r.entry.endAt == null ? '…' : hm(minuteOf(r.entry.endAt!, _day))}'),
              trailing: Text(formatHm((r.entry.endAt ?? now.toUtc()).difference(r.entry.startAt).inSeconds),
                  style: theme.textTheme.titleSmall?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
              onTap: () => showEntryDialog(context, entry: r.entry),
            ),
          ],
        ]),
      ),
    ]);
  }

  /// « Comme hier », « Comme vendredi » (la semaine écoulée), sinon « Comme le 12 oct. ».
  String _likeDay(BuildContext context, DateTime day, DateTime now) {
    final l = context.l10n;
    final locale = context.localeTag;
    if (_day == _midnight(now) && day == addDays(_day, -1)) return l.likeYesterday;
    if (!day.isBefore(addDays(_day, -6))) return l.likeDay(DateFormat.EEEE(locale).format(day));
    return l.likeDate(DateFormat.MMMd(locale).format(day));
  }

  // ------------------------------------------------------------------ frise
  Widget _timeline(BuildContext context,
      {required CatalogController catalog,
      required Span range,
      required List<_Block> blocks,
      required List<Span> gaps,
      required List<(TimeEntry, Span)> claude,
      required List<(CalendarEvent, Span)> events,
      required List<(CommitTrace, int)> commits,
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
                                      style: theme.textTheme.labelSmall?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
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

          // Une heure sur deux, ou sur trois, quand la place manque (téléphone) : jamais d'étiquettes qui se chevauchent.
          final perHour = hours.length < 2 ? width : x(60) - x(0);
          final labelEvery = perHour >= 48 ? 1 : (perHour >= 24 ? 2 : (perHour >= 16 ? 3 : 4));
          final ruler = SizedBox(
            width: width,
            height: 18,
            child: Stack(clipBehavior: Clip.none, children: [
              for (final h in hours)
                if (h % labelEvery == 0)
                  Positioned(
                    left: (x(h * 60) - 21).clamp(0.0, math.max(0.0, width - 42)),
                    width: 42,
                    child: Text('${h.toString().padLeft(2, '0')}:00', textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
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

          // Traces : événements de l'agenda (bord fin) et commits (points), d'où viennent certaines propositions.
          final tracesLane = lane(
            height: 46,
            children: [
              for (final (ev, sp) in events)
                Positioned(
                  left: x(sp.start),
                  width: math.max(6.0, x(sp.end) - x(sp.start)),
                  top: 6,
                  bottom: 6,
                  child: Tooltip(
                    message: '${ev.title}, ${hm(sp.start)} – ${hm(sp.end)}',
                    child: CustomPaint(
                      painter: _BlockPainter(fill: theme.colorScheme.surface, border: theme.colorScheme.outline.withValues(alpha: 0.7)),
                      child: x(sp.end) - x(sp.start) < 40
                          ? const SizedBox.expand()
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ExcludeSemantics(
                                  child: Text(ev.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              for (final (c, m) in commits)
                Positioned(
                  left: x(m) - 6,
                  top: 17,
                  width: 12,
                  height: 12,
                  child: Tooltip(
                    message: '${c.subject} — ${c.repository}, ${hm(m)}',
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.tertiaryContainer,
                        border: Border.all(color: theme.colorScheme.tertiary, width: 2),
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
                  Flexible(child: Text('Claude', overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                ]),
                claudeLane,
              ),
            if (events.isNotEmpty || commits.isNotEmpty)
              row(
                Row(children: [
                  Icon(Icons.event_note_outlined, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Flexible(child: Text(l.journalTraces, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                ]),
                tracesLane,
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

  /// Plage d'un événement dans le jour affiché (minutes), ou null s'il n'y tombe pas.
  Span? _traceSpan(DateTime start, DateTime end) {
    final s = math.max(0, minuteOf(start, _day)), e = math.min(1440, minuteOf(end, _day));
    return e > s ? Span(s, e) : null;
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
    final source = _sourceLabel(l, b.draft?.source);
    final reasons = <String>[
      for (final r in b.draft?.reasons ?? const <DraftReason>[])
        switch (r.kind) {
          ReasonKind.presence => r.b < 0 ? l.journalReasonPresenceSince(hm(r.a)) : l.journalReasonPresence(hm(r.a), hm(r.b)),
          ReasonKind.presenceRounded => l.journalReasonPresenceRounded,
          ReasonKind.claudeSession => l.journalReasonClaudeSession(hm(r.a), hm(r.b)),
          ReasonKind.claudePilot => l.journalReasonClaudePilot,
          ReasonKind.calendar => l.journalReasonCalendar(hm(r.a), hm(r.b)),
          ReasonKind.commits => l.journalReasonCommits(r.count, r.text, hm(r.a), hm(r.b)),
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
            style: theme.textTheme.bodyMedium?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
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
      // Un nœud d'accessibilité par champ et par bouton, pas toute la carte fondue en un seul.
      semanticContainer: false,
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

  /// Bilan par projet : vos minutes et celles de Claude, côte à côte.
  List<Widget> _perProject(BuildContext context, CatalogController catalog, List<EntryRow> mine, List<(TimeEntry, Span)> claude) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final now = widget.clock();
    final me = <String?, int>{}, agent = <String?, int>{};
    for (final r in mine) {
      if (spanOf(r.entry, _day, now) case final sp?) me[r.entry.projectId] = (me[r.entry.projectId] ?? 0) + sp.length;
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

  // ------------------------------------------------------------------ bilan
  Widget _summary(BuildContext context,
      {required CatalogController catalog,
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
          ..._perProject(context, catalog, mine, claude),
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
}

/// D'où vient une proposition : « Habitude », « Agenda », « Chantier »…
String _sourceLabel(AppLocalizations l, DraftSource? source) => switch (source) {
      DraftSource.presence => l.journalSourcePresence,
      DraftSource.claude => l.journalSourceClaude,
      DraftSource.calendar => l.journalSourceCalendar,
      DraftSource.commits => l.journalSourceCommits,
      DraftSource.habit => l.journalSourceHabit,
      DraftSource.planning => l.journalSourcePlanning,
      null => '',
    };

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
