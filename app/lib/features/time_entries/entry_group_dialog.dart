import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import 'entry_groups.dart';

/// Modifie d'un coup les entrées d'un groupe d'entrées similaires : description, projet, tâche, tags
/// et facturable. Les horaires, propres à chaque entrée, ne changent pas.
Future<void> showEntryGroupDialog(BuildContext context, EntryGroup group) =>
    showDialog<void>(context: context, builder: (_) => _EntryGroupDialog(group));

class _EntryGroupDialog extends StatefulWidget {
  const _EntryGroupDialog(this.group);
  final EntryGroup group;

  @override
  State<_EntryGroupDialog> createState() => _EntryGroupDialogState();
}

class _EntryGroupDialogState extends State<_EntryGroupDialog> {
  late final TextEditingController _description;
  late String? _projectId;
  late String? _taskId;
  late List<String> _tagIds;
  late bool _billable;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final first = widget.group.first;
    _description = TextEditingController(text: first.entry.description);
    _projectId = first.entry.projectId;
    _taskId = first.entry.taskId;
    _tagIds = first.tagIds;
    _billable = first.entry.billable;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    if (ws.requireProject && _projectId == null) return showSnack(context, l.projectRequired);
    if (ws.requireDescription && _description.text.trim().isEmpty) return showSnack(context, l.descriptionRequired);
    setState(() => _saving = true);
    await entriesRepo.updateMany(
      [for (final r in widget.group.rows) r.entry],
      description: _description.text,
      projectId: _projectId,
      taskId: _taskId,
      billable: _billable,
      tagIds: _tagIds,
      hourlyRateFor: (e) => catalog.rateFor(projectId: _projectId, userId: e.userId),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.editSimilarEntries(widget.group.rows.length)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _description,
              decoration: InputDecoration(labelText: l.description),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final pick = await showProjectPicker(context, projectId: _projectId, taskId: _taskId);
                if (pick == null) return;
                setState(() {
                  _projectId = pick.projectId;
                  _taskId = pick.taskId;
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
            const SizedBox(height: 12),
            Text(l.similarEntriesEditHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
