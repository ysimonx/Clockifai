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

/// Pointage d'équipe (chef d'équipe, manager) : on coche les présents d'une journée,
/// une entrée terminée est créée pour chacun, hors ligne compris. Horaires communs,
/// ajustables personne par personne (arrivée tardive, départ anticipé).
class TeamEntryPage extends StatefulWidget {
  const TeamEntryPage({super.key});

  @override
  State<TeamEntryPage> createState() => _TeamEntryPageState();
}

typedef _Hours = ({TimeOfDay start, TimeOfDay end});

class _TeamEntryPageState extends State<TeamEntryPage> {
  final _description = TextEditingController();
  DateTime _date = startOfDay(DateTime.now());
  _Hours _hours = (start: const TimeOfDay(hour: 8, minute: 0), end: const TimeOfDay(hour: 16, minute: 0));
  final _overrides = <String, _Hours>{};
  final _selected = <String>{};
  String? _projectId;
  String? _taskId;
  List<String> _tagIds = const [];
  bool _billable = true;
  bool _saving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  _Hours _hoursOf(String userId) => _overrides[userId] ?? _hours;

  /// Début et fin réels : une fin avant le début passe au lendemain (travail de nuit).
  (DateTime, DateTime) _span(_Hours h) {
    final start = DateTime(_date.year, _date.month, _date.day, h.start.hour, h.start.minute);
    var end = DateTime(_date.year, _date.month, _date.day, h.end.hour, h.end.minute);
    if (end.isBefore(start)) end = end.add(const Duration(days: 1));
    return (start, end);
  }

  int _seconds(_Hours h) {
    final (s, e) = _span(h);
    return e.difference(s).inSeconds;
  }

  Future<_Hours?> _pickHours(_Hours initial) async {
    final start = await showTimePicker(context: context, initialTime: initial.start, helpText: context.l10n.startTime);
    if (start == null || !mounted) return null;
    final end = await showTimePicker(context: context, initialTime: initial.end, helpText: context.l10n.endTime);
    if (end == null) return null;
    return (start: start, end: end);
  }

  Future<void> _save(List<String> userIds) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final rights = TeamRights.read(context);
    final ws = session.workspace!;
    final targets = userIds.where(rights.canEditTimeOf).toList();
    if (targets.isEmpty) return showSnack(context, l.noTeammateSelected);
    if (targets.any((uid) => _seconds(_hoursOf(uid)) <= 0)) return showSnack(context, l.invalidDuration);
    if (ws.requireProject && _projectId == null) return showSnack(context, l.projectRequired);
    if (ws.requireDescription && _description.text.trim().isEmpty) return showSnack(context, l.descriptionRequired);
    final lock = DateTime.tryParse(ws.lockEntriesBefore ?? '');
    if (lock != null && _date.isBefore(lock) && !session.isAdmin) return showSnack(context, l.entryLocked);
    for (final uid in targets) {
      if (await modulesRepo.isDayApproved(ws.id, uid, _date)) {
        if (mounted) showSnack(context, l.approvedPeriodFor(memberName(catalog.memberOf(uid))));
        return;
      }
    }
    final slots = <MemberSlot>[];
    for (final uid in targets) {
      final (start, end) = _span(_hoursOf(uid));
      slots.add(MemberSlot(
        userId: uid,
        start: start,
        end: end,
        hourlyRateCents: catalog.rateFor(projectId: _projectId, userId: uid),
      ));
    }
    setState(() => _saving = true);
    try {
      await entriesRepo.createForMembers(
        workspaceId: ws.id,
        createdBy: session.userId,
        slots: slots,
        draft: EntryDraft(
          description: _description.text,
          projectId: _projectId,
          taskId: _taskId,
          billable: _billable,
          tagIds: _tagIds,
        ),
      );
      if (!mounted) return;
      showSnack(context, l.entriesCreated(targets.length));
      setState(() {
        _selected.clear();
        _overrides.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final rights = TeamRights.of(context);
    if (!rights.canEditOthers) return EmptyState(icon: Icons.lock_outline, title: l.managersOnly);
    final members = rights.editableMembers;
    final chosen = members.where((m) => _selected.contains(m.userId)).map((m) => m.userId).toList();
    final total = chosen.fold<int>(0, (s, uid) => s + _seconds(_hoursOf(uid)));
    final allChosen = members.isNotEmpty && chosen.length == members.length;

    return PageScaffold(
      title: l.teamEntry,
      maxWidth: 800,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(l.teamEntryHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _description, decoration: InputDecoration(labelText: l.description)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final pick = await showProjectPicker(context, projectId: _projectId, taskId: _taskId);
                  if (pick == null || !context.mounted) return;
                  final project = context.read<CatalogController>().project(pick.projectId);
                  setState(() {
                    _projectId = pick.projectId;
                    _taskId = pick.taskId;
                    if (project != null) _billable = project.billableDefault;
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
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: Align(alignment: Alignment.centerLeft, child: _tagIds.isEmpty ? Text(l.addTags) : TagChips(_tagIds)),
                    onPressed: () async {
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
                  onSelected: (v) => setState(() => _billable = v),
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(DateFormat.yMMMEd(locale).format(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text('${l.defaultHours} : ${_hours.start.format(context)} – ${_hours.end.format(context)} · ${formatHm(_seconds(_hours))}'),
                  onPressed: () async {
                    final h = await _pickHours(_hours);
                    if (h != null) setState(() => _hours = h);
                  },
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            CheckboxListTile(
              value: allChosen,
              title: Text(l.selectAll, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${l.peopleCount(chosen.length)} · ${formatHm(total)}'),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.addAll(members.map((m) => m.userId));
                } else {
                  _selected.clear();
                }
              }),
            ),
            const Divider(height: 1),
            for (final m in members)
              _MemberRow(
                name: memberName(m),
                selected: _selected.contains(m.userId),
                hours: _hoursOf(m.userId),
                overridden: _overrides.containsKey(m.userId),
                seconds: _seconds(_hoursOf(m.userId)),
                onSelected: (v) => setState(() => v ? _selected.add(m.userId) : _selected.remove(m.userId)),
                onEditHours: () async {
                  final h = await _pickHours(_hoursOf(m.userId));
                  if (h == null) return;
                  setState(() {
                    _overrides[m.userId] = h;
                    _selected.add(m.userId);
                  });
                },
                onResetHours: () => setState(() => _overrides.remove(m.userId)),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.group_add),
            label: Text(l.createEntries),
            onPressed: _saving || chosen.isEmpty ? null : () => _save(chosen),
          ),
        ),
      ]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.selected,
    required this.hours,
    required this.overridden,
    required this.seconds,
    required this.onSelected,
    required this.onEditHours,
    required this.onResetHours,
  });
  final String name;
  final bool selected;
  final _Hours hours;
  final bool overridden;
  final int seconds;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEditHours;
  final VoidCallback onResetHours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: overridden ? theme.colorScheme.primary : null,
      fontWeight: overridden ? FontWeight.w600 : null,
    );
    return ListTile(
      leading: Checkbox(value: selected, onChanged: (v) => onSelected(v ?? false)),
      title: Text(name),
      onTap: () => onSelected(!selected),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(
          onPressed: onEditHours,
          child: Text('${hours.start.format(context)} – ${hours.end.format(context)} · ${formatHm(seconds)}', style: style),
        ),
        if (overridden) IconButton(icon: const Icon(Icons.undo, size: 18), onPressed: onResetHours),
      ]),
    );
  }
}
