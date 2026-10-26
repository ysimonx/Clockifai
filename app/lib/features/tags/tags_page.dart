import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final tags = catalog.tags;
    return PageScaffold(
      title: l.tags,
      maxWidth: 800,
      actions: [
        if (session.isManager)
          FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: Text(l.newTag)),
      ],
      child: tags.isEmpty
          ? EmptyState(icon: Icons.sell_outlined, title: l.noTags)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tags.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final t = tags[i];
                return Card(
                  child: ListTile(
                    leading: ColorDot(t.color, size: 14),
                    title: Text(t.name, style: t.archived ? TextStyle(color: Theme.of(context).colorScheme.outline) : null),
                    subtitle: t.archived ? Text(l.archived) : null,
                    trailing: session.isManager
                        ? PopupMenuButton<String>(
                            onSelected: (v) async {
                              switch (v) {
                                case 'edit':
                                  await _edit(context, t);
                                case 'archive':
                                  await catalogRepo.updateTag(t.id, archived: !t.archived);
                                case 'delete':
                                  await catalogRepo.deleteTag(t.id);
                                  if (context.mounted) showUndo(context, l.tagDeleted(t.name), () => catalogRepo.restoreTag(t));
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: Text(l.edit)),
                              PopupMenuItem(value: 'archive', child: Text(t.archived ? l.restore : l.archive)),
                              PopupMenuItem(value: 'delete', child: Text(l.delete)),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Future<void> _edit(BuildContext context, Tag? tag) async {
    final l = context.l10n;
    final name = TextEditingController(text: tag?.name ?? '');
    var color = tag?.color ?? '#6B7280';
    final ws = context.read<SessionController>().workspaceId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tag == null ? l.newTag : l.editTag),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.name)),
              const SizedBox(height: 16),
              ColorPalettePicker(value: color, onChanged: (c) => setState(() => color = c)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (tag == null) {
      await catalogRepo.createTag(ws, name.text, color: color);
    } else {
      await catalogRepo.updateTag(tag.id, name: name.text, color: color);
    }
  }
}
