import 'dart:math' as math;

import '../data/drift/database.dart';

/// Temps à facturer (plans/19-tickets-clients.md, lot 4) : deux tâches menées en parallèle s'additionnent, mais un
/// même agent ne facture qu'une fois la tâche que deux de ses sessions mènent en même temps. Le temps des humains et
/// celui sans tâche gardent leur durée.

/// Secondes à facturer de chaque entrée, par id : chaque ligne de facture additionne celles de ses entrées.
/// [rootOf] : la tâche de premier niveau de l'entrée (le ticket), null sans tâche. [invoiced] : les entrées déjà
/// facturées, comptées d'abord pour ne pas refacturer leur plage. [now] : la fin d'une entrée en cours.
Map<String, int> billedSeconds(Iterable<TimeEntry> entries,
    {required String? Function(TimeEntry) rootOf, Set<String> invoiced = const {}, required DateTime now}) {
  final seconds = <String, int>{};
  final shared = <(String, String), List<TimeEntry>>{};
  for (final e in entries) {
    final root = rootOf(e);
    if (e.source == 'agent' && root != null) {
      shared.putIfAbsent((e.userId, root), () => []).add(e);
    } else {
      seconds[e.id] = (e.endAt ?? now).difference(e.startAt).inSeconds;
    }
  }
  int rank(TimeEntry e) => invoiced.contains(e.id) ? 0 : 1;
  for (final list in shared.values) {
    list.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.startAt.compareTo(b.startAt));
    final covered = <(int, int)>[];
    for (final e in list) {
      final fresh = _cover(covered, e.startAt.microsecondsSinceEpoch, (e.endAt ?? now).microsecondsSinceEpoch);
      seconds[e.id] = fresh ~/ Duration.microsecondsPerSecond;
    }
  }
  return seconds;
}

/// Ajoute la plage [start]-[end] à [covered], des plages sans chevauchement, et rend sa part encore non couverte.
int _cover(List<(int, int)> covered, int start, int end) {
  var fresh = end - start;
  var from = start, to = end;
  covered.removeWhere((c) {
    if (c.$2 <= start || end <= c.$1) return false;
    fresh -= math.min(c.$2, end) - math.max(c.$1, start);
    from = math.min(from, c.$1);
    to = math.max(to, c.$2);
    return true;
  });
  covered.add((from, to));
  return fresh;
}
