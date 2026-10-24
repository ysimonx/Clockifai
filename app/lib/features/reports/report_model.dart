import '../../core/catalog.dart';
import '../../data/repositories/time_entry_repository.dart';

enum GroupBy { project, client, user, tag, day, description }

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
    final rate = r.entry.hourlyRateCents;
    if (!r.entry.billable || rate == null) return 0;
    return secondsOf(r) / 3600 * rate / 100;
  }

  ({int total, int billable, double amount}) totals(List<EntryRow> rows) {
    var total = 0, billable = 0;
    var amount = 0.0;
    for (final r in rows) {
      final s = secondsOf(r);
      total += s;
      if (r.entry.billable) billable += s;
      amount += amountOf(r);
    }
    return (total: total, billable: billable, amount: amount);
  }

  List<ReportGroup> group(List<EntryRow> rows, GroupBy by, {required String noProject, required String noClient, required String noTag, required String noDescription, required String Function(DateTime) dayLabel}) {
    final map = <String?, ReportGroup>{};
    void add(String? key, String label, EntryRow r, {String? color, double share = 1}) {
      final g = map.putIfAbsent(key, () => ReportGroup(key, label, color: color));
      final s = (secondsOf(r) * share).round();
      g.seconds += s;
      if (r.entry.billable) g.billableSeconds += s;
      g.amount += amountOf(r) * share;
      g.entries += 1;
    }

    for (final r in rows) {
      final e = r.entry;
      switch (by) {
        case GroupBy.project:
          final p = catalog.project(e.projectId);
          add(e.projectId, p?.name ?? noProject, r, color: p?.color);
        case GroupBy.client:
          final c = catalog.clientOfProject(e.projectId);
          add(c?.id, c?.name ?? noClient, r);
        case GroupBy.user:
          add(e.userId, catalog.memberOf(e.userId)?.displayName ?? e.userId.substring(0, 8), r);
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
    if (by == GroupBy.day) {
      list.sort((a, b) => (a.key ?? '').compareTo(b.key ?? ''));
    } else {
      list.sort((a, b) => b.seconds.compareTo(a.seconds));
    }
    return list;
  }
}
