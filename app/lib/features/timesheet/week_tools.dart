import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../today/day_plan.dart' show addDays, atMinute, dayKey, minuteOf;

/// La semaine (plans/13-ux-moderne.md, lot 5) : une page, trois vues (grille, calendrier, liste), et ce qui la
/// remplit vite : copie de la semaine précédente, remplissage par le planning, vérification avant soumission.

/// Grille (feuille de temps), calendrier, ou liste des entrées de la semaine ; [week] suit d'une vue à l'autre.
class WeekViews extends StatelessWidget {
  const WeekViews({super.key, required this.current, required this.week});
  final String current;
  final DateTime week;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final w = dayKey(week);
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'grid', icon: const Icon(Icons.grid_on_outlined), label: Text(l.weekGrid)),
        ButtonSegment(value: 'calendar', icon: const Icon(Icons.calendar_month_outlined), label: Text(l.calendar)),
        ButtonSegment(value: 'list', icon: const Icon(Icons.view_agenda_outlined), label: Text(l.weekList)),
      ],
      selected: {current},
      onSelectionChanged: (v) => context.go(switch (v.single) {
        'calendar' => '/calendar?week=$w',
        'list' => '/timesheet?view=list&week=$w',
        _ => '/timesheet?week=$w',
      }),
    );
  }
}

/// Minutes prévues au planning pour [projectId] le jour [day] (jours ouvrés seulement).
int plannedMinutes(List<ScheduleAssignment> assignments, String? projectId, DateTime day) {
  if (day.weekday > DateTime.friday) return 0;
  final key = dayKey(day);
  return assignments
      .where((a) => a.projectId == projectId && a.startDate.compareTo(key) <= 0 && a.endDate.compareTo(key) >= 0)
      .fold(0, (s, a) => s + (a.hoursPerDay * 60).round());
}

Future<List<EntryRow>> _entriesOf(String workspaceId, String userId, DateTime from, DateTime to) =>
    entriesRepo.watchEntries(workspaceId: workspaceId, userId: userId, from: from, to: to).first;

/// Copie les entrées de la semaine précédente sur [weekStart], aux mêmes jours et heures ; une entrée déjà présente
/// (même projet, même description, même début) n'est pas recopiée. Annuler retire les copies.
Future<bool> copyPreviousWeek(BuildContext context, {required String userId, required DateTime weekStart}) =>
    _copyEntries(context, userId: userId, from: addDays(weekStart, -7), to: weekStart, days: 7, empty: context.l10n.weekNothingToCopy);

/// « Comme vendredi » (lot 9) : les entrées du jour [from] recopiées sur [to], aux mêmes heures.
Future<bool> copyDay(BuildContext context, {required String userId, required DateTime from, required DateTime to}) =>
    _copyEntries(context, userId: userId, from: from, to: to, days: 1, empty: context.l10n.dayNothingToCopy);

/// Copie [days] jours d'entrées de [from] vers [to] ; ni jour verrouillé ou approuvé, ni doublon.
Future<bool> _copyEntries(BuildContext context,
    {required String userId, required DateTime from, required DateTime to, required int days, required String empty}) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final ws = session.workspace!;
  final previous = await _entriesOf(ws.id, userId, from, addDays(from, days));
  final current = await _entriesOf(ws.id, userId, to, addDays(to, days));
  final taken = {for (final r in current) '${r.entry.projectId}|${r.entry.description}|${r.entry.startAt.toLocal()}'};
  final lock = DateTime.tryParse(ws.lockEntriesBefore ?? '');
  // En jours civils (UTC : pas de décalage d'heure d'été).
  final shift = DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  final ids = <String>[];
  for (final r in previous) {
    final e = r.entry;
    if (e.endAt == null) continue;
    final local = e.startAt.toLocal();
    final day = addDays(DateTime(local.year, local.month, local.day), shift);
    final start = atMinute(day, minuteOf(e.startAt, local));
    if (taken.contains('${e.projectId}|${e.description}|$start')) continue;
    if (lock != null && day.isBefore(lock) && !session.isAdmin) continue;
    if (await modulesRepo.isDayApproved(ws.id, userId, day)) continue;
    ids.add(await entriesRepo.createManual(
      workspaceId: ws.id,
      userId: userId,
      start: start,
      end: start.add(e.endAt!.difference(e.startAt)),
      createdBy: session.userId,
      draft: EntryDraft(
        description: e.description,
        projectId: e.projectId,
        taskId: e.taskId,
        billable: e.billable,
        hourlyRateCents: e.hourlyRateCents,
        tagIds: r.tagIds,
      ),
    ));
  }
  if (!context.mounted) return ids.isNotEmpty;
  if (ids.isEmpty) {
    showSnack(context, empty);
    return false;
  }
  showUndo(context, l.entriesDuplicated(ids.length), () => entriesRepo.deleteMany(ids));
  return true;
}

/// Complète chaque jour ouvré passé (aujourd'hui compris) jusqu'aux heures prévues au planning, projet par projet
/// (feuille de temps : nouvelle entrée après la dernière du jour). Annuler retire ce qui a été ajouté.
Future<bool> fillFromPlanning(BuildContext context,
    {required String userId, required DateTime weekStart, required List<ScheduleAssignment> assignments}) async {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final ws = session.workspace!;
  final weekEnd = addDays(weekStart, 7);
  final rows = await _entriesOf(ws.id, userId, weekStart, weekEnd);
  final before = {for (final r in rows) r.entry.id};
  final lock = DateTime.tryParse(ws.lockEntriesBefore ?? '');
  final today = DateTime.now();
  for (var i = 0; i < 7; i++) {
    final day = addDays(weekStart, i);
    if (day.isAfter(today)) break;
    if (lock != null && day.isBefore(lock) && !session.isAdmin) continue;
    if (await modulesRepo.isDayApproved(ws.id, userId, day)) continue;
    for (final projectId in {for (final a in assignments) a.projectId}) {
      final planned = plannedMinutes(assignments, projectId, day);
      if (planned == 0) continue;
      final logged = rows
          .where((r) => r.entry.projectId == projectId && r.entry.endAt != null && dayKey(r.entry.startAt.toLocal()) == dayKey(day))
          .fold(0, (s, r) => s + r.entry.endAt!.difference(r.entry.startAt).inMinutes);
      if (logged >= planned) continue;
      await entriesRepo.setDayTotal(
        workspaceId: ws.id,
        userId: userId,
        projectId: projectId,
        dayLocal: day,
        targetSeconds: planned * 60,
        billable: catalog.billableFor(projectId: projectId, userId: userId),
        hourlyRateCents: catalog.rateFor(projectId: projectId, userId: userId),
        createdBy: session.userId,
      );
    }
  }
  final added = [for (final r in await _entriesOf(ws.id, userId, weekStart, weekEnd)) if (!before.contains(r.entry.id)) r.entry.id];
  if (!context.mounted) return added.isNotEmpty;
  if (added.isEmpty) {
    showSnack(context, l.weekNothingToFill);
    return false;
  }
  showUndo(context, l.weekFilled(added.length), () => entriesRepo.deleteMany(added));
  return true;
}

/// Ce qui mérite un coup d'œil avant de soumettre la semaine.
enum WeekIssueKind { emptyDay, belowPlan, noProject, noDescription, running, overlap }

class WeekIssue {
  const WeekIssue(this.kind, {this.day, this.count = 0, this.minutes = 0, this.planned = 0});
  final WeekIssueKind kind;
  final DateTime? day;
  final int count;
  final int minutes;
  final int planned;
}

/// Vérification de la semaine [days] (calcul pur) : jours ouvrés passés sans temps ou sous le planning, entrées sans
/// projet ou sans description quand le workspace les exige, chronomètres en cours, entrées qui se chevauchent.
List<WeekIssue> weekIssues({
  required List<DateTime> days,
  required List<EntryRow> rows,
  required List<ScheduleAssignment> assignments,
  required DateTime now,
  bool requireProject = false,
  bool requireDescription = false,
}) {
  final issues = <WeekIssue>[];
  final today = DateTime(now.year, now.month, now.day);
  for (final d in days) {
    if (d.isAfter(today) || d.weekday > DateTime.friday) continue;
    final ofDay = rows.where((r) => dayKey(r.entry.startAt.toLocal()) == dayKey(d)).toList();
    final minutes = ofDay.fold(0, (s, r) => s + (r.entry.endAt ?? now).difference(r.entry.startAt).inMinutes);
    final planned = {for (final a in assignments) a.projectId}.fold(0, (s, p) => s + plannedMinutes(assignments, p, d));
    if (minutes == 0) {
      issues.add(WeekIssue(WeekIssueKind.emptyDay, day: d, planned: planned));
    } else if (planned > 0 && minutes < planned) {
      issues.add(WeekIssue(WeekIssueKind.belowPlan, day: d, minutes: minutes, planned: planned));
    }
  }
  final noProject = rows.where((r) => r.entry.projectId == null).length;
  if (requireProject && noProject > 0) issues.add(WeekIssue(WeekIssueKind.noProject, count: noProject));
  final noDescription = rows.where((r) => r.entry.description.trim().isEmpty).length;
  if (requireDescription && noDescription > 0) issues.add(WeekIssue(WeekIssueKind.noDescription, count: noDescription));
  final running = rows.where((r) => r.entry.endAt == null).length;
  if (running > 0) issues.add(WeekIssue(WeekIssueKind.running, count: running));
  final sorted = [...rows]..sort((a, b) => a.entry.startAt.compareTo(b.entry.startAt));
  var overlaps = 0;
  for (var i = 1; i < sorted.length; i++) {
    final prevEnd = sorted[i - 1].entry.endAt ?? now.toUtc();
    if (sorted[i].entry.startAt.isBefore(prevEnd)) overlaps++;
  }
  if (overlaps > 0) issues.add(WeekIssue(WeekIssueKind.overlap, count: overlaps));
  return issues;
}
