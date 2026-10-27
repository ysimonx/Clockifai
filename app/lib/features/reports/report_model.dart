import '../../core/catalog.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../../core/widgets/teammates.dart' show memberName;

enum GroupBy { project, task, client, user, tag, day, description }

enum RangePreset { thisWeek, lastWeek, thisMonth, lastMonth, thisYear, custom }

/// Filtre « Humains / Agents » des rapports (agents Claude, plans/10-suivi-claude-code.md §8).
enum MemberKind {
  all,
  humans,
  agents;

  bool accepts(bool isAgent) => switch (this) { all => true, humans => !isAgent, agents => isAgent };

  /// Valeur du paramètre `member_kind` de l'export serveur.
  String? get param => switch (this) { all => null, humans => 'human', agents => 'agent' };
}

/// Ligne de rapport agrégée.
class ReportGroup {
  ReportGroup(this.key, this.label, {this.color});
  final String? key;
  final String label;
  final String? color;
  int seconds = 0;
  int billableSeconds = 0;
  double amount = 0;
  int entries = 0;

  /// Usage IA des entrées d'agent (plan 10, D17) ; coût null tant qu'aucune entrée n'a de tarif connu.
  int aiTokens = 0;
  int? aiCostMicros;

  /// Par tâche : ses sous-tâches (plans/16-sous-taches.md), déjà comptées dans la tâche ; du plus long au plus court.
  final List<ReportGroup> children = [];

  void _add(int s, EntryRow r, double amount, double share) {
    seconds += s;
    if (r.entry.billable) billableSeconds += s;
    this.amount += amount;
    entries += 1;
    aiTokens += (r.aiTokens * share).round();
    if (r.aiCostMicros != null) aiCostMicros = (aiCostMicros ?? 0) + (r.aiCostMicros! * share).round();
  }
}

/// Calcul des rapports à partir des entrées locales (fonctionne hors ligne).
class ReportCalculator {
  ReportCalculator({required this.catalog, required this.roundingMinutes, required this.applyRounding});

  final CatalogController catalog;
  final int roundingMinutes;
  final bool applyRounding;

  int secondsOf(EntryRow r) {
    final s = r.seconds;
    if (!applyRounding || roundingMinutes <= 0) return s;
    final step = roundingMinutes * 60;
    return ((s + step ~/ 2) ~/ step) * step;
  }

  double amountOf(EntryRow r) {
    final rate = catalog.entryRate(r.entry);
    if (!r.entry.billable || rate == null) return 0;
    return secondsOf(r) / 3600 * rate / 100;
  }

  ({int total, int billable, double amount, int aiTokens, int? aiCostMicros}) totals(List<EntryRow> rows) {
    var total = 0, billable = 0, aiTokens = 0;
    int? aiCost;
    var amount = 0.0;
    for (final r in rows) {
      final s = secondsOf(r);
      total += s;
      if (r.entry.billable) billable += s;
      amount += amountOf(r);
      aiTokens += r.aiTokens;
      if (r.aiCostMicros != null) aiCost = (aiCost ?? 0) + r.aiCostMicros!;
    }
    return (total: total, billable: billable, amount: amount, aiTokens: aiTokens, aiCostMicros: aiCost);
  }

  List<ReportGroup> group(List<EntryRow> rows, GroupBy by,
      {required String noProject,
      required String noClient,
      required String noTag,
      required String noDescription,
      required String Function(DateTime) dayLabel,
      String noTask = ''}) {
    final map = <String?, ReportGroup>{};
    ReportGroup add(String? key, String label, EntryRow r, {String? color, double share = 1}) {
      final g = map.putIfAbsent(key, () => ReportGroup(key, label, color: color));
      g._add((secondsOf(r) * share).round(), r, amountOf(r) * share, share);
      return g;
    }

    for (final r in rows) {
      final e = r.entry;
      switch (by) {
        case GroupBy.project:
          final p = catalog.project(e.projectId);
          add(e.projectId, p?.name ?? noProject, r, color: p?.color);
        case GroupBy.task:
          // La tâche compte ses sous-tâches ; chaque sous-tâche a sa ligne dépliable sous la tâche.
          final root = catalog.rootTask(e.taskId);
          final p = catalog.project(e.projectId);
          final g = add(root?.id, root?.name ?? noTask, r, color: p?.color);
          if (root != null && e.taskId != root.id) {
            var child = g.children.where((c) => c.key == e.taskId).firstOrNull;
            if (child == null) g.children.add(child = ReportGroup(e.taskId, catalog.task(e.taskId)?.name ?? '?'));
            child._add(secondsOf(r), r, amountOf(r), 1);
          }
        case GroupBy.client:
          final c = catalog.clientOfProject(e.projectId);
          add(c?.id, c?.name ?? noClient, r);
        case GroupBy.user:
          add(e.userId, memberName(catalog.memberOf(e.userId)), r);
        case GroupBy.tag:
          // Une entrée avec plusieurs tags compte dans chacun (comme Clockify).
          if (r.tagIds.isEmpty) {
            add(null, noTag, r);
          } else {
            for (final t in r.tagIds) {
              final tag = catalog.tag(t);
              add(t, tag?.name ?? '?', r, color: tag?.color);
            }
          }
        case GroupBy.day:
          final d = e.startAt.toLocal();
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          add(key, dayLabel(DateTime(d.year, d.month, d.day)), r);
        case GroupBy.description:
          add(e.description.toLowerCase(), e.description.isEmpty ? noDescription : e.description, r);
      }
    }
    final list = map.values.toList();
    for (final g in list) {
      g.children.sort((a, b) => b.seconds.compareTo(a.seconds));
    }
    if (by == GroupBy.day) {
      list.sort((a, b) => (a.key ?? '').compareTo(b.key ?? ''));
    } else {
      list.sort((a, b) => b.seconds.compareTo(a.seconds));
    }
    return list;
  }
}
