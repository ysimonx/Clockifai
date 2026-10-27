import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/format.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/timesheet/timesheet_page.dart';
import 'package:clockifai/features/timesheet/week_tools.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';
const me = 'user-1';

/// Session minimale : membre connecté dans un workspace.
class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace);
  @override
  final Workspace workspace;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => me;
  @override
  String get role => 'member';
  @override
  bool get isAdmin => false;
  @override
  bool get isManager => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TimeEntry entry(String id, DateTime start, DateTime? end, {String? project, String desc = 'x'}) => TimeEntry(
    id: id, workspaceId: ws, userId: me, projectId: project, description: desc, startAt: start.toUtc(), endAt: end?.toUtc(),
    billable: true, locked: false);

ScheduleAssignment plan(String project, String from, String to, double hours) =>
    ScheduleAssignment(id: 'a-$project', workspaceId: ws, userId: me, projectId: project, startDate: from, endDate: to, hoursPerDay: hours);

/// La semaine (plans/13-ux-moderne.md, lot 5).
void main() {
  test('vérification avant soumission : jours vides, sous le planning, chronomètre, chevauchement', () {
    DateTime at(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m);
    final days = [for (var d = 19; d <= 25; d++) DateTime(2026, 10, d)];
    final rows = [
      EntryRow(entry('a', at(19, 9), at(19, 16), project: 'p'), const []),
      EntryRow(entry('b', at(20, 9), at(20, 11), project: 'p'), const []),
      EntryRow(entry('c', at(20, 10, 30), at(20, 12), project: null, desc: ''), const []), // chevauche b, sans projet
      EntryRow(entry('d', at(21, 9), null, project: 'p'), const []), // en cours
    ];
    final issues = weekIssues(
      days: days,
      rows: rows,
      assignments: [plan('p', '2026-10-19', '2026-10-23', 7)],
      now: at(22, 18),
      requireProject: true,
    );
    expect([for (final i in issues) (i.kind, i.day?.day, i.minutes, i.planned, i.count)], [
      (WeekIssueKind.belowPlan, 20, 210, 420, 0),
      (WeekIssueKind.emptyDay, 22, 0, 420, 0),
      (WeekIssueKind.noProject, null, 0, 0, 1),
      (WeekIssueKind.running, null, 0, 0, 1),
      (WeekIssueKind.overlap, null, 0, 0, 1),
    ]);
    expect(issues.any((i) => i.day?.day == 21), isFalse, reason: 'le chronomètre en cours compte pour le jour');
    expect(issues.any((i) => i.day?.day == 23), isFalse, reason: 'jour à venir');
    expect(plannedMinutes([plan('p', '2026-10-19', '2026-10-25', 7)], 'p', DateTime(2026, 10, 24)), 0, reason: 'samedi');
  });

  group('page Semaine', () {
    late TestDb db;
    late CatalogController catalog;
    late Workspace workspace;
    late String chantier;
    final now = DateTime.now();
    final weekStart = startOfWeek(now, 1);
    DateTime day(int i, int h) => DateTime(weekStart.year, weekStart.month, weekStart.day + i, h);

    setUp(() async {
      db = TestDb();
      getIt
        ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db))
        ..registerSingleton<ModulesRepository>(ModulesRepository(db));
      await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier', weekStart: const Value(1)));
      workspace = await db.select(db.workspaces).getSingle();
      final catalogRepo = CatalogRepository(db);
      chantier = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
      catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      catalog.dispose();
      await getIt.reset();
      await db.close();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionController>.value(value: _Session(workspace)),
          ChangeNotifierProvider<CatalogController>.value(value: catalog),
        ],
        child: MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: TimesheetPage()),
        ),
      ));
      await settle(tester);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    Future<List<TimeEntry>> thisWeek(WidgetTester tester) async => (await tester.runAsync(() =>
        (db.select(db.timeEntries)..where((t) => t.deletedAt.isNull() & t.startAt.isBiggerOrEqualValue(weekStart.toUtc()))).get()))!;

    testWidgets('copier la semaine précédente, puis Annuler', (tester) async {
      final repo = getIt<TimeEntryRepository>();
      for (final i in [0, 2]) {
        await tester.runAsync(() => repo.createManual(
            workspaceId: ws, userId: me, start: day(i - 7, 9), end: day(i - 7, 12), draft: EntryDraft(description: 'Pose', projectId: chantier)));
      }
      await open(tester);
      await tester.tap(find.text('Copier la semaine précédente'));
      await settle(tester);
      final copies = await thisWeek(tester);
      expect(copies.map((e) => e.startAt.toLocal()).toSet(), {day(0, 9), day(2, 9)});
      expect(find.text('2 entrées dupliquées'), findsOneWidget);

      await tester.tap(find.text('Copier la semaine précédente'));
      await settle(tester);
      expect(await thisWeek(tester), hasLength(2), reason: 'déjà copiées : rien de plus');

      await tester.pump(const Duration(seconds: 9)); // le bandeau précédent s'en va
      await close(tester);
    });

    testWidgets('planning : heures prévues en pointillé, puis compléter les jours passés', (tester) async {
      await tester.runAsync(() => db.into(db.scheduleAssignments).insert(ScheduleAssignmentsCompanion.insert(
          workspaceId: ws, userId: me, projectId: Value(chantier), startDate: dayKey(weekStart), endDate: dayKey(day(6, 0)),
          hoursPerDay: const Value(7))));
      await open(tester);
      final workdaysSoFar = [for (var i = 0; i < 5; i++) if (!day(i, 0).isAfter(now)) i];
      expect(find.text('7:00'), findsNWidgets(5), reason: 'du lundi au vendredi');

      await tester.tap(find.text("Compléter d'après le planning"));
      await settle(tester);
      final filled = await thisWeek(tester);
      expect(filled, hasLength(workdaysSoFar.length));
      expect(filled.every((e) => e.endAt!.difference(e.startAt).inMinutes == 420 && e.projectId == chantier), isTrue);
      await close(tester);
    });
  });
}
