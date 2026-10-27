import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/dictation.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart' show Task;
import '../../data/repositories/time_entry_repository.dart';
import '../timer/timer_control.dart' show showStartTimer;
import '../timer/timer_rules.dart' show timerRuleViolation;
import '../today/day_plan.dart';
import 'duration_chips.dart';

/// « + » du téléphone (maquette « Téléphone : saisir sans clavier », plans/14-coller-aux-maquettes.md) : la durée au
/// pouce, le matin ou l'après-midi, le projet de la dernière entrée et ses tâches en pastilles, une description
/// facultative (dictée, ou reprise des dernières) ; « Enregistrer » ajoute l'entrée, avec Annuler.
Future<void> showQuickAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(outer: context),
    );

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key, required this.outer, this.clock = DateTime.now});

  /// Contexte de l'appelant, monté après la fermeture de la feuille (bandeau Annuler, chronomètre).
  final BuildContext outer;
  final DateTime Function() clock;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _description = TextEditingController();
  late DateTime _day;
  late TypicalDay _typical;
  late int _start;
  int _minutes = 180;
  String? _projectId;
  String? _taskId;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
    _day = DateTime(now.year, now.month, now.day);
    final session = context.read<SessionController>();
    _typical = TypicalDay.ofProfile(session.profile) ?? TypicalDay.fallback;
    final (morning, afternoon) = DurationChips(typical: _typical).halves;
    _start = minuteOf(now, _day) >= afternoon.start ? afternoon.start : morning.start;
    entriesRepo.watchRecent(session.workspaceId!, session.userId!, limit: 6).first.then((rows) {
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _projectId ??= rows.first.entry.projectId;
        _recent = {for (final r in rows) if (r.entry.description.isNotEmpty) r.entry.description}.take(3).toList();
      });
    });
  }

  @override
  void dispose() {
    _description.dispose();
    Dictation.instance.stop();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final blocked = timerRuleViolation(l, session.workspace!, description: _description.text, projectId: _projectId);
    if (blocked != null) return showSnack(context, blocked);
    final me = session.userId!;
    final start = atMinute(_day, _start), end = atMinute(_day, _start + _minutes);
    final id = await entriesRepo.createManual(
      workspaceId: session.workspaceId!,
      userId: me,
      start: start,
      end: end,
      createdBy: me,
      draft: EntryDraft(
        description: _description.text.trim(),
        projectId: _projectId,
        taskId: _taskId,
        billable: catalog.billableFor(projectId: _projectId, userId: me),
        hourlyRateCents: catalog.rateFor(projectId: _projectId, userId: me),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
    final outer = widget.outer;
    if (outer.mounted) {
      showUndo(outer, l.quickAddSaved(formatHm(_minutes * 60), '${hm(_start)} – ${hm(_start + _minutes)}'), () => entriesRepo.delete(id));
    }
  }

  Future<void> _pickProject() async {
    final pick = await showProjectPicker(context, projectId: _projectId, taskId: _taskId);
    if (pick == null || !mounted) return;
    setState(() {
      _projectId = pick.projectId;
      _taskId = pick.taskId;
    });
  }

  Future<void> _dictate() async {
    final dictation = Dictation.instance;
    if (dictation.listening.value) return dictation.stop();
    final ok = await dictation.start(context.localeTag, (text, _) {
      if (mounted) setState(() => _description.text = text);
    });
    if (!ok && mounted) showSnack(context, context.l10n.dictationUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final locale = context.localeTag;
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final (morning, afternoon) = DurationChips(typical: _typical).halves;
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: monoFont, fontFeatures: const [FontFeature.tabularFigures()]);
    final project = catalog.project(_projectId);
    final tasks = project == null ? const <Task>[] : catalog.tasksOf(project.id).take(8).toList();
    final root = catalog.rootTask(_taskId);
    final subtasks = root == null ? const <Task>[] : catalog.subtasksOf(root.id).take(8).toList();

    Widget round(IconData icon, String tooltip, VoidCallback onTap) => IconButton.outlined(
          tooltip: tooltip,
          iconSize: 26,
          style: IconButton.styleFrom(minimumSize: const Size(56, 56), side: BorderSide(color: theme.colorScheme.outlineVariant)),
          onPressed: onTap,
          icon: Icon(icon),
        );

    String dayLabel(DateTime d) => d == today
        ? l.today
        : d == addDays(today, -1)
            ? l.yesterday
            : toBeginningOfSentenceCase(DateFormat.MMMEd(locale).format(d));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.addTime, style: theme.textTheme.titleLarge)),
              PopupMenuButton<DateTime>(
                tooltip: l.date,
                initialValue: _day,
                onSelected: (d) => setState(() => _day = d),
                itemBuilder: (_) => [for (var i = 0; i < 7; i++) PopupMenuItem(value: addDays(today, -i), child: Text(dayLabel(addDays(today, -i))))],
                child: Chip(label: Text(dayLabel(_day)), avatar: const Icon(Icons.expand_more, size: 18)),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              round(Icons.remove, l.minus15, () => setState(() => _minutes = math.max(15, _minutes - 15))),
              Expanded(
                child: Column(children: [
                  Text(formatHm(_minutes * 60),
                      style: theme.textTheme.displaySmall?.copyWith(fontFamily: monoFont, fontWeight: FontWeight.w600, letterSpacing: -1)),
                  Text('${hm(_start)} → ${hm(math.min(1439, _start + _minutes))}', style: mono?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
              round(Icons.add, l.plus15, () => setState(() => _minutes = math.min(16 * 60, _minutes + 15))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              for (final m in [60, 120, 180, 270, _typical.target])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: m == _minutes
                        ? FilledButton(onPressed: () {}, style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)), child: Text(formatHm(m * 60), style: mono?.copyWith(color: theme.colorScheme.onPrimary)))
                        : OutlinedButton(
                            style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                            onPressed: () => setState(() {
                              _minutes = m;
                              if (m == _typical.target) _start = _typical.start;
                            }),
                            child: Text(formatHm(m * 60), style: mono),
                          ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: morning.start, label: Text('${l.morning} · ${hm(morning.start)}')),
                ButtonSegment(value: afternoon.start, label: Text('${l.afternoon} · ${hm(afternoon.start)}')),
              ],
              selected: {if (_start == morning.start || _start == afternoon.start) _start},
              emptySelectionAllowed: true,
              onSelectionChanged: (v) => setState(() => _start = v.isEmpty ? _start : v.single),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: project == null ? Text(l.noProject, style: TextStyle(color: theme.colorScheme.outline)) : ProjectLabel(projectId: project.id)),
              TextButton(onPressed: _pickProject, child: Text(project == null ? l.selectProject : l.change)),
            ]),
            if (tasks.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in tasks)
                  ChoiceChip(
                    label: Text(t.name),
                    selected: root?.id == t.id,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: TextStyle(color: root?.id == t.id ? theme.colorScheme.onPrimary : null),
                    showCheckmark: false,
                    onSelected: (v) => setState(() => _taskId = v ? t.id : null),
                  ),
              ]),
            // Sous-tâches de la tâche choisie (plans/16-sous-taches.md).
            if (subtasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Icon(Icons.subdirectory_arrow_right, size: 18, color: theme.colorScheme.outline),
                  for (final s in subtasks)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: _taskId == s.id,
                      selectedColor: theme.colorScheme.primary,
                      labelStyle: TextStyle(color: _taskId == s.id ? theme.colorScheme.onPrimary : null),
                      showCheckmark: false,
                      onSelected: (v) => setState(() => _taskId = v ? s.id : root!.id),
                    ),
                ]),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: l.descriptionOptional,
                suffixIcon: !Dictation.supported
                    ? null
                    : ValueListenableBuilder<bool>(
                        valueListenable: Dictation.instance.listening,
                        builder: (context, listening, _) => IconButton(
                          tooltip: listening ? l.dictationStop : l.dictate,
                          icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? theme.colorScheme.error : null),
                          onPressed: _dictate,
                        ),
                      ),
              ),
            ),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in _recent) ActionChip(label: Text(d), onPressed: () => setState(() => _description.text = d)),
              ]),
            ],
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: theme.textTheme.titleMedium),
              onPressed: _save,
              child: Text(l.saveDuration(formatHm(_minutes * 60))),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                if (widget.outer.mounted) showStartTimer(widget.outer);
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(l.cmdStartTimer),
            ),
          ]),
        ),
      ),
    );
  }
}
