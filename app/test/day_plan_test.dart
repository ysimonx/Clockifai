import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/features/today/day_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Journal automatique (plans/13-ux-moderne.md, lot 11) : journée type, créneaux vides et propositions.
DateTime at(int month, int day, int h, [int m = 0]) => DateTime(2026, month, day, h, m);

TimeEntry entry(String id, DateTime start, DateTime? end, {String desc = '', String? project, String? task, String user = 'me'}) =>
    TimeEntry(id: id, workspaceId: 'w', userId: user, projectId: project, taskId: task, description: desc,
        startAt: start.toUtc(), endAt: end?.toUtc(), billable: true, locked: false);

/// Dix jours travaillés (12 au 23 octobre) : courriels chaque matin, travail varié, pause de 12:30 à 13:30,
/// point hebdo le lundi de 10:30 à 11:30.
List<TimeEntry> history() {
  final out = <TimeEntry>[];
  var n = 0;
  for (var day = 12; day <= 23; day++) {
    final d = DateTime(2026, 10, day);
    if (d.weekday > DateTime.friday) continue;
    out.add(entry('h${n++}', at(10, day, 8, 30), at(10, day, 9), desc: 'Courriels', project: 'int'));
    if (d.weekday == DateTime.monday) {
      out.add(entry('h${n++}', at(10, day, 9), at(10, day, 10, 30), desc: 'Dev $day a', project: 'p1'));
      out.add(entry('h${n++}', at(10, day, 10, 30), at(10, day, 11, 30), desc: 'Point hebdo', project: 'int'));
      out.add(entry('h${n++}', at(10, day, 11, 30), at(10, day, 12, 30), desc: 'Dev $day b', project: 'p1'));
    } else {
      out.add(entry('h${n++}', at(10, day, 9), at(10, day, 12, 30), desc: 'Dev $day', project: 'p1'));
    }
    out.add(entry('h${n++}', at(10, day, 13, 30), at(10, day, 17, 30), desc: 'Dev $day pm', project: 'p1'));
  }
  // Le lundi 5 octobre aussi : trois lundis sur les quatre derniers.
  out.add(entry('h${n++}', at(10, 5, 10, 30), at(10, 5, 11, 30), desc: 'Point hebdo', project: 'int'));
  return out;
}

final now = at(10, 26, 17, 2); // lundi
final mine = [
  entry('m1', at(10, 26, 9), at(10, 26, 10, 30), desc: 'Maquettes', project: 'p2'),
  entry('m2', at(10, 26, 14), at(10, 26, 16, 15), desc: 'Recette', project: 'p1'),
  entry('m3', at(10, 26, 16, 15), null, desc: 'Relecture', project: 'p2'),
];
final claude = [entry('a1', at(10, 26, 10, 35), at(10, 26, 11, 30), desc: 'Rappels par SMS', project: 'p1', task: 't1', user: 'agent')];
final planning = [
  const ScheduleAssignment(id: 's1', workspaceId: 'w', userId: 'me', projectId: 'p1', startDate: '2026-10-26', endDate: '2026-10-30', hoursPerDay: 7),
];

void main() {
  test('journée type tirée de l’historique, sinon valeurs par défaut', () {
    final t = typicalDay(history(), now);
    expect(t.fromHistory, isTrue);
    expect((t.start, t.lunch, t.end, t.target), (510, const Span(750, 810), 1050, 480));
    expect(t.windows, [const Span(510, 750), const Span(810, 1050)]);
    expect(typicalDay(history().take(8).toList(), now), same(TypicalDay.fallback), reason: 'moins de trois jours');
  });

  test('Claude d’abord, puis les habitudes, puis le planning, sur les créneaux libres jusqu’à maintenant', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), agentEntries: claude, planning: planning);
    expect(plan.windows, [const Span(510, 750), const Span(810, 1022)]);
    expect(plan.loggedMinutes, 90 + 135 + 47);
    expect([for (final d in plan.drafts) (d.source, d.span)], [
      (DraftSource.habit, const Span(510, 540)),
      (DraftSource.claude, const Span(635, 690)),
      (DraftSource.planning, const Span(690, 750)),
      (DraftSource.planning, const Span(810, 840)),
    ]);
    final fromClaude = plan.drafts[1];
    expect((fromClaude.description, fromClaude.projectId, fromClaude.taskId), ('Rappels par SMS', 'p1', 't1'));
    expect(fromClaude.reasons.first.kind, ReasonKind.claudeSession);
    expect(plan.drafts.first.reasons.single.kind, ReasonKind.habitDaily);
    expect(plan.drafts[2].reasons.map((r) => r.kind), [ReasonKind.planned, ReasonKind.alreadyLogged]);
    expect(plan.gaps, isEmpty, reason: 'il ne reste que 5 minutes entre 10:30 et 10:35');
  });

  test('une proposition ignorée laisse la place à la suivante', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), agentEntries: claude, planning: planning,
        dismissed: {'claude:a1:635'});
    final hebdo = plan.drafts.firstWhere((d) => d.description == 'Point hebdo');
    expect((hebdo.source, hebdo.span, hebdo.reasons.single.kind), (DraftSource.habit, const Span(630, 690), ReasonKind.habitWeekday));
    expect(hebdo.reasons.single.count, 3);
    expect(plan.drafts.any((d) => d.source == DraftSource.claude), isFalse);
    expect(planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), dismissed: {hebdo.key}).drafts.map((d) => d.description),
        isNot(contains('Point hebdo')), reason: 'clé stable : ignorée, elle ne revient pas');
  });

  test('une habitude déjà saisie aujourd’hui n’est pas reproposée', () {
    final withMail = [...mine, entry('m4', at(10, 26, 8, 30), at(10, 26, 9), desc: 'courriels ', project: 'int')];
    final plan = planDay(day: at(10, 26, 0), now: now, mine: withMail, history: history());
    expect(plan.drafts.where((d) => d.description == 'Courriels'), isEmpty);
  });

  test('rien à proposer un samedi ni un jour à venir', () {
    expect(planDay(day: at(10, 24, 0), now: now, mine: const [], history: history(), planning: planning).drafts, isEmpty);
    expect(planDay(day: at(10, 27, 0), now: now, mine: const [], history: history(), planning: planning).drafts, isEmpty);
  });

  test('créneaux vides sans proposition possible', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: const []);
    // Valeurs par défaut : 08:30–12:30 et 14:00–17:30, coupé à 17:02.
    expect(plan.gaps, [const Span(510, 540), const Span(630, 750)]);
    expect(plan.drafts, isEmpty);
  });
}
