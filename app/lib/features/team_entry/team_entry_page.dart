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
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart' show dayKey;
import '../../data/repositories/time_entry_repository.dart';
import '../time_entries/duration_chips.dart';
import '../today/day_plan.dart' show TypicalDay, addDays;

/// Pointage d'équipe (chef d'équipe, manager) : une entrée terminée par présent, hors ligne compris. Les présents
/// sont cochés d'office (sauf soi) ; une absence validée ce jour-là exclut la personne, une journée déjà saisie la
/// décoche.
/// Horaires communs, et exceptions personne par personne (« Départ à 15:00 ») ; plans/13-ux-moderne.md, lot 9.
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

  /// Jour (`yyyy-MM-dd`) dont les présents ont été cochés d'office ; un autre jour les recoche.
  String? _presetFor;
  Stream<List<TimeOffRequest>>? _requests;
  String? _dayKey;
  Stream<List<EntryRow>>? _dayEntries;

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
      final ids = await entriesRepo.createForMembers(
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
      showUndo(context, l.entriesCreated(targets.length), () async {
        await entriesRepo.deleteMany(ids);
        if (mounted) setState(() => _presetFor = null); // les présents se recochent
      });
      setState(() {
        _selected.clear();
        _overrides.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exception(String userId, String kind) async {
    final l = context.l10n;
    final h = _hoursOf(userId);
    _Hours? next;
    switch (kind) {
      case 'arrive':
        final t = await showTimePicker(context: context, initialTime: h.start, helpText: l.arrivedAtPick);
        if (t != null) next = (start: t, end: h.end);
      case 'leave':
        final t = await showTimePicker(context: context, initialTime: h.end, helpText: l.leftAtPick);
        if (t != null) next = (start: h.start, end: t);
      case 'hours':
        next = await _pickHours(h);
      case 'reset':
        setState(() => _overrides.remove(userId));
        return;
    }
    if (next == null || !mounted) return;
    setState(() {
      _overrides[userId] = next!;
      _selected.add(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rights = TeamRights.of(context);
    if (!rights.canEditOthers) return EmptyState(icon: Icons.lock_outline, title: l.managersOnly);
    final ws = context.read<SessionController>().workspaceId!;
    final key = dayKey(_date);
    if (_dayKey != key) {
      _dayKey = key;
      _dayEntries = entriesRepo.watchEntries(workspaceId: ws, from: _date, to: addDays(_date, 1));
    }
    return StreamBuilder<List<TimeOffRequest>>(
      stream: _requests ??= modulesRepo.watchRequests(ws),
      builder: (context, reqSnap) => StreamBuilder<List<EntryRow>>(
        stream: _dayEntries,
        builder: (context, entrySnap) => _page(context, rights,
            requests: reqSnap.data, entries: entrySnap.data, key: key),
      ),
    );
  }

  Widget _page(BuildContext context, TeamRights rights,
      {required List<TimeOffRequest>? requests, required List<EntryRow>? entries, required String key}) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final members = rights.editableMembers;
    // Absence validée ce jour-là (null : aucune ; vrai : journée entière).
    bool? absence(String userId) {
      final r = (requests ?? const <TimeOffRequest>[])
          .where((r) => r.userId == userId && r.status == 'approved' && r.startDate.compareTo(key) <= 0 && r.endDate.compareTo(key) >= 0)
          .firstOrNull;
      return r == null ? null : !r.halfDay;
    }

    int logged(String userId) =>
        (entries ?? const <EntryRow>[]).where((r) => r.entry.userId == userId).fold(0, (s, r) => s + r.seconds);
    if (_presetFor != key && requests != null && entries != null) {
      _presetFor = key;
      _overrides.clear();
      _selected
        ..clear()
        ..addAll([
          // Soi-même non : on pointe son équipe, son propre temps se saisit à part.
          for (final m in members)
            if (m.userId != rights.me && absence(m.userId) == null && logged(m.userId) == 0) m.userId,
        ]);
    }
    final available = [for (final m in members) if (absence(m.userId) != true) m.userId];
    final chosen = members.where((m) => _selected.contains(m.userId) && available.contains(m.userId)).map((m) => m.userId).toList();
    final total = chosen.fold<int>(0, (s, uid) => s + _seconds(_hoursOf(uid)));
    final allChosen = available.isNotEmpty && chosen.length == available.length;

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
              const SizedBox(height: 8),
              DurationChips(
                typical: TypicalDay.ofProfile(context.read<SessionController>().profile) ?? TypicalDay.fallback,
                onNudge: (m) => setState(() {
                  final end = _hours.end.hour * 60 + _hours.end.minute + m;
                  _hours = (start: _hours.start, end: TimeOfDay(hour: (end ~/ 60) % 24, minute: end % 60));
                }),
                onRange: (start, end) => setState(() => _hours = (start: start, end: end)),
              ),
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
                  _selected.addAll(available);
                } else {
                  _selected.clear();
                }
              }),
            ),
            const Divider(height: 1),
            for (final m in members)
              _MemberRow(
                name: memberName(m),
                selected: chosen.contains(m.userId),
                absent: absence(m.userId) == true,
                note: switch ((absence(m.userId), logged(m.userId))) {
                  (true, _) => l.teamAbsent,
                  (false, _) => l.teamAbsentHalf,
                  (_, final s) when s > 0 => l.teamAlreadyLogged(formatHm(s)),
                  _ => null,
                },
                hours: _hoursOf(m.userId),
                common: _hours,
                overridden: _overrides.containsKey(m.userId),
                seconds: _seconds(_hoursOf(m.userId)),
                onSelected: (v) => setState(() => v ? _selected.add(m.userId) : _selected.remove(m.userId)),
                onException: (kind) => _exception(m.userId, kind),
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
    required this.absent,
    required this.note,
    required this.hours,
    required this.common,
    required this.overridden,
    required this.seconds,
    required this.onSelected,
    required this.onException,
  });
  final String name;
  final bool selected;

  /// Absence validée toute la journée : la ligne ne peut pas être cochée.
  final bool absent;

  /// « Absence validée », « Déjà saisi : 7:30 »…
  final String? note;
  final _Hours hours;
  final _Hours common;
  final bool overridden;
  final int seconds;
  final ValueChanged<bool> onSelected;
  final ValueChanged<String> onException;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: overridden ? theme.colorScheme.primary : null,
      fontWeight: overridden ? FontWeight.w600 : null,
    );
    // Une exception se lit telle qu'on la dit : « Départ à 15:00 », « Arrivée à 9:15 ».
    final sameStart = hours.start == common.start, sameEnd = hours.end == common.end;
    final label = !overridden || (sameStart && sameEnd)
        ? '${hours.start.format(context)} – ${hours.end.format(context)}'
        : sameStart
            ? l.leftAt(hours.end.format(context))
            : sameEnd
                ? l.arrivedAt(hours.start.format(context))
                : '${hours.start.format(context)} – ${hours.end.format(context)}';
    return ListTile(
      enabled: !absent,
      leading: Checkbox(value: selected, onChanged: absent ? null : (v) => onSelected(v ?? false)),
      title: Text(name),
      subtitle: note == null ? null : Text(note!),
      onTap: absent ? null : () => onSelected(!selected),
      trailing: absent
          ? null
          : PopupMenuButton<String>(
              tooltip: l.teamException,
              onSelected: onException,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'arrive', child: Text(l.arrivedAtPick)),
                PopupMenuItem(value: 'leave', child: Text(l.leftAtPick)),
                PopupMenuItem(value: 'hours', child: Text(l.otherHours)),
                if (overridden) PopupMenuItem(value: 'reset', child: Text(l.commonHours)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text('$label · ${formatHm(seconds)}', style: style),
              ),
            ),
    );
  }
}
