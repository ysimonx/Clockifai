import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/rate_change.dart';
import '../../data/drift/database.dart';
import '../presence/presence_log.dart' show Site;
import '../presence/presence_settings.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final q = _query.toLowerCase();
    final projects = catalog.projects
        .where((p) => _showArchived || !p.archived)
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (catalog.client(p.clientId)?.name.toLowerCase().contains(q) ?? false))
        .toList();

    return PageScaffold(
      title: l.projects,
      actions: [
        if (session.isManager)
          FilledButton.icon(onPressed: () => showProjectDialog(context), icon: const Icon(Icons.add), label: Text(l.newProject)),
      ],
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.search),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            FilterChip(label: Text(l.showArchived), selected: _showArchived, onSelected: (v) => setState(() => _showArchived = v)),
          ]),
        ),
        Expanded(
          child: StreamBuilder<Map<String?, int>>(
            stream: entriesRepo.watchTotalsByProject(session.workspaceId!, userId: session.isManager ? null : session.userId),
            builder: (context, snap) {
              final totals = snap.data ?? const {};
              if (projects.isEmpty) {
                return EmptyState(icon: Icons.folder_outlined, title: l.noProjects, message: session.isManager ? l.noProjectsMessage : null);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: projects.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ProjectTile(project: projects[i], trackedSeconds: totals[projects[i].id] ?? 0),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.trackedSeconds});
  final Project project;
  final int trackedSeconds;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.read<SessionController>();
    final catalog = context.watch<CatalogController>();
    final client = catalog.client(project.clientId);
    final budget = project.budgetHours;
    final progress = budget == null || budget == 0 ? null : trackedSeconds / (budget * 3600);
    final currency = session.workspace!.currency;
    // Tâches de premier niveau, chacune suivie de ses sous-tâches (plans/16-sous-taches.md).
    final tasks = catalog.tasks.where((t) => t.projectId == project.id && t.parentId == null).toList();
    List<Task> subtasks(Task t) => catalog.tasks.where((s) => s.parentId == t.id).toList();

    Widget taskTile(Task t, {required bool sub}) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: sub ? 40 : 16, right: 8),
          leading: Icon(
              sub ? Icons.subdirectory_arrow_right : (t.status == 'done' ? Icons.check_circle : Icons.radio_button_unchecked),
              size: 18,
              color: sub ? theme.colorScheme.outline : null),
          title: Text(t.name, style: t.status == 'done' ? TextStyle(decoration: TextDecoration.lineThrough, color: theme.colorScheme.outline) : null),
          trailing: session.isManager
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!sub)
                    IconButton(
                      tooltip: l.createSubtask,
                      icon: const Icon(Icons.subdirectory_arrow_right),
                      onPressed: () async {
                        final name = await promptText(context, title: l.newSubtaskIn(t.name), label: l.name);
                        if (name != null && name.trim().isNotEmpty) {
                          await catalogRepo.createTask(project.workspaceId, project.id, name, parentId: t.id);
                        }
                      },
                    ),
                  IconButton(
                    tooltip: t.status == 'done' ? l.reopen : l.markDone,
                    icon: Icon(t.status == 'done' ? Icons.undo : Icons.done),
                    onPressed: () => catalogRepo.updateTask(t.id, status: t.status == 'done' ? 'active' : 'done'),
                  ),
                  IconButton(
                    tooltip: l.rename,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await promptText(context, title: l.rename, label: l.name, initial: t.name);
                      if (name != null && name.trim().isNotEmpty) await catalogRepo.updateTask(t.id, name: name);
                    },
                  ),
                  IconButton(
                    tooltip: l.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => catalogRepo.deleteTask(t.id),
                  ),
                ])
              : null,
        );

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: ColorDot(project.color, size: 14),
        title: Row(children: [
          Flexible(child: Text(project.name, style: TextStyle(fontWeight: FontWeight.w600, color: project.archived ? theme.colorScheme.outline : null))),
          if (project.archived) ...[const SizedBox(width: 8), Chip(label: Text(l.archived), visualDensity: VisualDensity.compact)],
          if (!project.isPublic) ...[const SizedBox(width: 8), Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline)],
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([
            client?.name ?? l.noClient,
            '${l.tracked}: ${formatDecimalHours(trackedSeconds, context.localeTag)} h',
            if (project.hourlyRateCents != null) formatMoney(project.hourlyRateCents! / 100, currency, context.localeTag) + l.perHour,
          ].join(' · ')),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress.clamp(0, 1).toDouble(),
              color: progress > 1 ? theme.colorScheme.error : colorFromHex(project.color),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            Text(l.budgetUsed((progress * 100).round(), budget!), style: theme.textTheme.bodySmall),
          ],
        ]),
        trailing: session.isManager
            ? PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await showProjectDialog(context, project: project);
                    case 'task':
                      final name = await promptText(context, title: l.newTask, label: l.name);
                      if (name != null && name.trim().isNotEmpty) {
                        await catalogRepo.createTask(project.workspaceId, project.id, name);
                      }
                    case 'archive':
                      await catalogRepo.updateProject(project.id, ProjectsCompanion(archived: Value(!project.archived)));
                    case 'delete':
                      await catalogRepo.deleteProject(project.id);
                      if (context.mounted) showUndo(context, l.projectDeleted(project.name), () => catalogRepo.restoreProject(project));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l.edit)),
                  PopupMenuItem(value: 'task', child: Text(l.addTask)),
                  PopupMenuItem(value: 'archive', child: Text(project.archived ? l.restore : l.archive)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              )
            : null,
        children: [
          if (tasks.isEmpty)
            ListTile(dense: true, title: Text(l.noTasks, style: TextStyle(color: theme.colorScheme.outline))),
          for (final t in tasks) ...[
            taskTile(t, sub: false),
            for (final s in subtasks(t)) taskTile(s, sub: true),
          ],
        ],
      ),
    );
  }
}

Future<void> showProjectDialog(BuildContext context, {Project? project}) =>
    showDialog<void>(context: context, builder: (_) => _ProjectDialog(project: project));

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({this.project});
  final Project? project;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late final _rate = TextEditingController(text: _centsToText(widget.project?.hourlyRateCents));
  late final _budget = TextEditingController(text: widget.project?.budgetHours?.toString() ?? '');
  late final _note = TextEditingController(text: widget.project?.note ?? '');
  // Chantier (plan 13, lot 13) : position et rayon, pour la présence détectée par le téléphone.
  late final _site = TextEditingController(
      text: widget.project?.siteLat == null ? '' : formatSite(widget.project!.siteLat!, widget.project!.siteLng!));
  late final _radius = TextEditingController(text: '${widget.project?.siteRadius ?? Site.defaultRadius}');
  late String? _clientId = widget.project?.clientId;
  late String _color = widget.project?.color ?? projectPalette[DateTime.now().millisecond % projectPalette.length];
  late bool _billable = widget.project?.billableDefault ?? true;
  late bool _public = widget.project?.isPublic ?? true;
  /// Temps des agents Claude sur ce projet : nul = comme le workspace (plan 10, D16).
  late bool? _agentBillable = widget.project?.agentBillable;

  static String _centsToText(int? c) => c == null ? '' : (c / 100).toStringAsFixed(2);
  static int? _textToCents(String t) {
    final v = double.tryParse(t.replaceAll(',', '.').trim());
    return v == null ? null : (v * 100).round();
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _budget.dispose();
    _note.dispose();
    _site.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final site = parseSite(_site.text);
    if (_site.text.trim().isNotEmpty && site == null) return;
    final radius = (int.tryParse(_radius.text.trim()) ?? Site.defaultRadius).clamp(30, 5000);
    final ws = context.read<SessionController>().workspaceId!;
    final data = ProjectsCompanion(
      name: Value(_name.text.trim()),
      clientId: Value(_clientId),
      color: Value(_color),
      billableDefault: Value(_billable),
      isPublic: Value(_public),
      agentBillable: Value(_agentBillable),
      hourlyRateCents: Value(_textToCents(_rate.text)),
      budgetHours: Value(int.tryParse(_budget.text.trim())),
      note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
      siteLat: Value(site?.$1),
      siteLng: Value(site?.$2),
      siteRadius: Value(site == null ? null : radius),
    );
    if (widget.project == null) {
      await catalogRepo.createProject(ws, data);
    } else {
      final project = widget.project!;
      await catalogRepo.updateProject(project.id, data);
      final rate = data.hourlyRateCents.value;
      if (rate != project.hourlyRateCents && mounted) {
        final catalog = context.read<CatalogController>();
        await offerRateChange(context,
            projectId: project.id, rateFor: (e) => rate ?? catalog.memberOf(e.userId)?.hourlyRateCents);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final catalog = context.watch<CatalogController>();
    final session = context.read<SessionController>();
    return AlertDialog(
      title: Text(widget.project == null ? l.newProject : l.editProject),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: l.name)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _clientId,
                  decoration: InputDecoration(labelText: l.client),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.noClient)),
                    for (final c in catalog.clients.where((c) => !c.archived || c.id == _clientId))
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _clientId = v),
                ),
              ),
              IconButton(
                tooltip: l.newClient,
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final name = await promptText(context, title: l.newClient, label: l.name);
                  if (name == null || name.trim().isEmpty) return;
                  final id = await catalogRepo.createClient(session.workspaceId!, name: name);
                  setState(() => _clientId = id);
                },
              ),
            ]),
            const SizedBox(height: 16),
            Text(l.color, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ColorPalettePicker(value: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l.hourlyRate, suffixText: '${session.workspace!.currency}${l.perHour}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.budgetHours, suffixText: 'h'),
                ),
              ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(l.billableByDefault), value: _billable, onChanged: (v) => setState(() => _billable = v)),
            if (catalog.agents.isNotEmpty || _agentBillable != null)
              DropdownButtonFormField<bool?>(
                initialValue: _agentBillable,
                decoration: InputDecoration(labelText: l.agentBilling, helperText: l.agentBillableHelp, helperMaxLines: 3),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.agentBillableWorkspace)),
                  DropdownMenuItem(value: true, child: Text(l.billable)),
                  DropdownMenuItem(value: false, child: Text(l.nonBillable)),
                ],
                onChanged: (v) => setState(() => _agentBillable = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.publicProject),
              subtitle: Text(l.publicProjectHelp),
              value: _public,
              onChanged: (v) => setState(() => _public = v),
            ),
            TextField(controller: _note, maxLines: 3, decoration: InputDecoration(labelText: l.note)),
            const SizedBox(height: 12),
            SiteFields(position: _site, radius: _radius),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
