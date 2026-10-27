import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/drift/database.dart';

/// Alertes de budget (plans/18-rapports-presence-alertes-partage.md, lot 2) : projets et tâches à 80 % ou plus de
/// leur budget en heures, de leur budget en montant ou de leur estimation. Le job serveur (`budget_alerts.py`)
/// applique les mêmes règles pour ses emails.

enum BudgetKind { hours, amount, estimate }

class BudgetAlert {
  const BudgetAlert({required this.kind, required this.name, required this.used, required this.budget, this.projectName});
  final BudgetKind kind;

  /// Projet, ou tâche (avec son projet dans [projectName]).
  final String name;
  final String? projectName;

  /// Secondes (heures, estimation) ou centimes (montant).
  final int used;
  final int budget;
  int get percent => (used * 100 / budget).floor();
}

typedef ProjectUsage = ({int seconds, int amountCents});

/// Ce qui atteint [threshold] % : projets non archivés, tâches actives (une tâche compte ses sous-tâches) ; les plus
/// avancés d'abord.
List<BudgetAlert> budgetWatch({
  required List<Project> projects,
  required List<Task> tasks,
  required Map<String?, ProjectUsage> usage,
  required Map<String, int> taskSeconds,
  int threshold = 80,
}) {
  final out = <BudgetAlert>[];
  final open = {for (final p in projects) if (!p.archived && p.deletedAt == null) p.id: p};
  for (final p in open.values) {
    final u = usage[p.id];
    final hours = p.budgetHours;
    if (hours != null && hours > 0) {
      out.add(BudgetAlert(kind: BudgetKind.hours, name: p.name, used: u?.seconds ?? 0, budget: hours * 3600));
    }
    final amount = p.budgetAmountCents;
    if (amount != null && amount > 0) {
      out.add(BudgetAlert(kind: BudgetKind.amount, name: p.name, used: u?.amountCents ?? 0, budget: amount));
    }
  }
  for (final t in tasks) {
    final estimate = t.estimateSeconds;
    final project = open[t.projectId];
    if (estimate == null || estimate <= 0 || project == null || t.status != 'active' || t.deletedAt != null) continue;
    var used = taskSeconds[t.id] ?? 0;
    for (final s in tasks) {
      if (s.parentId == t.id && s.deletedAt == null) used += taskSeconds[s.id] ?? 0;
    }
    out.add(BudgetAlert(kind: BudgetKind.estimate, name: t.name, projectName: project.name, used: used, budget: estimate));
  }
  return out.where((a) => a.used * 100 >= a.budget * threshold).toList()..sort((a, b) => b.percent.compareTo(a.percent));
}

/// Heures à une décimale au plus (« 120 h », « 656,5 h »).
String budgetHours(int seconds, String locale) => '${NumberFormat('#,##0.#', locale).format(seconds / 3600)} h';

/// Montant en unités, sans décimales (« 12 450 € »).
String budgetMoney(int cents, String currency, String locale) => formatMoney((cents / 100).roundToDouble(), currency, locale);

/// « 92 % du budget en heures (184 h sur 200 h) ».
String budgetAlertText(BuildContext context, BudgetAlert a, String currency) {
  final l = context.l10n;
  final locale = context.localeTag;
  String h(int s) => budgetHours(s, locale);
  return switch (a.kind) {
    BudgetKind.hours => l.watchHours(a.percent, h(a.used), h(a.budget)),
    BudgetKind.amount => l.watchAmount(a.percent, budgetMoney(a.used, currency, locale), budgetMoney(a.budget, currency, locale)),
    BudgetKind.estimate => l.watchEstimate(a.percent, h(a.used), h(a.budget)),
  };
}

/// « À surveiller », en tête de Projets pour les managers ; rien s'il n'y a rien.
class BudgetWatchCard extends StatelessWidget {
  const BudgetWatchCard({super.key, required this.alerts, required this.currency});
  final List<BudgetAlert> alerts;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final warning = AppColors.of(context).warning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.watchList, style: theme.textTheme.titleMedium),
          Text(l.watchListHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 4),
          for (final a in alerts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.percent >= 100 ? Icons.error_outline : Icons.warning_amber_outlined,
                  color: a.percent >= 100 ? theme.colorScheme.error : warning),
              title: Text(a.projectName == null ? a.name : '${a.projectName} › ${a.name}'),
              subtitle: Text(budgetAlertText(context, a, currency)),
            ),
        ]),
      ),
    );
  }
}
