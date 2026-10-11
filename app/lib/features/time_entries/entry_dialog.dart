import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';

/// Création (entry == null) ou modification d'une entrée de temps.
Future<void> showEntryDialog(
  BuildContext context, {
  TimeEntry? entry,
  List<String>? tagIds,
  DateTime? initialStart,
  DateTime? initialEnd,
  String? initialProjectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EntryDialog(
      entry: entry,
      tagIds: tagIds ?? const [],
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialProjectId: initialProjectId,
    ),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({this.entry, required this.tagIds, this.initialStart, this.initialEnd, this.initialProjectId});
  final TimeEntry? entry;
  final List<String> tagIds;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? initialProjectId;

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
  bool _saving = false;

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
    setState(() => _saving = true);
    final userId = widget.entry?.userId ?? session.userId!;
    final rate = catalog.rateFor(projectId: _projectId, userId: userId);
    final e = widget.entry;
    if (e == null) {
      await entriesRepo.createManual(
        workspaceId: ws.id,
        userId: userId,
        start: _startDt,
        end: _endDt!,
        draft: EntryDraft(
          description: _description.text,
          projectId: _projectId,
          taskId: _taskId,
          billable: _billable,
          tagIds: _tagIds,
          hourlyRateCents: rate,
        ),
      );
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
        start: _startDt,
        end: _isRunning ? null : _endDt,
        tagIds: _tagIds,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final l = context.l10n;
    if (!await confirm(context, title: l.deleteEntry, message: l.deleteEntryMessage)) return;
    await entriesRepo.delete(widget.entry!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final locked = widget.entry?.locked ?? false;
    final session = context.watch<SessionController>();
    final lockDate = DateTime.tryParse(session.workspace?.lockEntriesBefore ?? '');
    final inLockedPeriod = lockDate != null && _date.isBefore(lockDate) && !session.isAdmin;
    final readOnly = (locked && !session.isAdmin) || inLockedPeriod;

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
                  Expanded(child: Text(l.entryLocked, style: TextStyle(color: theme.colorScheme.error))),
                ]),
              ),
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
                      final project = context.read<CatalogController>().project(pick.projectId);
                      setState(() {
                        _projectId = pick.projectId;
                        _taskId = pick.taskId;
                        if (project != null && widget.entry == null) _billable = project.billableDefault;
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
            if (_endDt != null && !sameDay(_endDt!, _startDt))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.endsNextDay, style: theme.textTheme.bodySmall),
              ),
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
