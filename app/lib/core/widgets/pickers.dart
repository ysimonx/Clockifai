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
  // Projets dont toutes les tâches sont dépliées ; celui de la tâche courante l'est d'office.
  late final Set<String> _expanded = {if (widget.taskId != null && widget.projectId != null) widget.projectId!};

  /// Sélectionne la tâche [name] du projet, en la créant si elle n'existe pas encore.
  Future<void> _pickOrCreateTask(Project p, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final existing = context
        .read<CatalogController>()
        .tasksOf(p.id)
        .where((t) => t.name.toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;
    final id = existing?.id ?? await catalogRepo.createTask(p.workspaceId, p.id, trimmed);
    if (mounted) Navigator.pop(context, ProjectPick(p.id, id));
  }

  Future<void> _promptTask(Project p, String initial) async {
    final l = context.l10n;
    final name = await promptText(context, title: l.newTaskIn(p.name), label: l.name, initial: initial);
    if (name != null && mounted) await _pickOrCreateTask(p, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final canCreateTasks = session.canCreateTasks;
    final q = _query.trim().toLowerCase();

    bool nameMatches(Project p) =>
        q.isEmpty ||
        p.name.toLowerCase().contains(q) ||
        (catalog.client(p.clientId)?.name ?? '').toLowerCase().contains(q);
    List<Task> matchingTasks(Project p) =>
        q.isEmpty ? const [] : catalog.tasksOf(p.id).where((t) => t.name.toLowerCase().contains(q)).toList();

    final projects = catalog.activeProjects.where((p) => nameMatches(p) || matchingTasks(p).isNotEmpty).toList();

    // Regroupement par client (sans client en premier).
    final groups = <String?, List<Project>>{};
    for (final p in projects) {
      groups.putIfAbsent(p.clientId, () => []).add(p);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a == null ? -1 : b == null ? 1 : (catalog.client(a)?.name ?? '').compareTo(catalog.client(b)?.name ?? ''));

    Widget projectTile(Project p) {
      final tasks = catalog.tasksOf(p.id);
      final expanded = _expanded.contains(p.id);
      return ListTile(
        dense: true,
        leading: ColorDot(p.color, size: 12),
        title: Text(p.name, style: TextStyle(color: colorFromHex(p.color), fontWeight: FontWeight.w600)),
        selected: widget.projectId == p.id && widget.taskId == null,
        onTap: () => Navigator.pop(context, ProjectPick(p.id, null)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (tasks.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: theme.colorScheme.outline),
              onPressed: () => setState(() => expanded ? _expanded.remove(p.id) : _expanded.add(p.id)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.taskCount(tasks.length)),
                Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
              ]),
            ),
          if (canCreateTasks)
            IconButton(
              tooltip: l.createTask,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              // La recherche porte sur une tâche (pas sur ce projet) : on la reprend comme nom.
              onPressed: () => _promptTask(p, nameMatches(p) ? '' : _query.trim()),
            ),
        ]),
      );
    }

    Widget taskTile(Project p, Task t) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 56, right: 16),
          title: Text(t.name),
          selected: widget.taskId == t.id,
          onTap: () => Navigator.pop(context, ProjectPick(p.id, t.id)),
        );

    final List<Widget> results;
    if (projects.isEmpty && q.isNotEmpty) {
      // Rien ne correspond : on propose de créer la tâche recherchée dans un projet au choix.
      results = canCreateTasks && catalog.activeProjects.isNotEmpty
          ? [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(l.createTaskIn(_query.trim()), style: theme.textTheme.labelLarge),
              ),
              for (final p in catalog.activeProjects)
                ListTile(
                  dense: true,
                  leading: ColorDot(p.color, size: 12),
                  title: Text(p.name, style: TextStyle(color: colorFromHex(p.color), fontWeight: FontWeight.w600)),
                  subtitle: p.clientId == null ? null : Text(catalog.client(p.clientId)?.name ?? ''),
                  trailing: const Icon(Icons.add, size: 18),
                  onTap: () => _pickOrCreateTask(p, _query),
                ),
            ]
          : [ListTile(title: Text(l.noMatch, style: TextStyle(color: theme.colorScheme.outline)))];
    } else {
      results = [
        for (final key in keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              (key == null ? l.noClient : catalog.client(key)?.name ?? '').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          for (final p in groups[key]!) ...[
            projectTile(p),
            for (final t in _expanded.contains(p.id) ? catalog.tasksOf(p.id) : matchingTasks(p)) taskTile(p, t),
          ],
        ],
      ];
    }

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
              ...results,
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
