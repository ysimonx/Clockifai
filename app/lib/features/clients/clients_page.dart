import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final clients = catalog.clients.where((c) => _showArchived || !c.archived).toList();
    return PageScaffold(
      title: l.clients,
      actions: [
        FilterChip(label: Text(l.showArchived), selected: _showArchived, onSelected: (v) => setState(() => _showArchived = v)),
        const SizedBox(width: 8),
        if (session.isManager)
          FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: Text(l.newClient)),
      ],
      child: clients.isEmpty
          ? EmptyState(icon: Icons.business_outlined, title: l.noClients)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: clients.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = clients[i];
                final count = catalog.projects.where((p) => p.clientId == c.id && !p.archived).length;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                    title: Text(c.name, style: c.archived ? TextStyle(color: Theme.of(context).colorScheme.outline) : null),
                    subtitle: Text([
                      l.projectCount(count),
                      if (c.currencyOverride != null) c.currencyOverride!,
                      if (c.note != null) c.note!,
                    ].join(' · ')),
                    trailing: session.isManager
                        ? PopupMenuButton<String>(
                            onSelected: (v) async {
                              switch (v) {
                                case 'edit':
                                  await _edit(context, c);
                                case 'archive':
                                  await catalogRepo.updateClient(c.id, archived: !c.archived);
                                case 'delete':
                                  if (await confirm(context, title: l.deleteClient, message: l.deleteClientMessage)) {
                                    await catalogRepo.deleteClient(c.id);
                                  }
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'edit', child: Text(l.edit)),
                              PopupMenuItem(value: 'archive', child: Text(c.archived ? l.restore : l.archive)),
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

  Future<void> _edit(BuildContext context, ClientItem? client) async {
    final l = context.l10n;
    final name = TextEditingController(text: client?.name ?? '');
    final note = TextEditingController(text: client?.note ?? '');
    final currency = TextEditingController(text: client?.currencyOverride ?? '');
    final address = TextEditingController(text: client?.address ?? '');
    final email = TextEditingController(text: client?.email ?? '');
    final ws = context.read<SessionController>().workspaceId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(client == null ? l.newClient : l.editClient),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.name)),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.billingEmail)),
            const SizedBox(height: 12),
            TextField(controller: address, maxLines: 3, decoration: InputDecoration(labelText: l.billingAddress)),
            const SizedBox(height: 12),
            TextField(controller: currency, decoration: InputDecoration(labelText: l.currencyOverride, hintText: 'EUR, USD…')),
            const SizedBox(height: 12),
            TextField(controller: note, maxLines: 3, decoration: InputDecoration(labelText: l.note)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (client == null) {
      await catalogRepo.createClient(ws, name: name.text, note: note.text, currency: currency.text, address: address.text, email: email.text);
    } else {
      await catalogRepo.updateClient(client.id, name: name.text, note: note.text, currency: currency.text, address: address.text, email: email.text);
    }
  }
}
