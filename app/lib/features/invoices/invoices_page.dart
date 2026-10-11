import 'package:drift/drift.dart' show Value;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/services_api.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/modules_repository.dart';

String invoiceStatusLabel(BuildContext context, String status) {
  final l = context.l10n;
  return switch (status) {
    'sent' => l.invoiceSent,
    'paid' => l.invoicePaid,
    'void' => l.invoiceVoid,
    _ => l.invoiceDraft,
  };
}

Color invoiceStatusColor(BuildContext context, String status) => switch (status) {
      'sent' => Colors.blue,
      'paid' => Colors.green,
      'void' => Theme.of(context).colorScheme.outline,
      _ => Theme.of(context).colorScheme.tertiary,
    };

/// Facturation (managers) : factures générées depuis le temps facturable non facturé.
class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    if (!session.isManager) return EmptyState(icon: Icons.lock_outline, title: l.managersOnly);
    final locale = context.localeTag;
    return PageScaffold(
      title: l.invoices,
      actions: [FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add), label: Text(l.newInvoice))],
      child: StreamBuilder<List<Invoice>>(
        stream: modulesRepo.watchInvoices(session.workspaceId!),
        builder: (context, snap) {
          final invoices = snap.data ?? const <Invoice>[];
          if (invoices.isEmpty) {
            return EmptyState(icon: Icons.receipt_long_outlined, title: l.noInvoices, message: l.noInvoicesMessage);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: invoices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final inv = invoices[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('${inv.number ?? l.draftNumberPending} · ${catalog.client(inv.clientId)?.name ?? l.noClient}'),
                  subtitle: Text([
                    if (inv.issueDate != null) DateFormat.yMMMd(locale).format(parseDay(inv.issueDate!)),
                    if (inv.dueDate != null) '${l.due} ${DateFormat.yMMMd(locale).format(parseDay(inv.dueDate!))}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Chip(
                      label: Text(invoiceStatusLabel(context, inv.status)),
                      labelStyle: TextStyle(color: invoiceStatusColor(context, inv.status)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 12),
                    Text(formatMoney(inv.totalCents / 100, inv.currency, locale), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  onTap: () => showDialog<void>(context: context, builder: (_) => _InvoiceDialog(invoiceId: inv.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    final clients = catalog.clients.where((c) => !c.archived).toList();
    if (clients.isEmpty) return showSnack(context, l.noClients);
    var clientId = clients.first.id;
    final now = DateTime.now();
    var range = DateTimeRange(start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month).subtract(const Duration(days: 1)));
    final tax = TextEditingController(text: ws.defaultTaxPercent.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final fmt = DateFormat.yMMMd(ctx.localeTag);
        return AlertDialog(
          title: Text(l.newInvoice),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: clientId,
                decoration: InputDecoration(labelText: l.client),
                items: [for (final c in clients) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => clientId = v!),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text('${fmt.format(range.start)} → ${fmt.format(range.end)}'),
                onPressed: () async {
                  final r = await showDateRangePicker(context: ctx, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDateRange: range);
                  if (r != null) setState(() => range = r);
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.taxPercent, suffixText: '%')),
              const SizedBox(height: 8),
              Text(l.newInvoiceHelp, style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.generate)),
          ],
        );
      }),
    );
    if (ok != true) return;
    final client = catalog.client(clientId);
    final id = await modulesRepo.createInvoiceFromTime(
      workspaceId: ws.id,
      userId: session.userId!,
      clientId: clientId,
      from: startOfDay(range.start),
      to: startOfDay(range.end).add(const Duration(days: 1)),
      currency: client?.currencyOverride ?? ws.currency,
      taxPercent: double.tryParse(tax.text.replaceAll(',', '.')) ?? ws.defaultTaxPercent,
      projectNames: {for (final p in catalog.projects) p.id: p.name},
    );
    if (!context.mounted) return;
    if (id == null) return showSnack(context, l.nothingToInvoice);
    await showDialog<void>(context: context, builder: (_) => _InvoiceDialog(invoiceId: id));
  }
}

class _InvoiceDialog extends StatelessWidget {
  const _InvoiceDialog({required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.watch<CatalogController>();
    final locale = context.localeTag;
    return StreamBuilder<List<Invoice>>(
      stream: modulesRepo.watchInvoices(session.workspaceId!),
      builder: (context, invSnap) {
        final inv = (invSnap.data ?? const <Invoice>[]).where((i) => i.id == invoiceId).firstOrNull;
        if (inv == null) return const AlertDialog(content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())));
        String money(num cents) => formatMoney(cents / 100, inv.currency, locale);
        return StreamBuilder<List<InvoiceItem>>(
          stream: modulesRepo.watchItems(invoiceId),
          builder: (context, itSnap) {
            final items = itSnap.data ?? const <InvoiceItem>[];
            // Totaux recalculés localement (identiques au calcul serveur) pour un affichage immédiat hors ligne.
            final subtotal = items.fold<int>(0, (s, i) => s + (i.quantity * i.unitPriceCents).round());
            final discount = (subtotal * inv.discountPercent / 100).round();
            final taxAmount = ((subtotal - discount) * inv.taxPercent / 100).round();
            final editable = inv.status == 'draft';
            return AlertDialog(
              title: Row(children: [
                Expanded(child: Text('${l.invoice} ${inv.number ?? l.draftNumberPending}')),
                DropdownButton<String>(
                  value: inv.status,
                  underline: const SizedBox.shrink(),
                  items: [for (final s in const ['draft', 'sent', 'paid', 'void']) DropdownMenuItem(value: s, child: Text(invoiceStatusLabel(context, s)))],
                  onChanged: (s) => modulesRepo.updateInvoice(inv.id, InvoicesCompanion(status: Value(s!))),
                ),
              ]),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Text('${catalog.client(inv.clientId)?.name ?? l.noClient}'
                        '${inv.periodStart != null ? ' · ${DateFormat.yMMMd(locale).format(parseDay(inv.periodStart!))} – ${DateFormat.yMMMd(locale).format(parseDay(inv.periodEnd!))}' : ''}'),
                    const SizedBox(height: 12),
                    Table(
                      columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.6), 4: FixedColumnWidth(40)},
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                          children: [
                            for (final h in [l.description, l.quantityHours, l.unitPrice, l.amount, ''])
                              Padding(padding: const EdgeInsets.all(6), child: Text(h, style: Theme.of(context).textTheme.labelMedium)),
                          ],
                        ),
                        for (final it in items)
                          TableRow(children: [
                            Padding(padding: const EdgeInsets.all(6), child: Text(it.description)),
                            Padding(padding: const EdgeInsets.all(6), child: Text(it.quantity.toStringAsFixed(2), textAlign: TextAlign.right)),
                            Padding(padding: const EdgeInsets.all(6), child: Text(money(it.unitPriceCents), textAlign: TextAlign.right)),
                            Padding(padding: const EdgeInsets.all(6), child: Text(money((it.quantity * it.unitPriceCents).round()), textAlign: TextAlign.right)),
                            editable
                                ? PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    onSelected: (v) => v == 'edit' ? _editItem(context, inv, it) : modulesRepo.deleteItem(it.id),
                                    itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(l.edit)), PopupMenuItem(value: 'delete', child: Text(l.delete))],
                                  )
                                : const SizedBox.shrink(),
                          ]),
                      ],
                    ),
                    if (editable)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(onPressed: () => _editItem(context, inv, null), icon: const Icon(Icons.add), label: Text(l.addLine)),
                      ),
                    const Divider(),
                    _TotalRow(l.subtotal, money(subtotal)),
                    Row(children: [
                      Expanded(
                        child: _PercentField(
                          label: l.discountPercent,
                          value: inv.discountPercent,
                          enabled: editable,
                          onChanged: (v) => modulesRepo.updateInvoice(inv.id, InvoicesCompanion(discountPercent: Value(v))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PercentField(
                          label: l.taxPercent,
                          value: inv.taxPercent,
                          enabled: editable,
                          onChanged: (v) => modulesRepo.updateInvoice(inv.id, InvoicesCompanion(taxPercent: Value(v))),
                        ),
                      ),
                    ]),
                    if (discount > 0) _TotalRow(l.discount, '− ${money(discount)}'),
                    _TotalRow(l.tax, money(taxAmount)),
                    _TotalRow(l.totalInclTax, money(subtotal - discount + taxAmount), bold: true),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: inv.note ?? '',
                      enabled: editable,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: l.invoiceNote, hintText: l.invoiceNoteHint),
                      onFieldSubmitted: (v) => modulesRepo.updateInvoice(inv.id, InvoicesCompanion(note: Value(v.trim().isEmpty ? null : v.trim()))),
                    ),
                  ]),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    if (await confirm(context, title: l.deleteInvoice, message: l.deleteInvoiceMessage)) {
                      await modulesRepo.deleteInvoice(inv.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: Text(l.delete),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                  onPressed: inv.number == null
                      ? null
                      : () async {
                          try {
                            final bytes = await ServicesApi.download('/api/invoices/${inv.id}/pdf', {'workspace_id': inv.workspaceId});
                            await FileSaver.instance.saveFile(name: inv.number!, bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
                          } catch (e) {
                            if (context.mounted) showSnack(context, l.exportFailed('$e'));
                          }
                        },
                ),
                FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editItem(BuildContext context, Invoice inv, InvoiceItem? it) async {
    final l = context.l10n;
    final desc = TextEditingController(text: it?.description ?? '');
    final qty = TextEditingController(text: (it?.quantity ?? 1).toString());
    final price = TextEditingController(text: ((it?.unitPriceCents ?? 0) / 100).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it == null ? l.addLine : l.edit),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: desc, decoration: InputDecoration(labelText: l.description)),
            const SizedBox(height: 12),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.quantityHours)),
            const SizedBox(height: 12),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.unitPrice, suffixText: inv.currency)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.replaceAll(',', '.')) ?? 1;
    final p = ((double.tryParse(price.text.replaceAll(',', '.')) ?? 0) * 100).round();
    await modulesRepo.saveItem(
      inv.workspaceId,
      inv.id,
      InvoiceItemsCompanion(description: Value(desc.text.trim()), quantity: Value(q), unitPriceCents: Value(p)),
      id: it?.id,
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style, textAlign: TextAlign.right)), const SizedBox(width: 16), SizedBox(width: 140, child: Text(value, style: style, textAlign: TextAlign.right))]),
    );
  }
}

class _PercentField extends StatelessWidget {
  const _PercentField({required this.label, required this.value, required this.enabled, required this.onChanged});
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value.toString(),
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: '%'),
        onFieldSubmitted: (v) {
          final d = double.tryParse(v.replaceAll(',', '.'));
          if (d != null && d >= 0 && d <= 100) onChanged(d);
        },
      );
}
