import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/teammates.dart' show memberName;
import '../../data/drift/database.dart';
import '../time_off/time_off_page.dart' show workingDays;

/// Présence (plans/18-rapports-presence-alertes-partage.md, lot 1) : arrivée, départ, temps travaillé et heures sup
/// par personne et par jour, calculés dans l'app à partir des entrées, de la capacité, des jours fériés et des
/// absences approuvées.

/// Un jour d'une personne. [worked] : union des intervalles (deux chronomètres en parallèle ne comptent pas double) ;
/// [breaks] : de l'arrivée au départ, le temps sans entrée ; [expected] : capacité du jour, moins les absences.
class AttendanceDay {
  const AttendanceDay({
    required this.day,
    this.arrival,
    this.departure,
    this.worked = 0,
    this.breaks = 0,
    this.expected = 0,
    this.holiday = false,
    this.absent = false,
  });
  final DateTime day;
  final DateTime? arrival;
  final DateTime? departure;
  final int worked;
  final int breaks;
  final int expected;
  final bool holiday;
  final bool absent;
  int get delta => worked - expected;
}

class AttendancePerson {
  const AttendancePerson(this.userId, this.days);
  final String userId;
  final List<AttendanceDay> days;
  int get worked => days.fold(0, (s, d) => s + d.worked);
  int get expected => days.fold(0, (s, d) => s + d.expected);
  int get delta => worked - expected;
}

bool _workingDay(DateTime d, Set<String> holidays) => d.weekday <= 5 && !holidays.contains(dayKey(d));

/// Heures d'absence approuvées de [requests] (ceux de la personne) le jour [day] : la demande est répartie sur ses
/// jours ouvrés, en jours (× [capacityHours]) ou en heures selon la politique ; au plus la capacité.
double absenceHours(DateTime day, List<TimeOffRequest> requests, Map<String, String> policyUnits,
    Set<String> holidays, double capacityHours) {
  if (!_workingDay(day, holidays)) return 0;
  final key = dayKey(day);
  var hours = 0.0;
  for (final r in requests) {
    if (r.status != 'approved' || r.deletedAt != null) continue;
    if (key.compareTo(r.startDate) < 0 || key.compareTo(r.endDate) > 0) continue;
    final days = workingDays(parseDay(r.startDate), parseDay(r.endDate), holidays);
    if (days == 0) continue;
    final perDay = r.amount / days;
    hours += policyUnits[r.policyId] == 'hours' ? perDay : perDay * capacityHours;
  }
  return hours.clamp(0, capacityHours).toDouble();
}

/// Présence d'une personne du jour [from] (inclus) au jour [to] (exclu), sans aller au-delà d'aujourd'hui ([now]).
/// Un jour sans entrée n'apparaît que s'il était prévu. Une entrée appartient au jour où elle commence ; une entrée en
/// cours compte jusqu'à [now].
List<AttendanceDay> attendanceOf({
  required List<TimeEntry> entries,
  required DateTime from,
  required DateTime to,
  required DateTime now,
  required double capacityHours,
  required Set<String> holidays,
  List<TimeOffRequest> requests = const [],
  Map<String, String> policyUnits = const {},
}) {
  final byDay = <String, List<TimeEntry>>{};
  for (final e in entries) {
    if (e.deletedAt != null) continue;
    byDay.putIfAbsent(dayKey(e.startAt.toLocal()), () => []).add(e);
  }
  final last = addDays(startOfDay(now), 1);
  final end = to.isBefore(last) ? to : last;
  final out = <AttendanceDay>[];
  for (var d = startOfDay(from); d.isBefore(end); d = addDays(d, 1)) {
    final key = dayKey(d);
    final holiday = d.weekday <= 5 && holidays.contains(key);
    final absence = absenceHours(d, requests, policyUnits, holidays, capacityHours);
    final expected = _workingDay(d, holidays) ? ((capacityHours - absence) * 3600).round() : 0;
    final list = byDay[key] ?? const <TimeEntry>[];
    if (list.isEmpty) {
      if (expected > 0 || holiday || absence > 0) {
        out.add(AttendanceDay(day: d, expected: expected, holiday: holiday, absent: absence > 0));
      }
      continue;
    }
    final spans = [
      for (final e in list) (e.startAt.toLocal(), (e.endAt ?? now).toLocal()),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var worked = 0;
    DateTime? curStart, curEnd;
    for (final (s, e) in spans) {
      if (!e.isAfter(s)) continue;
      if (curEnd == null || s.isAfter(curEnd)) {
        if (curStart != null) worked += curEnd!.difference(curStart).inSeconds;
        curStart = s;
        curEnd = e;
      } else if (e.isAfter(curEnd)) {
        curEnd = e;
      }
    }
    if (curStart != null) worked += curEnd!.difference(curStart).inSeconds;
    final arrival = spans.first.$1;
    final departure = spans.map((s) => s.$2).reduce((a, b) => a.isAfter(b) ? a : b);
    out.add(AttendanceDay(
      day: d,
      arrival: arrival,
      departure: departure,
      worked: worked,
      breaks: (departure.difference(arrival).inSeconds - worked).clamp(0, 1 << 31),
      expected: expected,
      holiday: holiday,
      absent: absence > 0,
    ));
  }
  return out;
}

/// Présence de [userIds] (dans cet ordre) ; une personne sans aucun jour retenu est omise.
List<AttendancePerson> attendanceOfPeople({
  required List<String> userIds,
  required List<TimeEntry> entries,
  required DateTime from,
  required DateTime to,
  required DateTime now,
  required double Function(String userId) capacityOf,
  required Set<String> holidays,
  List<TimeOffRequest> requests = const [],
  Map<String, String> policyUnits = const {},
}) =>
    [
      for (final uid in userIds)
        AttendancePerson(
          uid,
          attendanceOf(
            entries: [for (final e in entries) if (e.userId == uid) e],
            from: from,
            to: to,
            now: now,
            capacityHours: capacityOf(uid),
            holidays: holidays,
            requests: [for (final r in requests) if (r.userId == uid) r],
            policyUnits: policyUnits,
          ),
        ),
    ].where((p) => p.days.isNotEmpty).toList();

/// « +1:30 », « −0:45 », « 0:00 ».
String formatDelta(int seconds) => seconds > 0 ? '+${formatHm(seconds)}' : (seconds < 0 ? '−${formatHm(-seconds)}' : formatHm(0));

/// Présence en CSV (une ligne par personne et par jour), fait dans l'app, hors ligne.
String attendanceCsv(List<AttendancePerson> people, String Function(String userId) nameOf) {
  final csv = StringBuffer('\uFEFFPerson;Date;Arrival;Departure;Breaks (h);Worked (h);Expected (h);Difference (h);Note\n');
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  String h(int seconds) => (seconds / 3600).toStringAsFixed(2);
  String hm(DateTime? t) => t == null ? '' : DateFormat('HH:mm').format(t);
  for (final p in people) {
    for (final d in p.days) {
      csv.writeln([
        q(nameOf(p.userId)),
        dayKey(d.day),
        hm(d.arrival),
        hm(d.departure),
        h(d.breaks),
        h(d.worked),
        h(d.expected),
        h(d.delta),
        d.holiday ? 'holiday' : (d.absent ? 'time off' : ''),
      ].join(';'));
    }
  }
  return csv.toString();
}

/// Jours fériés, absences et unités des politiques du workspace, pour l'export.
Future<({Set<String> holidays, List<TimeOffRequest> requests, Map<String, String> policyUnits})> attendanceSources(
        String workspaceId) async =>
    (
      holidays: {for (final h in await modulesRepo.watchHolidays(workspaceId).first) h.date},
      requests: await modulesRepo.watchRequests(workspaceId).first,
      policyUnits: {for (final p in await modulesRepo.watchPolicies(workspaceId).first) p.id: p.unit},
    );

/// Vue « Présence » des rapports : une carte par personne, un jour par ligne.
class AttendanceReport extends StatelessWidget {
  const AttendanceReport({super.key, required this.entries, required this.userIds, required this.range});

  /// Entrées visibles de la période, tous projets confondus.
  final List<TimeEntry> entries;
  final List<String> userIds;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final ws = context.read<SessionController>().workspaceId!;
    final catalog = context.watch<CatalogController>();
    return StreamBuilder<List<Holiday>>(
      stream: modulesRepo.watchHolidays(ws),
      builder: (context, holidays) => StreamBuilder<List<TimeOffRequest>>(
        stream: modulesRepo.watchRequests(ws),
        builder: (context, requests) => StreamBuilder<List<TimeOffPolicy>>(
          stream: modulesRepo.watchPolicies(ws),
          builder: (context, policies) {
            final people = attendanceOfPeople(
              userIds: userIds,
              entries: entries,
              from: range.start,
              to: range.end,
              now: DateTime.now(),
              capacityOf: (uid) => catalog.memberOf(uid)?.capacityHoursPerDay ?? 7,
              holidays: {for (final h in holidays.data ?? const <Holiday>[]) h.date},
              requests: requests.data ?? const [],
              policyUnits: {for (final p in policies.data ?? const <TimeOffPolicy>[]) p.id: p.unit},
            );
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.attendanceHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 8),
              if (people.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.noDataForPeriod)))
              else
                // Une seule personne : ses jours d'emblée ; une équipe : une ligne par personne, à déplier.
                for (final p in people)
                  _PersonCard(person: p, name: memberName(catalog.memberOf(p.userId)), expanded: people.length == 1),
            ]);
          },
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.name, required this.expanded});
  final AttendancePerson person;
  final String name;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final locale = context.localeTag;
    Color deltaColor(int s) => s > 0 ? colors.success : (s < 0 ? theme.colorScheme.error : theme.colorScheme.outline);
    String time(DateTime? t) => t == null ? '' : timeLabel(context, t);
    final delta = person.delta;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        title: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(name, style: theme.textTheme.titleSmall),
          Text('${l.attendanceWorked} ${formatHm(person.worked)} · ${l.attendanceExpected} ${formatHm(person.expected)}',
              style: theme.textTheme.bodySmall),
          Text(
            delta >= 0 ? l.attendanceOvertime(formatHm(delta)) : l.attendanceMissing(formatHm(-delta)),
            style: theme.textTheme.bodySmall?.copyWith(color: deltaColor(delta), fontWeight: FontWeight.w600),
          ),
        ]),
        children: [
          // Toute la largeur de la carte, défilement horizontal sur un écran étroit.
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth),
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 0,
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 48,
                  columns: [
                    DataColumn(label: Text(l.day)),
                    DataColumn(label: Text(l.attendanceArrival)),
                    DataColumn(label: Text(l.attendanceDeparture)),
                    DataColumn(label: Text(l.attendanceBreaks), numeric: true),
                    DataColumn(label: Text(l.attendanceWorked), numeric: true),
                    DataColumn(label: Text(l.attendanceExpected), numeric: true),
                    DataColumn(label: Text(l.attendanceDifference), numeric: true),
                  ],
                  rows: [
                    for (final d in person.days)
                      DataRow(cells: [
                        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(DateFormat.MMMEd(locale).format(d.day)),
                          if (d.holiday || d.absent)
                            Text(d.holiday ? l.attendanceHoliday : l.attendanceTimeOff,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        ])),
                        DataCell(Text(time(d.arrival))),
                        DataCell(Text(time(d.departure))),
                        DataCell(Text(d.breaks == 0 ? '' : formatHm(d.breaks))),
                        DataCell(Text(d.worked == 0 ? '' : formatHm(d.worked))),
                        DataCell(Text(d.expected == 0 ? '' : formatHm(d.expected))),
                        DataCell(Text(formatDelta(d.delta), style: TextStyle(color: deltaColor(d.delta)))),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
