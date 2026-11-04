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

  test('le temps de Claude compte déjà : habitudes puis planning, sur les trous seulement', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), agentEntries: claude, planning: planning);
    expect(plan.windows, [const Span(510, 750), const Span(810, 1022)]);
    expect(plan.loggedMinutes, 90 + 135 + 47);
    expect([for (final d in plan.drafts) (d.source, d.span)], [
      (DraftSource.habit, const Span(510, 540)),
      (DraftSource.planning, const Span(690, 750)),
      (DraftSource.planning, const Span(810, 840)),
    ], reason: 'pas de copie de la session de Claude (10:35 – 11:30), ni du point hebdo qui tombe dessus');
    expect(plan.drafts.first.reasons.single.kind, ReasonKind.habitDaily);
    expect(plan.drafts[1].reasons.map((r) => r.kind), [ReasonKind.planned, ReasonKind.alreadyLogged]);
    expect(plan.agent, [const Span(635, 690)]);
    expect(plan.agentOnlyMinutes, 55);
    expect(plan.gaps, isEmpty, reason: 'il ne reste que 5 minutes entre 10:30 et 10:35');
  });

  test('une proposition ignorée laisse la place à la suivante', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), planning: planning);
    final hebdo = plan.drafts.firstWhere((d) => d.description == 'Point hebdo');
    expect((hebdo.source, hebdo.span, hebdo.reasons.single.kind), (DraftSource.habit, const Span(630, 690), ReasonKind.habitWeekday));
    expect(hebdo.reasons.single.count, 3);
    final without = planDay(day: at(10, 26, 0), now: now, mine: mine, history: history(), planning: planning, dismissed: {hebdo.key});
    expect(without.drafts.map((d) => d.description), isNot(contains('Point hebdo')), reason: 'clé stable : ignorée, elle ne revient pas');
    expect(without.drafts.where((d) => d.source == DraftSource.planning).first.span, const Span(630, 750));
  });

  test('sessions de Claude : réunies sans double compte, une ligne par projet, projets en parallèle', () {
    expect(merge(const [Span(600, 660), Span(540, 610), Span(700, 720), Span(660, 680)]), const [Span(540, 680), Span(700, 720)]);
    expect(coveredMinutes(const [Span(600, 660), Span(630, 700)]), 100);
    final sessions = [
      (entry('a', at(10, 26, 9), at(10, 26, 10), project: 'p1', user: 'agent'), const Span(540, 600)),
      (entry('b', at(10, 26, 9, 30), at(10, 26, 11), project: 'p2', user: 'agent'), const Span(570, 660)),
      (entry('c', at(10, 26, 9, 45), at(10, 26, 10, 15), project: 'p1', user: 'agent'), const Span(585, 615)),
      (entry('d', at(10, 26, 10, 30), at(10, 26, 11), project: 'p1', user: 'agent'), const Span(630, 660)),
    ];
    final lanes = agentLanes(sessions);
    expect([for (final l in lanes) '${l.projectId}: ${[for (final s in l.sessions) s.$1.id].join(' ')}'], ['p1: a d', 'p1: c', 'p2: b'],
        reason: 'deux sessions simultanées sur p1 : deux lignes, l’une sous l’autre');
    expect(parallelProjects(sessions), 2);
    expect(parallelProjects(sessions.take(1).toList()), 1);
    expect(parallelProjects(const []), 0);
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

  test('jours de changement d’heure : des jours de calendrier, des heures à l’horloge', () {
    // Le 25 octobre 2026 compte 25 heures en Europe (passage à l’heure d’hiver) ; sans effet en UTC.
    final sunday = at(10, 25, 0);
    expect(addDays(at(10, 26, 0), -1), sunday);
    expect(atMinute(sunday, 600), at(10, 25, 10));
    expect(minuteOf(at(10, 25, 10), sunday), 600);
    expect(minuteOf(at(10, 26, 0, 30), sunday), 1470);
    expect(spanOf(entry('x', at(10, 25, 10), at(10, 25, 11)), sunday, now), const Span(600, 660));
  });

  test('journée type réglée dans le profil : elle prime sur l’historique', () {
    Profile profile({String? start, String? ls, String? le, String? end}) =>
        Profile(id: 'me', displayName: '', timezone: 'Europe/Paris', locale: 'fr', dayStart: start, lunchStart: ls, lunchEnd: le, dayEnd: end);
    final mine = TypicalDay.ofProfile(profile(start: '09:00', ls: '12:00', le: '13:00', end: '18:00'))!;
    expect((mine.start, mine.lunch, mine.end, mine.target, mine.fromProfile), (540, const Span(720, 780), 1080, 480, true));
    expect(TypicalDay.ofProfile(profile(start: '09:00', ls: '13:00', le: '12:00', end: '18:00'))!.lunch, isNull,
        reason: 'pause incohérente ignorée');
    expect(TypicalDay.ofProfile(profile(start: '09:00')), isNull, reason: 'sans départ : automatique');
    expect(TypicalDay.ofProfile(null), isNull);

    final plan = planDay(day: at(10, 26, 0), now: now, mine: const [], history: history(), typical: mine);
    expect(plan.windows, [const Span(540, 720), const Span(780, 1022)]);
  });

  test('agenda et commits : propositions sur les trous laissés par vous et Claude, avant les habitudes', () {
    DateTime utc(int h, [int m = 0]) => at(10, 26, h, m).toUtc();
    final plan = planDay(
      day: at(10, 26, 0),
      now: now,
      mine: mine,
      history: history(),
      agentEntries: claude,
      calendar: [
        CalendarEvent(id: 'ev1', start: utc(8, 30), end: utc(9), title: 'Point client boulangerie'),
        CalendarEvent(id: 'ev2', start: utc(20), end: utc(21), title: 'Dîner'), // hors de la journée de travail
      ],
      commits: [
        CommitTrace(sha: 'aaaaaaaaaaaaaaaa', subject: 'Maquette du panier', at: utc(13, 50), repository: 'site', projectId: 'p2'),
        CommitTrace(sha: 'bbbbbbbbbbbbbbbb', subject: '', at: utc(13, 55), repository: 'site', projectId: 'p2'),
      ],
      guessProject: (text) => text.contains('boulangerie') ? (projectId: 'boul', taskId: null) : null,
    );
    final byKey = {for (final d in plan.drafts) d.source: d};
    final cal = byKey[DraftSource.calendar]!;
    expect((cal.span, cal.description, cal.projectId), (const Span(510, 540), 'Point client boulangerie', 'boul'));
    expect(cal.reasons.single.kind, ReasonKind.calendar);
    expect(plan.drafts.where((d) => d.description == 'Courriels'), isEmpty, reason: 'la réunion a pris le créneau de l’habitude');
    final git = byKey[DraftSource.commits]!;
    expect((git.span, git.description, git.projectId), (const Span(810, 835), 'Maquette du panier', 'p2'));
    expect((git.reasons.single.count, git.reasons.single.text), (2, 'site'));
    expect(plan.drafts.any((d) => d.description == 'Dîner'), isFalse);
  });

  test('créneaux vides sans proposition possible', () {
    final plan = planDay(day: at(10, 26, 0), now: now, mine: mine, history: const []);
    // Valeurs par défaut : 08:30–12:30 et 14:00–17:30, coupé à 17:02.
    expect(plan.gaps, [const Span(510, 540), const Span(630, 750)]);
    expect(plan.drafts, isEmpty);
  });

  test('dernier jour travaillé : le plus récent avant le jour, entrées terminées seulement', () {
    expect(lastWorkedDay(history(), at(10, 26, 0)), DateTime(2026, 10, 23), reason: 'vendredi, par-dessus le week-end');
    expect(lastWorkedDay(history(), at(10, 20, 0)), DateTime(2026, 10, 19));
    expect(lastWorkedDay([entry('run', at(10, 25, 9), null)], at(10, 26, 0)), isNull, reason: 'chronomètre en cours');
    expect(lastWorkedDay(const [], at(10, 26, 0)), isNull);
  });
}
