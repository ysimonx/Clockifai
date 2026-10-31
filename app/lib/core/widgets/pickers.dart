import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/drift/database.dart';
import '../catalog.dart';
import '../di.dart';
import '../format.dart';
import '../l10n.dart';
import '../session.dart';
import '../tickets.dart';
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

/// Demande le nom d'une nouvelle tâche du projet [p] (ou d'une sous-tâche de [parent]) et renvoie son id ; une tâche
/// du même nom est reprise plutôt que dupliquée. Nul si l'utilisateur annule.
Future<String?> promptNewTask(BuildContext context, Project p, {String initial = '', Task? parent}) async {
  final l = context.l10n;
  final title = parent == null ? l.newTaskIn(p.name) : l.newSubtaskIn(parent.name);
  final name = (await promptText(context, title: title, label: l.name, initial: initial))?.trim();
  if (name == null || name.isEmpty || !context.mounted) return null;
  return pickOrCreateTask(context, p, name, parent: parent);
}

/// La tâche du ticket [ticket] dans le projet [p] (plans/19-tickets-clients.md) : reprise si elle existe (rouverte
/// par un manager si elle est terminée, plans/20-cloture-des-taches.md), sinon créée sous le nom « ENG-123 · Titre »,
/// le titre étant demandé (facultatif). Nul si l'utilisateur annule.
Future<String?> promptTicketTask(BuildContext context, Project p, TicketRef ticket) async {
  final canReopen = context.read<SessionController>().isManager;
  final existing = context.read<CatalogController>().ticketTask(ticket, projectId: p.id, withDone: canReopen);
  if (existing != null) return _resumed(existing);
  final l = context.l10n;
  final title = await promptText(context, title: l.newTicketTask(ticket.label), label: l.ticketTitle);
  if (title == null || !context.mounted) return null;
  return catalogRepo.createTask(p.workspaceId, p.id, ticketTaskName(ticket, title), ticket: ticket);
}

/// La tâche [name] du projet [p] (ou la sous-tâche de [parent]), créée si elle n'existe pas encore. Un manager
/// reprend aussi une tâche terminée du même nom, qui se rouvre (plans/20-cloture-des-taches.md).
Future<String> pickOrCreateTask(BuildContext context, Project p, String name, {Task? parent}) async {
  final catalog = context.read<CatalogController>();
  final canReopen = context.read<SessionController>().isManager;
  final existing = CatalogController.byStatus(catalog.tasks.where((t) =>
          t.projectId == p.id &&
          t.parentId == parent?.id &&
          (canReopen || t.status == 'active') &&
          t.name.toLowerCase() == name.toLowerCase()))
      .firstOrNull;
  return existing == null ? catalogRepo.createTask(p.workspaceId, p.id, name, parentId: parent?.id) : _resumed(existing);
}

/// L'id de la tâche reprise, rouverte si elle était terminée.
Future<String> _resumed(Task t) async {
  if (t.status == 'done') await catalogRepo.reopenTask(t.id);
  return t.id;
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
  // Tâches dont les sous-tâches sont dépliées (plans/16-sous-taches.md) ; celle de la tâche courante l'est d'office.
  late final Set<String> _expandedTasks = {?context.read<CatalogController>().rootTask(widget.taskId)?.id};

  /// Sélectionne la tâche [name] du projet, en la créant si elle n'existe pas encore.
  Future<void> _pickOrCreateTask(Project p, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = await pickOrCreateTask(context, p, trimmed);
    if (mounted) Navigator.pop(context, ProjectPick(p.id, id));
  }

  Future<void> _promptTask(Project p, String initial, {Task? parent}) async {
    final id = await promptNewTask(context, p, initial: initial, parent: parent);
    if (id != null && mounted) Navigator.pop(context, ProjectPick(p.id, id));
  }

  Future<void> _promptTicketTask(Project p, TicketRef ticket) async {
    final id = await promptTicketTask(context, p, ticket);
    if (id != null && mounted) Navigator.pop(context, ProjectPick(p.id, id));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    final canCreateTasks = session.canCreateTasks;
    final q = _query.trim().toLowerCase();
    // Une URL ou une clé de ticket collée retrouve la tâche du ticket (plans/19-tickets-clients.md).
    final ticket = parseTicket(_query);

    bool nameMatches(Project p) =>
        q.isEmpty ||
        p.name.toLowerCase().contains(q) ||
        (catalog.client(p.clientId)?.name ?? '').toLowerCase().contains(q);
    bool named(Task t) =>
        t.name.toLowerCase().contains(q) || (ticket != null && t.parentId == null && isTicket(ticket, key: t.ticketKey, url: t.ticketUrl));
    // Une tâche répond à la recherche par son nom ou par celui d'une de ses sous-tâches.
    List<Task> matchingTasks(Project p) =>
        q.isEmpty ? const [] : catalog.tasksOf(p.id).where((t) => named(t) || catalog.subtasksOf(t.id).any(named)).toList();
    List<Task> shownSubtasks(Task t) {
      final subs = catalog.subtasksOf(t.id);
      if (_expandedTasks.contains(t.id)) return subs;
      return q.isEmpty ? const [] : subs.where(named).toList();
    }

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
              // La recherche porte sur une tâche (pas sur ce projet) : on la reprend comme nom, ou comme ticket.
              onPressed: () => ticket != null && !nameMatches(p) ? _promptTicketTask(p, ticket) : _promptTask(p, nameMatches(p) ? '' : _query.trim()),
            ),
        ]),
      );
    }

    Widget taskTile(Project p, Task t) {
      final subs = catalog.subtasksOf(t.id);
      final open = _expandedTasks.contains(t.id);
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 56, right: 16),
        title: Text(t.name),
        selected: widget.taskId == t.id,
        onTap: () => Navigator.pop(context, ProjectPick(p.id, t.id)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (subs.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: theme.colorScheme.outline),
              onPressed: () => setState(() => open ? _expandedTasks.remove(t.id) : _expandedTasks.add(t.id)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.subtaskCount(subs.length)),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
              ]),
            ),
          if (canCreateTasks)
            IconButton(
              tooltip: l.createSubtask,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.subdirectory_arrow_right, size: 18),
              onPressed: () => _promptTask(p, '', parent: t),
            ),
        ]),
      );
    }

    Widget subtaskTile(Project p, Task s) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 84, right: 16),
          leading: Icon(Icons.subdirectory_arrow_right, size: 16, color: theme.colorScheme.outline),
          minLeadingWidth: 16,
          title: Text(s.name),
          selected: widget.taskId == s.id,
          onTap: () => Navigator.pop(context, ProjectPick(p.id, s.id)),
        );

    final List<Widget> results;
    if (projects.isEmpty && q.isNotEmpty) {
      // Rien ne correspond : on propose de créer la tâche recherchée dans un projet au choix.
      results = canCreateTasks && catalog.activeProjects.isNotEmpty
          ? [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(ticket != null ? l.createTicketTaskIn(ticket.label) : l.createTaskIn(_query.trim()), style: theme.textTheme.labelLarge),
              ),
              for (final p in catalog.activeProjects)
                ListTile(
                  dense: true,
                  leading: ColorDot(p.color, size: 12),
                  title: Text(p.name, style: TextStyle(color: colorFromHex(p.color), fontWeight: FontWeight.w600)),
                  subtitle: p.clientId == null ? null : Text(catalog.client(p.clientId)?.name ?? ''),
                  trailing: const Icon(Icons.add, size: 18),
                  onTap: () => ticket != null ? _promptTicketTask(p, ticket) : _pickOrCreateTask(p, _query),
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
            for (final t in _expanded.contains(p.id) ? catalog.tasksOf(p.id) : matchingTasks(p)) ...[
              taskTile(p, t),
              for (final s in shownSubtasks(t)) subtaskTile(p, s),
            ],
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
                    if (!mounted) return;
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
