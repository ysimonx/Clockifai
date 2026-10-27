import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/entry_dialog.dart';
import '../time_entries/time_entries_page.dart' show continueEntry;
import 'running_timer_row.dart';
import 'timer_notifications.dart';
import 'timer_rules.dart';

final _toggles = ValueNotifier<int>(0);

/// Touche S et palette ⌘K : arrête le chronomètre en cours, ou ouvre « Démarrer le chronomètre ».
void toggleTimer() => _toggles.value++;

/// Chronomètre (plans/14-coller-aux-maquettes.md, lot 1) : un bouton « Démarrer » toujours visible, qui devient la
/// pastille « description · projet · 0:47 ■ » tant qu'il tourne. Le chronomètre est une entrée sans fin en base
/// locale : il survit au redémarrage de l'app, fonctionne hors ligne et apparaît sur les autres appareils après sync.
/// Avec plusieurs chronomètres simultanés, la pastille montre le plus récent ; un clic les liste tous.
class TimerControl extends StatefulWidget {
  const TimerControl({super.key, this.compact = false});

  /// Téléphone : bouton rond, pastille resserrée.
  final bool compact;

  @override
  State<TimerControl> createState() => _TimerControlState();
}

class _TimerControlState extends State<TimerControl> {
  StreamSubscription<List<TimeEntry>>? _sub;
  String? _boundKey;
  List<TimeEntry> _running = const [];

  @override
  void initState() {
    super.initState();
    _toggles.addListener(_onToggle);
  }

  void _onToggle() {
    if (!mounted) return;
    final latest = _running.firstOrNull;
    final parallel = context.read<SessionController>().runningTimersLimit != 1;
    latest == null || parallel ? showStartTimer(context) : stopTimer(context, latest);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final key = '${session.workspaceId}:${session.userId}';
    if (key == _boundKey || session.workspaceId == null || session.userId == null) return;
    _boundKey = key;
    _sub?.cancel();
    _sub = entriesRepo.watchRunningAll(session.workspaceId!, session.userId!).listen(_onRunning);
  }

  Future<void> _onRunning(List<TimeEntry> all) async {
    _running = all;
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
    _toggles.removeListener(_onToggle);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final latest = _running.firstOrNull;
    if (latest == null) {
      return widget.compact
          ? IconButton.filled(
              tooltip: l.cmdStartTimer,
              style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: () => showStartTimer(context),
              icon: const Icon(Icons.play_arrow),
            )
          : FilledButton.icon(
              onPressed: () => showStartTimer(context),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(l.start),
            );
    }
    return RunningTimerChip(entry: latest, others: _running.length - 1, compact: widget.compact, onOpen: () => _showRunning(context));
  }

  /// Les chronomètres en cours : modifier, arrêter, abandonner ; en démarrer un autre si l'espace le permet.
  void _showRunning(BuildContext context) {
    final l = context.l10n;
    final parallel = context.read<SessionController>().runningTimersLimit != 1;
    showPanel<void>(
      context,
      title: l.runningTimersCount(_running.length),
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in _running) RunningTimerRow(key: ValueKey(e.id), entry: e),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showEntryDialog(context);
            },
            icon: const Icon(Icons.add),
            label: Text(l.addManualEntry),
          ),
          if (parallel)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showStartTimer(context);
              },
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(l.start),
            ),
        ]),
      ]),
    );
  }
}

/// Pastille du chronomètre en cours : point vert, description, projet, durée, bouton d'arrêt.
class RunningTimerChip extends StatelessWidget {
  const RunningTimerChip({super.key, required this.entry, this.others = 0, this.compact = false, this.onOpen});
  final TimeEntry entry;
  final int others;
  final bool compact;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final project = context.watch<CatalogController>().project(entry.projectId);
    final title = entry.description.isEmpty ? (project?.name ?? l.noDescription) : entry.description;
    return Material(
      color: theme.colorScheme.surface,
      shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 14, 4, 4, 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: colors.success,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: colors.successContainer, spreadRadius: 3)],
              ),
            ),
            // Téléphone : le point, la durée et l'arrêt ; le détail au toucher.
            if (!compact) ...[
              const SizedBox(width: 10),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(title, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
              ),
            ],
            if (!compact && project != null && entry.description.isNotEmpty) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(project.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ),
            ],
            if (others > 0 && !compact) ...[
              const SizedBox(width: 8),
              Text(l.otherRunningTimers(others), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
            const SizedBox(width: 10),
            ElapsedText(entry.startAt,
                style: theme.textTheme.bodyMedium?.copyWith(fontFamily: monoFont, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: l.cmdStopTimer,
              child: Tooltip(
                message: l.cmdStopTimer,
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => stopTimer(context, entry),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Container(
                            width: 10, height: 10, decoration: BoxDecoration(color: theme.colorScheme.onPrimary, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Feuille sur téléphone, fenêtre en haut à droite ailleurs : même contenu.
Future<T?> showPanel<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  final narrow = MediaQuery.sizeOf(context).width < 600;
  Widget body(BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 16),
        Flexible(child: SingleChildScrollView(child: builder(ctx))),
      ]);
  if (narrow) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: body(ctx),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(padding: const EdgeInsets.all(20), child: body(ctx)),
      ),
    ),
  );
}

/// « Démarrer le chronomètre » : ce qu'on fait, le projet, et les dernières entrées à reprendre d'un geste.
Future<void> showStartTimer(BuildContext context) =>
    showPanel<void>(context, title: context.l10n.cmdStartTimer, builder: (_) => StartTimerForm(outer: context));

class StartTimerForm extends StatefulWidget {
  const StartTimerForm({super.key, required this.outer});

  /// Contexte de l'appelant, qui reste monté une fois la feuille fermée (reprise d'une entrée, messages).
  final BuildContext outer;

  @override
  State<StartTimerForm> createState() => _StartTimerFormState();
}

class _StartTimerFormState extends State<StartTimerForm> {
  final _description = TextEditingController();
  String? _projectId;
  String? _taskId;
  List<String> _tagIds = const [];
  bool _billable = true;
  List<EntryRow> _recent = const [];

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionController>();
    entriesRepo.watchRecent(session.workspaceId!, session.userId!, limit: 4).first.then((rows) {
      if (mounted) setState(() => _recent = rows);
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    final l = context.l10n;
    final running = await entriesRepo.watchRunningAll(ws.id, session.userId!).first;
    if (!mounted) return;
    final blocked = timerRuleViolation(l, ws, description: _description.text, projectId: _projectId) ??
        alreadyRunningViolation(l, running, description: _description.text, projectId: _projectId, taskId: _taskId);
    if (blocked != null) return showSnack(context, blocked);
    final limit = session.runningTimersLimit;
    final stopsOldest = limit > 1 && running.length >= limit;
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
    Navigator.pop(context);
    if (stopsOldest && widget.outer.mounted) showSnack(widget.outer, l.oldestTimerStopped);
  }

  Future<void> _resume(EntryRow row) async {
    Navigator.pop(context);
    if (widget.outer.mounted) await continueEntry(widget.outer, row);
  }

  Future<void> _pickProject() async {
    final pick = await showProjectPicker(context, projectId: _projectId, taskId: _taskId);
    if (pick == null || !mounted) return;
    final project = context.read<CatalogController>().project(pick.projectId);
    setState(() {
      _projectId = pick.projectId;
      _taskId = pick.taskId;
      if (project != null) _billable = project.billableDefault;
    });
  }

  Future<void> _pickTags() async {
    final res = await showTagPicker(context, _tagIds);
    if (res != null) setState(() => _tagIds = res);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _description,
        autofocus: true,
        decoration: InputDecoration(hintText: l.whatAreYouWorkingOn),
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _start(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _pickProject,
              child: _projectId == null
                  ? Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.add_circle_outline, size: 18), const SizedBox(width: 6), Text(l.project)])
                  : ProjectLabel(projectId: _projectId, taskId: _taskId),
            ),
          ),
        ),
        IconButton(
          tooltip: l.tags,
          onPressed: _pickTags,
          icon: Badge(isLabelVisible: _tagIds.isNotEmpty, label: Text('${_tagIds.length}'), child: const Icon(Icons.sell_outlined)),
        ),
        IconButton(
          tooltip: _billable ? l.billable : l.nonBillable,
          onPressed: () => setState(() => _billable = !_billable),
          icon: Icon(Icons.attach_money, color: _billable ? theme.colorScheme.primary : theme.colorScheme.outline),
        ),
      ]),
      const SizedBox(height: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _start,
        icon: const Icon(Icons.play_arrow),
        label: Text(l.start),
      ),
      if (_recent.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(l.menuBarRecent.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        for (final r in _recent)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.play_circle_outline),
            title: Text(r.entry.description.isEmpty ? (catalog.project(r.entry.projectId)?.name ?? l.noDescription) : r.entry.description,
                overflow: TextOverflow.ellipsis),
            subtitle: r.entry.projectId == null ? null : ProjectLabel(projectId: r.entry.projectId, taskId: r.entry.taskId, dense: true),
            onTap: () => _resume(r),
          ),
      ],
    ]);
  }
}
