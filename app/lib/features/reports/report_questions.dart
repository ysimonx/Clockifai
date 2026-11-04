import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/billing_time.dart';
import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../invoices/invoices_page.dart' show showInvoice;
import 'report_model.dart';

/// Rapports par questions (plans/13-ux-moderne.md, lot 7) : questions toutes faites, comparaison avec la période
/// précédente, temps prêt à facturer et facture en un clic.

/// La période d'avant, de même nature : semaine, mois ou année civils, sinon le même nombre de jours.
DateTimeRange previousRange(DateTimeRange range, RangePreset preset) => switch (preset) {
      RangePreset.thisMonth || RangePreset.lastMonth =>
        DateTimeRange(start: DateTime(range.start.year, range.start.month - 1), end: range.start),
      RangePreset.thisYear => DateTimeRange(start: DateTime(range.start.year - 1), end: range.start),
      _ => DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day - range.end.difference(range.start).inDays),
          end: range.start),
    };

/// « +12 % », « −8 % », « = » ; null sans base de comparaison.
String? deltaPercent(num now, num before) {
  if (before == 0) return null;
  final p = ((now - before) / before * 100).round();
  return p == 0 ? '=' : (p > 0 ? '+$p %' : '−${-p} %');
}

/// Temps facturable pas encore facturé, par client, avec « Facturer » (managers ; douze derniers mois).
class ReadyToBill extends StatefulWidget {
  const ReadyToBill({super.key});

  @override
  State<ReadyToBill> createState() => _ReadyToBillState();
}

class _ReadyToBillState extends State<ReadyToBill> {
  late final DateTime _from = DateTime(DateTime.now().year - 1, DateTime.now().month, DateTime.now().day);
  Future<Set<String>>? _invoiced;
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final ws = session.workspace!;
    final locale = context.localeTag;
    return StreamBuilder<List<EntryRow>>(
      stream: entriesRepo.watchEntries(workspaceId: ws.id, from: _from, to: DateTime.now().add(const Duration(days: 1))),
      builder: (context, snap) {
        // Relu à chaque changement des entrées (une facture vient peut-être d'en prendre).
        _invoiced = modulesRepo.invoicedEntryIds(ws.id);
        return FutureBuilder<Set<String>>(
          future: _invoiced,
          builder: (context, inv) {
            final invoiced = inv.data ?? const <String>{};
            final calc = ReportCalculator(catalog: catalog, roundingMinutes: ws.roundingMinutes, applyRounding: true);
            final rows = snap.data ?? const <EntryRow>[];
            final billed = billedSeconds([for (final r in rows) if (r.entry.billable) r.entry],
                rootOf: (e) => catalog.rootTask(e.taskId)?.id, invoiced: invoiced, now: DateTime.now());
            final byClient = <String, ({int seconds, double amount, DateTime first})>{};
            for (final r in rows) {
              final client = catalog.clientOfProject(r.entry.projectId);
              if (!r.entry.billable || client == null || invoiced.contains(r.entry.id)) continue;
              final seconds = roundSeconds(billed[r.entry.id]!, ws.roundingMinutes);
              if (seconds == 0) continue;
              final prev = byClient[client.id];
              final start = r.entry.startAt.toLocal();
              byClient[client.id] = (
                seconds: (prev?.seconds ?? 0) + seconds,
                amount: (prev?.amount ?? 0) + calc.amountOf(r, seconds: seconds),
                first: prev == null || start.isBefore(prev.first) ? start : prev.first,
              );
            }
            final lines = byClient.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
            return Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.readyToBillTitle, style: theme.textTheme.titleMedium),
                  Text(l.readyToBillHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  if (!snap.hasData || !inv.hasData)
                    const LinearProgressIndicator()
                  else if (lines.isEmpty)
                    ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.check_circle, color: AppColors.of(context).success), title: Text(l.readyToBillNone))
                  else
                    for (final line in lines)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(catalog.client(line.key)?.name ?? ''),
                        subtitle: Text('${formatHm(line.value.seconds)} · ${l.readyToBillSince(dayLabel(context, line.value.first, today: l.today, yesterday: l.yesterday))}'),
                        trailing: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(formatMoney(line.value.amount, catalog.client(line.key)?.currencyOverride ?? ws.currency, locale),
                              style: theme.textTheme.titleSmall),
                          FilledButton.tonal(
                            onPressed: _busy != null ? null : () => _bill(line.key, line.value.first),
                            child: Text(l.invoiceNow),
                          ),
                        ]),
                      ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _bill(String clientId, DateTime first) async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspace!;
    setState(() => _busy = clientId);
    final id = await modulesRepo.createInvoiceFromTime(
      workspaceId: ws.id,
      userId: session.userId!,
      clientId: clientId,
      from: DateTime(first.year, first.month, first.day),
      to: DateTime.now().add(const Duration(days: 1)),
      currency: catalog.client(clientId)?.currencyOverride ?? ws.currency,
      taxPercent: ws.defaultTaxPercent,
      projectNames: catalog.projectNames,
      byTask: true,
      taskNames: catalog.taskPaths,
      roundingMinutes: ws.roundingMinutes,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (id == null) return showSnack(context, l.nothingToInvoice);
    await showInvoice(context, id);
  }
}
