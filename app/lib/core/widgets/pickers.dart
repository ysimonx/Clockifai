import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/drift/database.dart';
import '../catalog.dart';
import '../di.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import 'common.dart';

/// Résultat du sélecteur de projet : `projectId == null` = sans projet.
class ProjectPick {
  const ProjectPick(this.projectId, this.taskId);
  final String? projectId;
  final String? taskId;
}

Future<ProjectPick?> showProjectPicker(BuildContext context, {String? projectId, String? taskId}) {
  return showDialog<ProjectPick>(
    context: context,
    builder: (_) => _ProjectPickerDialog(projectId: projectId, taskId: taskId),
  );
}

class _ProjectPickerDialog extends StatefulWidget {
  const _ProjectPickerDialog({this.projectId, this.taskId});
  final String? projectId;
  final String? taskId;

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final q = _query.toLowerCase();
    final projects = catalog.activeProjects.where((p) {
      if (q.isEmpty) return true;
      final client = catalog.client(p.clientId)?.name ?? '';
      return p.name.toLowerCase().contains(q) ||
          client.toLowerCase().contains(q) ||
          catalog.tasksOf(p.id).any((t) => t.name.toLowerCase().contains(q));
    }).toList();

    // Regroupement par client (sans client en premier).
    final groups = <String?, List<Project>>{};
    for (final p in projects) {
      groups.putIfAbsent(p.clientId, () => []).add(p);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a == null ? -1 : b == null ? 1 : (catalog.client(a)?.name ?? '').compareTo(catalog.client(b)?.name ?? ''));

    return AlertDialog(
      title: Text(l.selectProject),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.searchProjectOrTask),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              ListTile(
                leading: const Icon(Icons.block, size: 18),
                title: Text(l.noProject),
                selected: widget.projectId == null,
                onTap: () => Navigator.pop(context, const ProjectPick(null, null)),
              ),
              for (final key in keys) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    (key == null ? l.noClient : catalog.client(key)?.name ?? '').toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                for (final p in groups[key]!) ...[
                  ListTile(
                    dense: true,
                    leading: ColorDot(p.color, size: 12),
                    title: Text(p.name, style: TextStyle(color: colorFromHex(p.color), fontWeight: FontWeight.w600)),
                    selected: widget.projectId == p.id && widget.taskId == null,
                    onTap: () => Navigator.pop(context, ProjectPick(p.id, null)),
                  ),
                  for (final t in catalog.tasksOf(p.id))
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 56, right: 16),
                      title: Text(t.name),
                      selected: widget.taskId == t.id,
                      onTap: () => Navigator.pop(context, ProjectPick(p.id, t.id)),
                    ),
                ],
              ],
            ]),
          ),
        ]),
      ),
      actions: [
        if (session.isManager)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l.createProject),
            onPressed: () async {
              final name = await promptText(context, title: l.newProject, label: l.name, initial: _query);
              if (name == null || name.trim().isEmpty || !context.mounted) return;
              final id = await catalogRepo.createProject(
                session.workspaceId!,
                ProjectsCompanion.insert(workspaceId: session.workspaceId!, name: name),
              );
              if (context.mounted) Navigator.pop(context, ProjectPick(id, null));
            },
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ],
    );
  }
}

Future<List<String>?> showTagPicker(BuildContext context, List<String> selected) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TagPickerDialog(selected: selected),
  );
}

class _TagPickerDialog extends StatefulWidget {
  const _TagPickerDialog({required this.selected});
  final List<String> selected;

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  late final Set<String> _selected = widget.selected.toSet();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final tags = catalog.activeTags.where((t) => t.name.toLowerCase().contains(_query.toLowerCase())).toList();
    final exact = catalog.activeTags.any((t) => t.name.toLowerCase() == _query.trim().toLowerCase());
    return AlertDialog(
      title: Text(l.tags),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.searchTags),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final t in tags)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(t.id),
                  title: Row(children: [ColorDot(t.color), const SizedBox(width: 8), Flexible(child: Text(t.name))]),
                  onChanged: (v) => setState(() => v == true ? _selected.add(t.id) : _selected.remove(t.id)),
                ),
              if (session.isManager && _query.trim().isNotEmpty && !exact)
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l.createTagNamed(_query.trim())),
                  onTap: () async {
                    final id = await catalogRepo.createTag(session.workspaceId!, _query.trim());
                    setState(() {
                      _selected.add(id);
                      _query = '';
                    });
                  },
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _selected.toList()), child: Text(l.apply)),
      ],
    );
  }
}

Future<String?> promptText(BuildContext context, {required String title, required String label, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(ctx.l10n.save)),
      ],
    ),
  );
}
