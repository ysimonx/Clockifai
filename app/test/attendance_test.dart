import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/features/reports/attendance.dart';
import 'package:flutter_test/flutter_test.dart';

TimeEntry entry(DateTime start, DateTime? end, {String user = 'u1'}) => TimeEntry(
      id: '${start.millisecondsSinceEpoch}-$user',
      workspaceId: 'ws',
      userId: user,
      description: '',
      startAt: start.toUtc(),
      endAt: end?.toUtc(),
      billable: true,
      locked: false,
    );

TimeOffRequest absence(String start, String end, double amount, {String policy = 'days', String status = 'approved'}) =>
    TimeOffRequest(
      id: '$start-$policy',
      workspaceId: 'ws',
      userId: 'u1',
      policyId: policy,
      startDate: start,
      endDate: end,
      amount: amount,
      halfDay: false,
      status: status,
    );

void main() {
  // Semaine du lundi 2 au dimanche 8 novembre 2026.
  final monday = DateTime(2026, 11, 2);
  final now = DateTime(2026, 11, 9, 12);
  List<AttendanceDay> week(List<TimeEntry> entries,
          {Set<String> holidays = const {}, List<TimeOffRequest> requests = const [], DateTime? at}) =>
      attendanceOf(
        entries: entries,
        from: monday,
        to: DateTime(2026, 11, 9),
        now: at ?? now,
        capacityHours: 7,
        holidays: holidays,
        requests: requests,
        policyUnits: const {'days': 'days', 'hours': 'hours'},
      );
  DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

  test('arrivée, départ, pauses ; deux chronomètres en parallèle ne comptent pas double', () {
    final days = week([
      entry(at(2, 8, 30), at(2, 12)),
      entry(at(2, 11), at(2, 12, 30)), // chevauche la première
      entry(at(2, 13, 30), at(2, 17, 30)),
    ]);
    final d = days.first;
    expect((d.arrival, d.departure), (at(2, 8, 30), at(2, 17, 30)));
    expect(d.worked, (4 * 60 + 4 * 60) * 60); // 8:30–12:30 et 13:30–17:30
    expect(d.breaks, 3600);
    expect(d.expected, 7 * 3600);
    expect(d.delta, 3600);
  });

  test('jours prévus sans entrée affichés, week-end seulement s\'il y a du temps', () {
    final days = week([entry(at(7, 9), at(7, 11))]);
    expect([for (final d in days) d.day.day], [2, 3, 4, 5, 6, 7]);
    expect(days.first.worked, 0);
    expect(days.first.delta, -7 * 3600);
    final saturday = days.last;
    expect((saturday.expected, saturday.delta), (0, 2 * 3600));
  });

  test('jour férié : rien de prévu', () {
    final days = week(const [], holidays: {'2026-11-03'});
    final tuesday = days.firstWhere((d) => d.day.day == 3);
    expect((tuesday.holiday, tuesday.expected), (true, 0));
  });

  test('absences : jour entier, demi-journée, heures réparties sur les jours ouvrés', () {
    final days = week(const [], requests: [
      absence('2026-11-04', '2026-11-04', 1),
      absence('2026-11-05', '2026-11-05', 0.5),
      absence('2026-11-06', '2026-11-09', 6, policy: 'hours'), // vendredi et lundi suivant : 3 h par jour
      absence('2026-11-02', '2026-11-02', 1, status: 'pending'), // pas encore approuvée
    ]);
    int expected(int day) => days.firstWhere((d) => d.day.day == day).expected;
    expect(expected(2), 7 * 3600);
    expect(expected(4), 0);
    expect(expected(5), (3.5 * 3600).round());
    expect(expected(6), 4 * 3600);
    expect(days.firstWhere((d) => d.day.day == 4).absent, isTrue);
  });

  test('une entrée appartient au jour où elle commence ; une entrée en cours compte jusqu\'à maintenant', () {
    final days = week([entry(at(4, 22), at(5, 2)), entry(at(5, 9), null)], at: at(5, 10));
    expect([for (final d in days) d.day.day], [2, 3, 4, 5], reason: 'rien après aujourd\'hui');
    expect(days[2].worked, 4 * 3600);
    expect(days[3].worked, 3600);
  });

  test('par personne : totaux, personne sans jour retenue omise, CSV', () {
    final people = attendanceOfPeople(
      userIds: ['u1', 'u2'],
      entries: [entry(at(2, 9), at(2, 18))],
      from: monday,
      to: DateTime(2026, 11, 3),
      now: now,
      capacityOf: (uid) => uid == 'u1' ? 8 : 0,
      holidays: const {},
    );
    expect(people.map((p) => (p.userId, p.worked, p.expected, p.delta)), [('u1', 9 * 3600, 8 * 3600, 3600)]);
    final csv = attendanceCsv(people, (_) => 'Léa');
    expect(csv.split('\n')[1], '"Léa";2026-11-02;09:00;18:00;0.00;9.00;8.00;1.00;');
  });
}
