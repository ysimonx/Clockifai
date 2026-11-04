import 'package:clockifai/core/billing_time.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int hour, [int minute = 0]) => DateTime.utc(2026, 11, 4, hour, minute);

TimeEntry entry(String id, DateTime start, DateTime? end, {String? task, String user = 'claude', String? source = 'agent'}) =>
    TimeEntry(id: id, workspaceId: 'w', userId: user, taskId: task, description: '', startAt: start, endAt: end,
        billable: true, locked: false, source: source);

const parents = {'validation': 'ticket', 'paiement': 'ticket'};

/// La tâche de premier niveau, comme `catalog.rootTask`.
String? rootOf(TimeEntry e) => parents[e.taskId] ?? e.taskId;

Map<String, int> billed(List<TimeEntry> entries, {Set<String> invoiced = const {}, DateTime? now}) =>
    billedSeconds(entries, rootOf: rootOf, invoiced: invoiced, now: now ?? at(23));

int hours(int n) => n * 3600;

void main() {
  test('deux tickets en parallèle s\'additionnent', () {
    expect(billed([entry('a', at(9), at(11), task: 'ENG-1'), entry('b', at(9), at(11), task: 'ENG-2')]),
        {'a': hours(2), 'b': hours(2)});
  });

  test('deux sessions sur le même ticket ne comptent qu\'une fois', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(9), at(11), task: 'ticket')]),
        {'a': hours(2), 'b': 0});
  });

  test('chevauchement partiel : seule la part commune disparaît', () {
    expect(billed([entry('b', at(10), at(12), task: 'ticket'), entry('a', at(9), at(11), task: 'ticket')]),
        {'a': hours(2), 'b': hours(1)});
  });

  test('une entrée comprise dans une autre ne compte pas', () {
    expect(billed([entry('a', at(9), at(12), task: 'ticket'), entry('b', at(10), at(11), task: 'ticket')]),
        {'a': hours(3), 'b': 0});
  });

  test('les sous-tâches d\'une tâche comptent ensemble', () {
    expect(billed([entry('a', at(9), at(11), task: 'validation'), entry('b', at(9), at(11), task: 'paiement')]),
        {'a': hours(2), 'b': 0});
  });

  test('sans ticket : même objectif une fois, deux objectifs additionnés', () {
    expect(billed([entry('a', at(9), at(11), task: 'Refonte'), entry('b', at(9), at(11), task: 'Refonte')]),
        {'a': hours(2), 'b': 0});
    expect(billed([entry('a', at(9), at(11), task: 'Refonte'), entry('b', at(9), at(11), task: 'Audit')]),
        {'a': hours(2), 'b': hours(2)});
  });

  test('sans tâche, chaque session compte', () {
    expect(billed([entry('a', at(9), at(11)), entry('b', at(9), at(11))]), {'a': hours(2), 'b': hours(2)});
  });

  test('les agents de deux pilotes s\'additionnent', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(9), at(11), task: 'ticket', user: 'autre')]),
        {'a': hours(2), 'b': hours(2)});
  });

  test('le temps des humains ne change pas', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket', source: null), entry('b', at(9), at(11), task: 'ticket', source: 'manual')]),
        {'a': hours(2), 'b': hours(2)});
  });

  test('un humain et Claude sur un ticket s\'additionnent', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(9), at(11), task: 'ticket', user: 'moi', source: null)]),
        {'a': hours(2), 'b': hours(2)});
  });

  test('une entrée déjà facturée compte d\'abord', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(9), at(11), task: 'ticket')], invoiced: {'b'})['a'], 0);
  });

  test('entrée déjà facturée commencée après : le début de l\'autre reste à facturer', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(10), at(12), task: 'ticket')], invoiced: {'b'})['a'], hours(1));
  });

  test('entrée en cours : jusqu\'à maintenant', () {
    expect(billed([entry('a', at(9), at(11), task: 'ticket'), entry('b', at(10), null, task: 'ticket')], now: at(12)),
        {'a': hours(2), 'b': hours(1)});
  });

  test('sans chevauchement, chaque entrée garde sa durée, même si elles se touchent', () {
    expect(billed([entry('a', at(9), at(10, 7), task: 'ticket'), entry('b', at(10, 7), at(11), task: 'ticket')]),
        {'a': hours(1) + 7 * 60, 'b': 53 * 60});
  });

  test('trois sessions : les plages couvertes s\'assemblent', () {
    final seconds = billed([
      entry('a', at(9), at(10), task: 'ticket'),
      entry('b', at(11), at(12), task: 'ticket'),
      entry('c', at(9, 30), at(11, 30), task: 'ticket'),
    ]);
    expect(seconds, {'a': hours(1), 'c': 90 * 60, 'b': 30 * 60});
    expect(seconds.values.reduce((a, b) => a + b), hours(3));
  });
}
