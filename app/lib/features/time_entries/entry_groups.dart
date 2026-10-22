import '../../data/repositories/time_entry_repository.dart';

/// Entrées similaires d'une même journée, réunies sur une ligne dépliable (comme Clockify).
/// Plan : plans/08-regroupement-entrees.md.
class EntryGroup {
  EntryGroup._(this.key);

  /// Critères communs (voir [similarityKey]) : identifie le groupe d'un rafraîchissement à l'autre.
  final String key;

  /// Les plus récentes d'abord.
  final List<EntryRow> rows = [];

  EntryRow get first => rows.first;
  bool get isSingle => rows.length == 1;
  int get seconds => rows.fold(0, (s, r) => s + r.seconds);
  DateTime get startAt => rows.map((r) => r.entry.startAt).reduce((a, b) => a.isBefore(b) ? a : b);

  /// Dernière fin connue (null si aucune entrée n'est terminée).
  DateTime? get endAt => rows
      .map((r) => r.entry.endAt)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  bool get anyLocked => rows.any((r) => r.entry.locked);
}

/// Description (sans espaces en bout), projet, tâche, tags (en ensemble) et facturable.
/// Le taux horaire et l'auteur de la saisie n'entrent pas en compte.
String similarityKey(EntryRow row) {
  final e = row.entry;
  final tags = row.tagIds.toSet().toList()..sort();
  return [e.description.trim(), e.projectId ?? '', e.taskId ?? '', tags.join(','), e.billable ? '1' : '0'].join('\u0000');
}

/// Regroupe les entrées d'une journée, données les plus récentes d'abord : chaque groupe prend la place
/// de son entrée la plus récente et garde l'ordre de ses entrées.
List<EntryGroup> groupSimilar(List<EntryRow> rows) {
  final groups = <String, EntryGroup>{};
  for (final row in rows) {
    final key = similarityKey(row);
    groups.putIfAbsent(key, () => EntryGroup._(key)).rows.add(row);
  }
  return groups.values.toList();
}
