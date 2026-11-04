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
import 'package:clockifai/features/reports/report_model.dart';
import 'package:clockifai/features/reports/report_questions.dart';
import 'package:clockifai/features/reports/reports_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member;
import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';
const me = 'alex';

class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace);
  @override
  final Workspace workspace;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => me;
  @override
  String get role => 'owner';
  @override
  bool get isAdmin => true;
  @override
  bool get isManager => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Rapports par questions (plans/13-ux-moderne.md, lot 7).
void main() {
  test('période précédente et écart', () {
    final week = DateTimeRange(start: DateTime(2026, 10, 19), end: DateTime(2026, 10, 26));
    final day = DateTimeRange(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 2));
    expect(previousRange(day, RangePreset.today), DateTimeRange(start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 1)));
    expect(previousRange(week, RangePreset.thisWeek), DateTimeRange(start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 19)));
    final march = DateTimeRange(start: DateTime(2027, 3, 1), end: DateTime(2027, 4, 1));
    expect(previousRange(march, RangePreset.thisMonth), DateTimeRange(start: DateTime(2027, 2, 1), end: DateTime(2027, 3, 1)));
    final year = DateTimeRange(start: DateTime(2026), end: DateTime(2027));
    expect(previousRange(year, RangePreset.thisYear).start, DateTime(2025));
    final ten = DateTimeRange(start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 20));
    expect(previousRange(ten, RangePreset.custom).start, DateTime(2026, 9, 30));
    expect((deltaPercent(150, 100), deltaPercent(80, 100), deltaPercent(100, 100), deltaPercent(5, 0)), ('+50 %', '−20 %', '=', null));
  });

  group('page Rapports', () {
    late TestDb db;
    late CatalogController catalog;
    late Workspace workspace;
    final now = DateTime.now();
    final weekStart = startOfWeek(now, 1);

    setUp(() async {
      db = TestDb();
      final repo = TimeEntryRepository(db);
      getIt
        ..registerSingleton<TimeEntryRepository>(repo)
        ..registerSingleton<ModulesRepository>(ModulesRepository(db));
      await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier', weekStart: const Value(1)));
      workspace = await db.select(db.workspaces).getSingle();
      await db.into(db.workspaceMembers).insert(member(me));
      final catalogRepo = CatalogRepository(db);
      final client = await catalogRepo.createClient(ws, name: 'Boulangerie');
      final project = await catalogRepo.createProject(
          ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Site', clientId: Value(client), hourlyRateCents: const Value(6000)));
      catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
      // Cette semaine : 3 h ; la semaine d'avant : 2 h.
      for (final (day, hours) in [(0, 3), (-7, 2)]) {
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day + day, 9);
        await repo.createManual(workspaceId: ws, userId: me, start: start, end: start.add(Duration(hours: hours)),
            draft: EntryDraft(description: 'Pose', projectId: project, billable: true, hourlyRateCents: 6000));
      }
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

    testWidgets('comparer, puis facturer d’un clic', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
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
          home: const Scaffold(body: ReportsPage()),
        ),
      ));
      await settle(tester);
      expect(find.text('3:00'), findsWidgets);

      await tester.tap(find.text('Comparer à la période précédente'));
      await settle(tester);
      expect(find.text('+50 % vs période précédente'), findsNWidgets(3), reason: 'temps, facturable, montant');
      expect(find.text('avant : 2:00'), findsOneWidget);

      await tester.tap(find.text('Prêt à facturer'));
      await settle(tester);
      expect(find.text('À facturer'), findsOneWidget);
      expect(find.text('Boulangerie'), findsWidgets);
      await tester.tap(find.text('Facturer'));
      await settle(tester);
      final invoices = (await tester.runAsync(() => db.select(db.invoices).get()))!;
      expect(invoices, hasLength(1));
      expect((await tester.runAsync(() => db.select(db.invoiceEntries).get()))!, hasLength(2), reason: 'les deux semaines');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    testWidgets('À facturer : un ticket à deux sessions compte une fois, comme sur la facture', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final project = await db.select(db.projects).getSingle();
        final ticket = await CatalogRepository(db).createTask(ws, project.id, 'ENG-1');
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day - 7, 14).toUtc();
        for (var i = 0; i < 2; i++) {
          await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
                workspaceId: ws,
                userId: 'claude',
                projectId: Value(project.id),
                taskId: Value(ticket),
                startAt: start,
                endAt: Value(start.add(const Duration(hours: 2))),
                billable: const Value(true),
                hourlyRateCents: const Value(6000),
                source: const Value('agent'),
              ));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
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
          home: const Scaffold(body: ReadyToBill()),
        ),
      ));
      await settle(tester);
      // 5 h de temps humain, plus 2 h pour le ticket : pas 9 h.
      expect(find.textContaining('7:00'), findsOneWidget);

      await tester.tap(find.text('Facturer'));
      await settle(tester);
      final items = (await tester.runAsync(() => db.select(db.invoiceItems).get()))!;
      expect(items.fold<double>(0, (s, i) => s + i.quantity), 7);
      expect((await tester.runAsync(() => db.select(db.invoiceEntries).get()))!, hasLength(4), reason: 'toutes les entrées');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });
}
