import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/display_prefs.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/today/today_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

const me = 'alex';

/// Session minimale : membre connecté dans un workspace.
class _Session extends ChangeNotifier implements SessionController {
  @override
  String? get workspaceId => ws;
  @override
  String? get userId => me;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Journal automatique (plans/13-ux-moderne.md, lot 11), sur base Drift en mémoire, lundi 26 octobre 2026 à 17:02.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late DisplayPrefs prefs;

  DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = DisplayPrefs(await SharedPreferences.getInstance());
    db = TestDb();
    getIt
      ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db))
      ..registerSingleton<ModulesRepository>(ModulesRepository(db));
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Studio'));
    await db.into(db.workspaceMembers).insert(member(me));
    final catalogRepo = CatalogRepository(db);
    final interne = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Interne'));
    final site = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Site'));
    Future<void> add(DateTime s, DateTime e, String desc, String project) => db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
        workspaceId: ws, userId: me, description: Value(desc), projectId: Value(project), startAt: s.toUtc(), endAt: Value(e.toUtc())));
    // Deux semaines : courriels chaque matin (habitude), travail varié, pause de 12:30 à 13:30.
    for (var day = 12; day <= 23; day++) {
      if (DateTime(2026, 10, day).weekday > DateTime.friday) continue;
      await add(at(day, 8, 30), at(day, 9), 'Courriels', interne);
      await add(at(day, 9), at(day, 12, 30), 'Site, matin du $day', site);
      await add(at(day, 13, 30), at(day, 17, 30), 'Site, après-midi du $day', site);
    }
    await add(at(26, 9), at(26, 10, 30), 'Maquettes', site);
    catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    catalog.dispose();
    await getIt.reset();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _Session()),
        ChangeNotifierProvider<CatalogController>.value(value: catalog),
        ChangeNotifierProvider<DisplayPrefs>.value(value: prefs),
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
        home: Scaffold(body: TodayPage(clock: () => DateTime(2026, 10, 26, 17, 2))),
      ),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<List<TimeEntry>> today() => (db.select(db.timeEntries)
        ..where((t) => t.deletedAt.isNull() & t.description.equals('Courriels') & t.startAt.isBiggerOrEqualValue(at(26, 0).toUtc())))
      .get();

  testWidgets('la journée proposée se confirme d’un geste', (tester) async {
    await open(tester);
    expect(find.text('Votre journée est presque prête'), findsOneWidget);
    expect(find.textContaining('1 proposition à confirmer'), findsOneWidget);
    expect(find.text('Journée type : 08:30 – 17:30, d’après vos semaines passées'), findsOneWidget);

    await tester.tap(find.text('Tout confirmer · 1'));
    await settle(tester);
    final added = (await tester.runAsync(today))!;
    expect(added, hasLength(1));
    expect((added.single.startAt.toLocal(), added.single.endAt!.toLocal()), (at(26, 8, 30), at(26, 9)));
    expect(find.text('Il reste des créneaux vides'), findsOneWidget, reason: 'rien ne propose la fin de matinée ni l’après-midi');
    expect(find.text('1 entrée ajoutée · 0:30'), findsOneWidget);
    await close(tester);
  });

  testWidgets('une proposition ignorée ne revient pas', (tester) async {
    await open(tester);
    await tester.tap(find.text('Courriels'));
    await settle(tester);
    expect(find.text('Proposé par Clockifai'), findsOneWidget);
    expect(find.textContaining('Habitude : 10 jours sur les 10 derniers jours travaillés, vers 08:30'), findsOneWidget);

    await tester.tap(find.text('Ignorer'));
    await settle(tester);
    expect(prefs.dismissedSuggestions, hasLength(1));
    expect(find.text('Votre journée est presque prête'), findsNothing);
    expect((await tester.runAsync(today))!, isEmpty, reason: 'rien n’est enregistré');
    await close(tester);
  });

  testWidgets('glisser sur la frise crée une entrée à compléter', (tester) async {
    await open(tester);
    final lane = find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragStart != null && w.onTapUp != null);
    final box = tester.getRect(lane.first);
    // De 15:00 à 16:00 environ, dans le créneau vide de l'après-midi (frise de 7:00 à 19:00).
    final x15 = box.left + box.width * (8 / 12), x16 = box.left + box.width * (9 / 12);
    await tester.dragFrom(Offset(x15, box.center.dy), Offset(x16 - x15, 0));
    await settle(tester);
    expect(find.text('Nouvelle entrée'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Appel client');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    final rows = (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.description.equals('Appel client'))).get()))!;
    expect(rows, hasLength(1));
    expect(rows.single.endAt!.difference(rows.single.startAt).inMinutes, inInclusiveRange(55, 65));
    await close(tester);
  });
}
