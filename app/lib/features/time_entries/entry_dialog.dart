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
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/teammates.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../today/day_plan.dart' show TypicalDay;
import 'ai_usage.dart';
import 'duration_chips.dart';

/// Heure à écrire pour une entrée modifiée : null si l'heure saisie, à la minute près, est celle d'origine.
/// Le dialogue ne saisit pas les secondes : réécrire une heure inchangée les perdrait, et ferait passer une entrée
/// d'agent Claude pour corrigée à la main, que le serveur cesserait alors de prolonger (plan 10, D7.8).
DateTime? changedTime(DateTime? original, DateTime? edited) {
  if (edited == null) return null;
  if (original == null) return edited;
  final o = original.toLocal();
  final e = edited.toLocal();
  final same = o.year == e.year && o.month == e.month && o.day == e.day && o.hour == e.hour && o.minute == e.minute;
  return same ? null : edited;
}

/// Création (entry == null) ou modification d'une entrée de temps.
/// À la création, [initialUserIds] préremplit les collaborateurs (chef d'équipe, manager) :
/// une entrée est créée par personne.
Future<void> showEntryDialog(
  BuildContext context, {
  TimeEntry? entry,
  List<String>? tagIds,
  DateTime? initialStart,
  DateTime? initialEnd,
  String? initialProjectId,
  Set<String>? initialUserIds,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EntryDialog(
      entry: entry,
      tagIds: tagIds ?? const [],
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialProjectId: initialProjectId,
      initialUserIds: initialUserIds,
    ),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    this.entry,
    required this.tagIds,
    this.initialStart,
    this.initialEnd,
    this.initialProjectId,
    this.initialUserIds,
  });
  final TimeEntry? entry;
  final List<String> tagIds;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? initialProjectId;
  final Set<String>? initialUserIds;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final TextEditingController _description;
  late final TextEditingController _duration;
  late DateTime _date;
  late TimeOfDay _start;
  TimeOfDay? _end;
  String? _projectId;
  String? _taskId;
  late List<String> _tagIds;
  late bool _billable;
  late Set<String> _userIds;
  bool _saving = false;
  /// « Toujours rattacher ce dépôt à ce projet » (entrée d'agent sans projet, plan 10, D9).
  bool _attachRepo = true;

  bool get _isRunning => widget.entry != null && widget.entry!.endAt == null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final now = DateTime.now();
    final start = e?.startAt.toLocal() ?? widget.initialStart ?? now.subtract(const Duration(hours: 1));
    final end = e == null ? (widget.initialEnd ?? (widget.initialStart?.add(const Duration(hours: 1)) ?? now)) : e.endAt?.toLocal();
    _description = TextEditingController(text: e?.description ?? '');
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay.fromDateTime(start);
    _end = end == null ? null : TimeOfDay.fromDateTime(end);
    _projectId = e?.projectId ?? widget.initialProjectId;
    _taskId = e?.taskId;
    _tagIds = List.of(widget.tagIds);
    _billable = e?.billable ?? true;
    _userIds = {...?widget.initialUserIds};
    if (_userIds.isEmpty) _userIds.add(context.read<SessionController>().userId!);
    _duration = TextEditingController(text: _end == null ? '' : formatHm(_seconds()));
  }

  @override
  void dispose() {
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  DateTime get _startDt => DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);

  /// Fin : si l'heure de fin est avant le début, on considère le lendemain (travail de nuit).
  DateTime? get _endDt {
    if (_end == null) return null;
    var end = DateTime(_date.year, _date.month, _date.day, _end!.hour, _end!.minute);
    if (end.isBefore(_startDt)) end = end.add(const Duration(days: 1));
    return end;
  }

  int _seconds() => _endDt == null ? 0 : _endDt!.difference(_startDt).inSeconds;

  void _syncDurationField() => _duration.text = _end == null ? '' : formatHm(_seconds());

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : (_end ?? TimeOfDay.now()));
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t;
      } else {
        _end = t;
      }
      _syncDurationField();
    });
  }

  void _setEnd(DateTime end) => setState(() {
        _end = TimeOfDay.fromDateTime(end);
        _syncDurationField();
      });

  /// ±15 min sur la fin, sans descendre sous 5 minutes.
  void _nudge(int minutes) {
    final end = (_endDt ?? _startDt).add(Duration(minutes: minutes));
    final min = _startDt.add(const Duration(minutes: 5));
    _setEnd(end.isBefore(min) ? min : end);
  }

  void _onDurationChanged(String v) {
    final secs = parseDuration(v);
    if (secs == null) return;
    final end = _startDt.add(Duration(seconds: secs));
    setState(() => _end = TimeOfDay.fromDateTime(end));
  }

  Future<void> _save() async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    if (ws.requireProject && _projectId == null) return showSnack(context, l.projectRequired);
    if (ws.requireDescription && _description.text.trim().isEmpty) return showSnack(context, l.descriptionRequired);
    if (!_isRunning && _endDt == null) return showSnack(context, l.endTimeRequired);
    if (_isRunning && _startDt.isAfter(DateTime.now())) return showSnack(context, l.startInFuture);
    final e = widget.entry;
    // Seules les personnes pour qui l'on a le droit de saisir (la RLS refuserait les autres).
    final rights = TeamRights.read(context);
    final targets = _userIds.where(rights.canEditTimeOf).toSet();
    if (e == null && targets.isEmpty) return showSnack(context, l.noTeammateSelected);
    // Période déjà approuvée pour l'une des personnes : le serveur refuserait, on prévient avant.
    if (e == null) {
      for (final uid in targets) {
        if (await modulesRepo.isDayApproved(ws.id, uid, _date)) {
          if (mounted) showSnack(context, l.approvedPeriodFor(memberName(catalog.memberOf(uid))));
          return;
        }
      }
      if (!mounted) return;
    }
    setState(() => _saving = true);
    final userId = e?.userId ?? session.userId!;
    final rate = catalog.rateFor(projectId: _projectId, userId: userId);
    if (e == null) {
      await entriesRepo.createForMembers(
        workspaceId: ws.id,
        slots: [
          for (final uid in targets)
            MemberSlot(
              userId: uid,
              start: _startDt,
              end: _endDt!,
              hourlyRateCents: catalog.rateFor(projectId: _projectId, userId: uid),
            ),
        ],
        createdBy: session.userId,
        draft: EntryDraft(
          description: _description.text,
          projectId: _projectId,
          taskId: _taskId,
          billable: _billable,
          tagIds: _tagIds,
        ),
      );
      if (mounted && targets.length > 1) showSnack(context, l.entriesCreated(targets.length));
    } else {
      await entriesRepo.update(
        e,
        description: _description.text,
        projectId: _projectId,
        clearProject: _projectId == null,
        taskId: _taskId,
        clearTask: _taskId == null,
        billable: _billable,
        hourlyRateCents: _projectId != e.projectId ? rate : null,
        start: changedTime(e.startAt, _startDt),
        end: _isRunning ? null : changedTime(e.endAt, _endDt),
        tagIds: _tagIds,
      );
      if (_offersRepoRule(rights) && _attachRepo) await _createRepoRule(e);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Le pilote donne un projet à une entrée de son agent qui n'en avait pas : on lui propose d'y rattacher le dépôt.
  bool _offersRepoRule(TeamRights rights) {
    final e = widget.entry;
    return e != null && e.projectId == null && _projectId != null && rights.pilots(e.userId);
  }

  /// Règle personnelle « ce dépôt → ce projet » (Flask lit le dépôt de l'entrée), qui rattache aussi les autres
  /// entrées sans projet de l'agent sur 7 jours. En ligne seulement ; l'entrée elle-même est déjà enregistrée.
  Future<void> _createRepoRule(TimeEntry e) async {
    final l = context.l10n;
    try {
      final res = await ServicesApi.post('/api/activity/rules', {
        'workspace_id': e.workspaceId,
        'time_entry_id': e.id,
        // Le projet seulement : la tâche est celle de cette session, pas de toutes les suivantes du dépôt.
        'project_id': _projectId,
      });
      if (mounted) showSnack(context, l.repoAttached((res['reattributed'] as num?)?.toInt() ?? 0));
    } on ServicesException catch (err) {
      if (mounted) showSnack(context, err.status == 404 ? l.repoUnknown : l.repoAttachOffline);
    } catch (_) {
      if (mounted) showSnack(context, l.repoAttachOffline);
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final before = await entriesRepo.delete(widget.entry!.id);
    if (!mounted) return;
    showUndo(context, l.entryDeleted, () => entriesRepo.restore(before));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final locked = widget.entry?.locked ?? false;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final project = catalog.project(_projectId);
    final rights = TeamRights.of(context);
    final lockDate = DateTime.tryParse(session.workspace?.lockEntriesBefore ?? '');
    final inLockedPeriod = lockDate != null && _date.isBefore(lockDate) && !session.isAdmin;
    final owner = widget.entry?.userId;
    final notAllowed = owner != null && !rights.canEditTimeOf(owner);
    final readOnly = (locked && !session.isAdmin) || inLockedPeriod || notAllowed;
    final author = widget.entry?.createdBy;
    // Une entrée d'agent porte son pilote comme auteur, mais c'est Claude Code qui l'a enregistrée.
    final enteredByOther = owner != null && author != null && author != owner && widget.entry?.source != 'agent';
    final taskPills = readOnly || project == null ? const <Task>[] : catalog.tasksOf(project.id);
    // Sous-tâches de la tâche choisie (plans/16-sous-taches.md), en pastilles sous les tâches.
    final rootTask = catalog.rootTask(_taskId);
    final subtaskPills = readOnly || rootTask == null ? const <Task>[] : catalog.subtasksOf(rootTask.id);

    return AlertDialog(
      title: Text(widget.entry == null ? l.addManualEntry : (_isRunning ? l.runningTimer : l.editEntry)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (readOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.lock, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notAllowed ? l.readOnlyTimeOf(memberName(catalog.memberOf(owner))) : l.entryLocked,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ]),
              ),
            // Entrée de quelqu'un d'autre : à qui elle appartient et qui l'a saisie.
            if (owner != null && (owner != session.userId || enteredByOther))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.person_outline, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        memberName(catalog.memberOf(owner)),
                        if (enteredByOther) l.enteredBy(memberName(catalog.memberOf(author))),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
              ),
            // Création par un chef d'équipe ou un manager : une entrée par collaborateur choisi.
            if (widget.entry == null && rights.canEditOthers) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.people_outline, size: 18),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _userIds.isEmpty ? l.selectTeammates : _userIds.map((u) => memberName(catalog.memberOf(u))).join(', '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                onPressed: () async {
                  final picked = await showMembersPicker(
                    context,
                    title: l.teammates,
                    members: rights.editableMembers,
                    selected: _userIds,
                  );
                  if (picked != null) setState(() => _userIds = picked);
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _description,
              enabled: !readOnly,
              decoration: InputDecoration(labelText: l.description),
              autofocus: widget.entry == null,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: readOnly
                  ? null
                  : () async {
                      final pick = await showProjectPicker(context, projectId: _projectId, taskId: _taskId);
                      if (pick == null || !context.mounted) return;
                      final catalog = context.read<CatalogController>();
                      final project = catalog.project(pick.projectId);
                      final agent = widget.entry != null && catalog.isAgent(widget.entry!.userId);
                      setState(() {
                        _projectId = pick.projectId;
                        _taskId = pick.taskId;
                        if (project != null && widget.entry == null) _billable = project.billableDefault;
                        // Entrée de Claude : facturable selon le réglage des agents (D16), corrigeable ensuite.
                        if (agent && pick.projectId != widget.entry!.projectId) {
                          _billable = catalog.billableFor(
                            projectId: pick.projectId,
                            userId: widget.entry!.userId,
                            agentBilling: context.read<SessionController>().workspace?.agentBilling,
                          );
                        }
                      });
                    },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ProjectLabel(projectId: _projectId, taskId: _taskId),
                ),
              ),
            ),
            // Tâches en pastilles (lot 9) : un toucher, sans rouvrir le sélecteur.
            if (taskPills.isNotEmpty && taskPills.length <= 12)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in taskPills)
                    ChoiceChip(
                      label: Text(t.name),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: rootTask?.id == t.id,
                      onSelected: (v) => setState(() => _taskId = v ? t.id : null),
                    ),
                ]),
              ),
            if (subtaskPills.isNotEmpty && subtaskPills.length <= 12)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Icon(Icons.subdirectory_arrow_right, size: 16, color: theme.colorScheme.outline),
                  for (final s in subtaskPills)
                    ChoiceChip(
                      label: Text(s.name),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: _taskId == s.id,
                      onSelected: (v) => setState(() => _taskId = v ? s.id : rootTask!.id),
                    ),
                ]),
              ),
            // Une tâche pour ce travail, sans passer par le « + » du sélecteur (une session de Claude, par exemple :
            // ses entrées suivantes la reprennent, plan 10, D9).
            if (!readOnly && _taskId == null && project != null && session.canCreateTasks)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_task, size: 18),
                  label: Text(l.newTask),
                  onPressed: () async {
                    final id = await promptNewTask(context, project);
                    if (id != null && mounted) setState(() => _taskId = id);
                  },
                ),
              ),
            if (!readOnly && _offersRepoRule(rights))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _attachRepo,
                onChanged: (v) => setState(() => _attachRepo = v ?? false),
                title: Text(l.alwaysAttachRepo),
                subtitle: Text(l.alwaysAttachRepoHelp),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: _tagIds.isEmpty ? Text(l.addTags) : TagChips(_tagIds),
                  ),
                  onPressed: readOnly
                      ? null
                      : () async {
                          final res = await showTagPicker(context, _tagIds);
                          if (res != null) setState(() => _tagIds = res);
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.attach_money, size: 18),
                label: Text(l.billable),
                selected: _billable,
                onSelected: readOnly ? null : (v) => setState(() => _billable = v),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _FieldButton(
                  label: l.date,
                  value: DateFormat.yMMMEd(locale).format(_date),
                  onTap: readOnly ? null : _pickDate,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _FieldButton(label: l.startTime, value: _start.format(context), onTap: readOnly ? null : () => _pickTime(true))),
              const SizedBox(width: 8),
              if (!_isRunning) ...[
                Expanded(
                  child: _FieldButton(
                    label: l.endTime,
                    value: _end?.format(context) ?? '—',
                    onTap: readOnly ? null : () => _pickTime(false),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _duration,
                    enabled: !readOnly,
                    decoration: InputDecoration(labelText: l.duration, hintText: '1:30'),
                    onChanged: _onDurationChanged,
                  ),
                ),
              ],
            ]),
            if (!_isRunning && !readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DurationChips(
                  typical: TypicalDay.ofProfile(session.profile) ?? TypicalDay.fallback,
                  onNudge: _nudge,
                  onLength: (m) => _setEnd(_startDt.add(Duration(minutes: m))),
                  onRange: (start, end) => setState(() {
                    _start = start;
                    _end = end;
                    _syncDurationField();
                  }),
                ),
              ),
            if (_endDt != null && !sameDay(_endDt!, _startDt))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.endsNextDay, style: theme.textTheme.bodySmall),
              ),
            // Entrée d'agent : tokens, modèle, effort et coût estimé (plan 10, D17).
            if (widget.entry != null && catalog.isAgent(widget.entry!.userId)) AiUsageSection(entryId: widget.entry!.id),
          ]),
        ),
      ),
      actions: [
        if (widget.entry != null && !readOnly)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: Text(l.delete),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        if (!readOnly) FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
      ],
    );
  }
}

class _FieldButton extends StatelessWidget {
  const _FieldButton({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, enabled: onTap != null),
          child: Text(value),
        ),
      );
}
