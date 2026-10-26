import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/entry_dialog.dart';
import 'running_timer_row.dart';
import 'timer_notifications.dart';
import 'timer_rules.dart';

/// Barre « Sur quoi travaillez-vous ? » : démarre / arrête le chronomètre.
/// Le chronomètre est une entrée sans fin en base locale : il survit au redémarrage
/// de l'app, fonctionne hors ligne et apparaît sur les autres appareils après sync.
/// Si le workspace autorise plusieurs chronomètres simultanés, la barre reste un
/// formulaire de démarrage et chaque chronomètre en cours a sa ligne en dessous.
class TimerBar extends StatefulWidget {
  const TimerBar({super.key});

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar> {
  final _description = TextEditingController();
  final _focus = FocusNode();
  StreamSubscription<List<TimeEntry>>? _sub;
  String? _boundKey;
  List<TimeEntry> _runningAll = const [];
  bool _parallel = false;
  bool _expanded = false;
  // Chronomètre affiché dans la barre (null en mode simultané).
  TimeEntry? _running;
  List<String> _runningTags = const [];
  Timer? _debounce;

  // Brouillon quand rien ne tourne.
  String? _projectId;
  String? _taskId;
  List<String> _tagIds = const [];
  bool _billable = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final parallel = session.runningTimersLimit != 1;
    if (parallel != _parallel) {
      _parallel = parallel;
      if (_boundKey != null) Future.microtask(() => _onRunning(_runningAll));
    }
    final key = '${session.workspaceId}:${session.userId}';
    if (key == _boundKey || session.workspaceId == null || session.userId == null) return;
    _boundKey = key;
    _sub?.cancel();
    _sub = entriesRepo.watchRunningAll(session.workspaceId!, session.userId!).listen(_onRunning);
  }

  Future<void> _onRunning(List<TimeEntry> all) async {
    _runningAll = all;
    final entry = _parallel ? null : all.firstOrNull;
    final changed = entry?.id != _running?.id;
    _running = entry;
    if (entry != null) {
      _runningTags = await entriesRepo.tagIdsOf(entry.id);
      if (changed || !_focus.hasFocus) _description.text = entry.description;
    } else if (changed) {
      _description.clear();
    }
    if (!mounted) return;
    setState(() {});
    final catalog = context.read<CatalogController>();
    final l = context.l10n;
    final latest = all.firstOrNull;
    final subtitle = [
      ?catalog.project(latest?.projectId)?.name,
      if (all.length > 1) l.otherRunningTimers(all.length - 1),
    ].join(' · ');
    await TimerNotifications.instance.show(
      latest,
      title: latest == null ? null : (latest.description.isNotEmpty ? latest.description : l.noDescription),
      subtitle: subtitle.isEmpty ? null : subtitle,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _description.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    final l = context.l10n;
    final blocked = timerRuleViolation(l, ws, description: _description.text, projectId: _projectId) ??
        alreadyRunningViolation(l, _runningAll, description: _description.text, projectId: _projectId, taskId: _taskId);
    if (blocked != null) return showSnack(context, blocked);
    final limit = session.runningTimersLimit;
    final stopsOldest = limit > 1 && _runningAll.length >= limit;
    await entriesRepo.start(
      workspaceId: ws.id,
      userId: session.userId!,
      draft: EntryDraft(
        description: _description.text,
        projectId: _projectId,
        taskId: _taskId,
        billable: _billable,
        tagIds: _tagIds,
        hourlyRateCents: catalog.rateFor(projectId: _projectId, userId: session.userId!),
      ),
      maxRunning: limit,
    );
    if (!mounted) return;
    if (stopsOldest) showSnack(context, l.oldestTimerStopped);
    setState(() {
      _projectId = null;
      _taskId = null;
      _tagIds = const [];
      if (_parallel) _description.clear();
    });
  }

  Future<void> _stop() async {
    final running = _running;
    if (running == null) return;
    final ws = context.read<SessionController>().workspace!;
    final blocked = timerRuleViolation(context.l10n, ws, description: _description.text, projectId: running.projectId);
    if (blocked != null) return showSnack(context, blocked);
    _debounce?.cancel();
    if (_description.text.trim() != running.description) {
      await entriesRepo.update(running, description: _description.text);
    }
    await entriesRepo.stop(running.id);
  }

  Future<void> _discard() async {
    final running = _running;
    if (running == null) return;
    final l = context.l10n;
    final before = await entriesRepo.delete(running.id);
    if (mounted) showUndo(context, l.timerDiscarded, () => entriesRepo.restore(before));
  }

  void _onDescriptionChanged(String value) {
    final running = _running;
    if (running == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => entriesRepo.update(running, description: value));
  }

  Future<void> _pickProject() async {
    final running = _running;
    final pick = await showProjectPicker(context,
        projectId: running?.projectId ?? _projectId, taskId: running?.taskId ?? _taskId);
    if (pick == null || !mounted) return;
    final catalog = context.read<CatalogController>();
    final session = context.read<SessionController>();
    final project = catalog.project(pick.projectId);
    if (running != null) {
      await entriesRepo.update(running,
          projectId: pick.projectId,
          clearProject: pick.projectId == null,
          taskId: pick.taskId,
          clearTask: pick.taskId == null,
          billable: project?.billableDefault,
          hourlyRateCents: catalog.rateFor(projectId: pick.projectId, userId: session.userId!));
    } else {
      setState(() {
        _projectId = pick.projectId;
        _taskId = pick.taskId;
        if (project != null) _billable = project.billableDefault;
      });
    }
  }

  Future<void> _pickTags() async {
    final running = _running;
    final res = await showTagPicker(context, running != null ? _runningTags : _tagIds);
    if (res == null) return;
    if (running != null) {
      await entriesRepo.update(running, tagIds: res);
      _runningTags = res;
      setState(() {});
    } else {
      setState(() => _tagIds = res);
    }
  }

  Future<void> _toggleBillable() async {
    final running = _running;
    if (running != null) {
      await entriesRepo.update(running, billable: !running.billable);
    } else {
      setState(() => _billable = !_billable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final running = _running;
    final projectId = running?.projectId ?? _projectId;
    final taskId = running?.taskId ?? _taskId;
    final tagIds = running != null ? _runningTags : _tagIds;
    final billable = running?.billable ?? _billable;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final descriptionField = TextField(
      controller: _description,
      focusNode: _focus,
      decoration: InputDecoration(
        hintText: l.whatAreYouWorkingOn,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      textInputAction: TextInputAction.done,
      onChanged: _onDescriptionChanged,
      onSubmitted: (_) => running == null ? _start() : null,
    );

    final projectButton = TextButton(
      onPressed: _pickProject,
      child: projectId == null
          ? Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add_circle_outline, size: 18), const SizedBox(width: 4), Text(l.project)])
          : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: ProjectLabel(projectId: projectId, taskId: taskId)),
    );

    final tagButton = IconButton(
      tooltip: l.tags,
      onPressed: _pickTags,
      icon: Badge(
        isLabelVisible: tagIds.isNotEmpty,
        label: Text('${tagIds.length}'),
        child: Icon(Icons.sell_outlined, color: tagIds.isNotEmpty ? theme.colorScheme.primary : null),
      ),
    );

    final billableButton = IconButton(
      tooltip: billable ? l.billable : l.nonBillable,
      onPressed: _toggleBillable,
      icon: Icon(Icons.attach_money, color: billable ? theme.colorScheme.primary : theme.colorScheme.outline),
    );

    final clock = running == null
        ? Text('0:00:00', style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))
        : ElapsedText(running.startAt,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]));

    final mainButton = running == null
        ? FilledButton(onPressed: _start, child: Text(l.start.toUpperCase()))
        : FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: _stop,
            child: Text(l.stop.toUpperCase()),
          );

    final menu = PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'manual':
            showEntryDialog(context);
          case 'discard':
            _discard();
          case 'edit' when running != null:
            showEntryDialog(context, entry: running, tagIds: _runningTags);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'manual', child: Text(l.addManualEntry)),
        if (running != null) PopupMenuItem(value: 'edit', child: Text(l.editTimer)),
        if (running != null) PopupMenuItem(value: 'discard', child: Text(l.discardTimer)),
      ],
    );

    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: wide
          ? Row(children: [
              Expanded(child: descriptionField),
              projectButton,
              tagButton,
              billableButton,
              const SizedBox(width: 8),
              clock,
              const SizedBox(width: 12),
              mainButton,
              menu,
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [Expanded(child: descriptionField), clock, const SizedBox(width: 8), mainButton]),
              Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: projectButton)), tagButton, billableButton, menu]),
            ]),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: !_parallel || _runningAll.isEmpty
          ? bar
          : Column(mainAxisSize: MainAxisSize.min, children: [
              bar,
              const Divider(height: 1),
              ..._runningRows(wide),
            ]),
    );
  }

  /// Chronomètres simultanés : une ligne chacun ; repliés sur mobile au-delà de deux.
  List<Widget> _runningRows(bool wide) {
    final theme = Theme.of(context);
    final collapsible = !wide && _runningAll.length > 2;
    return [
      if (collapsible)
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(context.l10n.runningTimersCount(_runningAll.length), style: theme.textTheme.labelLarge)),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
        ),
      if (!collapsible || _expanded)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Column(children: [for (final e in _runningAll) RunningTimerRow(key: ValueKey(e.id), entry: e)]),
          ),
        ),
    ];
  }
}
