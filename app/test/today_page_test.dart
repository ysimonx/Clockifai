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
import 'package:clockifai/features/presence/presence.dart';
import 'package:clockifai/features/presence/presence_log.dart';
import 'package:clockifai/features/today/day_plan.dart' show CalendarEvent;
import 'package:clockifai/features/today/day_recap.dart';
import 'package:clockifai/features/today/today_page.dart';
import 'package:clockifai/features/today/traces.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
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
  Profile? profile;
  @override
  Workspace? workspace;
  @override
  bool get isAdmin => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Journal automatique (plans/13-ux-moderne.md, lot 11), sur base Drift en mémoire, lundi 26 octobre 2026 à 17:02.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late DisplayPrefs prefs;
  late _Session session;

  DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = DisplayPrefs(await SharedPreferences.getInstance());
    session = _Session();
    TracesApi.override = (_, _) async => DayTraces.empty;
    db = TestDb();
    getIt
      ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db))
      ..registerSingleton<ModulesRepository>(ModulesRepository(db));
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Studio'));
    await db.into(db.workspaceMembers).insert(member(me));
    session.workspace = await db.select(db.workspaces).getSingle();
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
    TracesApi.override = null;
    PresenceTracker.instance.log.value = PresenceLog();
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

  Future<void> open(WidgetTester tester, {Widget? body}) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
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
        home: Scaffold(body: body ?? TodayPage(clock: () => DateTime(2026, 10, 26, 17, 2))),
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

  testWidgets('journée type du profil : créneaux et mention dans le bilan', (tester) async {
    session.profile = const Profile(
        id: me, displayName: '', timezone: 'Europe/Paris', locale: 'fr', dayStart: '09:00', lunchStart: '12:00', lunchEnd: '13:00', dayEnd: '18:00');
    await open(tester);
    expect(find.text('Journée type : 09:00 – 18:00, réglée dans vos paramètres'), findsOneWidget);
    expect(find.text('Courriels'), findsNothing, reason: 'l’habitude de 08:30 tombe avant l’arrivée réglée');
    await close(tester);
  });

  testWidgets('agenda : la réunion devient une proposition, et la ligne « Traces » la montre', (tester) async {
    TracesApi.override = (_, day) async => DayTraces(calendar: 'ok', events: [
          CalendarEvent(id: 'ev', start: at(26, 15).toUtc(), end: at(26, 16).toUtc(), title: 'Point client site'),
        ]);
    await open(tester);
    expect(find.text('Traces'), findsOneWidget);
    await tester.tap(find.text('Point client site').first);
    await settle(tester);
    expect(find.text('Agenda'), findsWidgets, reason: 'dans « À compléter » et le panneau du bloc');
    expect(find.textContaining('Dans votre agenda, de 15:00 à 16:00'), findsOneWidget);
    await close(tester);
  });

  testWidgets('fin de journée : bandeau à l’heure dite, propositions cochées, confirmées d’un geste', (tester) async {
    await open(tester, body: Column(children: [DayRecapBanner(clock: () => DateTime(2026, 10, 26, 17, 40)), const Expanded(child: SizedBox())]));
    expect(find.textContaining('Fin de journée · 1:30 saisies sur'), findsOneWidget);
    expect(find.textContaining('1 proposition à confirmer'), findsOneWidget);
    expect(prefs.dayRecapShown, '2026-10-26', reason: 'une fois par jour');

    await tester.tap(find.text('Revoir'));
    await settle(tester);
    expect(find.widgetWithText(CheckboxListTile, 'Courriels'), findsOneWidget);
    await tester.tap(find.text('Confirmer 1 entrée'));
    await settle(tester);
    expect((await tester.runAsync(today))!, hasLength(1));
    await close(tester);
  });

  testWidgets('Claude : une ligne par projet, son temps compte, seuls les trous restent à saisir', (tester) async {
    const agent = 'claude-alex';
    final site = catalog.projects.firstWhere((p) => p.name == 'Site').id;
    final interne = catalog.projects.firstWhere((p) => p.name == 'Interne').id;
    await tester.runAsync(() async {
      await db.into(db.workspaceMembers).insert(member(agent, pilot: me));
      Future<void> session(DateTime s, DateTime e, String desc, String project) => db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
          workspaceId: ws, userId: agent, description: Value(desc), projectId: Value(project), startAt: s.toUtc(), endAt: Value(e.toUtc())));
      await session(at(26, 10, 30), at(26, 12), 'Rappels par SMS', site);
      await session(at(26, 11), at(26, 12, 30), 'Revue des droits', interne);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await open(tester);
    expect(find.text('jusqu’à 2 projets en parallèle'), findsOneWidget);
    final sms = tester.getTopLeft(find.byTooltip('Claude : Rappels par SMS, 10:30 – 12:00'));
    final droits = tester.getTopLeft(find.byTooltip('Claude : Revue des droits, 11:00 – 12:30'));
    expect(droits.dy, greaterThan(sms.dy), reason: 'deux projets : deux lignes, l’une sous l’autre');

    expect(find.textContaining('Pendant une session de Claude'), findsNothing, reason: 'le temps de Claude n’est pas recopié');
    expect(find.textContaining('2:00 à saisir'), findsNothing, reason: 'la fin de matinée est couverte par Claude');
    expect(find.text('Couvert par Claude'), findsOneWidget);
    expect(find.textContaining('4:00 reconstituées'), findsOneWidget, reason: '1:30 saisies, 2:00 de Claude, 0:30 proposées');
    await close(tester);
  });

  testWidgets('journée sans entrée où Claude a travaillé : pas de « Comme vendredi » par-dessus son temps', (tester) async {
    const agent = 'claude-alex';
    final site = catalog.projects.firstWhere((p) => p.name == 'Site').id;
    await tester.runAsync(() async {
      await (db.delete(db.timeEntries)..where((t) => t.description.equals('Maquettes'))).go();
      await db.into(db.workspaceMembers).insert(member(agent, pilot: me));
      await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
          workspaceId: ws, userId: agent, description: const Value('Rappels'), projectId: Value(site), startAt: at(26, 10).toUtc(), endAt: Value(at(26, 11).toUtc())));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await open(tester);
    expect(find.text('Comme vendredi ?'), findsNothing);
    expect(find.byTooltip('Claude : Rappels, 10:00 – 11:00'), findsOneWidget);
    await close(tester);
  });

  testWidgets('une proposition ignorée ne revient pas', (tester) async {
    await open(tester);
    await tester.tap(find.text('Courriels').first);
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
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Appel client');
    await tester.tap(find.text('Enregistrer').last, warnIfMissed: false); // celui du panneau, sous la saisie express
    await settle(tester);
    final rows = (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.description.equals('Appel client'))).get()))!;
    expect(rows, hasLength(1));
    expect(rows.single.endAt!.difference(rows.single.startAt).inMinutes, inInclusiveRange(55, 65));
    await close(tester);
  });

  testWidgets('saisie express : une ligne en clair, rangée dans le premier créneau vide assez grand', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Saisie express'), '1h20 réunion site');
    await tester.pump();
    expect(find.text('1:20'), findsWidgets);
    expect(find.text('« Réunion »'), findsOneWidget, reason: 'le nom du projet sort de la description');
    expect(find.text('10:30 → 11:50 · dans un créneau vide'), findsOneWidget, reason: '8:30 – 9:00 est trop court');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    final rows = (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.description.equals('Réunion'))).get()))!;
    expect(rows, hasLength(1));
    expect((rows.single.startAt.toLocal(), rows.single.endAt!.toLocal()), (at(26, 10, 30), at(26, 11, 50)));
    expect(find.textContaining('Ajouté : Réunion'), findsOneWidget);
    await close(tester);
  });

  testWidgets('saisie express : la proposition reste en place, « hier » est un jour de calendrier', (tester) async {
    await open(tester);
    final field = find.widgetWithText(TextField, 'Saisie express');
    await tester.enterText(field, '20min relecture');
    await tester.pump();
    expect(find.text('10:30 → 10:50 · dans un créneau vide'), findsOneWidget, reason: '08:30 – 09:00 est proposé (Courriels)');

    // Hier, dimanche 25 octobre : 25 heures en Europe, l'entrée garde l'heure tapée.
    await tester.enterText(field, '9h-10h30 site hier');
    await tester.pump();
    expect(find.text('Hier'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    final rows = (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.startAt.isSmallerThanValue(at(26, 0).toUtc()) & t.startAt.isBiggerOrEqualValue(at(25, 0).toUtc()))).get()))!;
    expect((rows.single.startAt.toLocal(), rows.single.endAt!.toLocal()), (at(25, 9), at(25, 10, 30)));
    await close(tester);
  });

  testWidgets('journée vide : « Comme vendredi » recopie la dernière journée travaillée, Annuler la retire', (tester) async {
    await tester.runAsync(() => (db.delete(db.timeEntries)..where((t) => t.description.equals('Maquettes'))).go());
    await open(tester);
    expect(find.text('Comme vendredi ?'), findsOneWidget);
    expect(find.text("Rien de saisi aujourd'hui"), findsOneWidget);
    await tester.tap(find.text('Reprendre la journée · 8:00'));
    await settle(tester);
    Future<List<TimeEntry>> monday() async => (await tester.runAsync(() => (db.select(db.timeEntries)
          ..where((t) => t.deletedAt.isNull() & t.startAt.isBiggerOrEqualValue(at(26, 0).toUtc())))
        .get()))!;
    final copies = await monday();
    expect({for (final e in copies) e.description: e.startAt.toLocal()},
        {'Courriels': at(26, 8, 30), 'Site, matin du 23': at(26, 9), 'Site, après-midi du 23': at(26, 13, 30)});
    expect(find.text('3 entrées dupliquées'), findsOneWidget);
    expect(find.text('Comme vendredi ?'), findsNothing, reason: 'la journée n’est plus vide');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect(await monday(), isEmpty);
    await close(tester);
  });

  testWidgets('« Comme hier » le lendemain d’une journée saisie ; rien sur une journée déjà commencée', (tester) async {
    await open(tester, body: TodayPage(clock: () => DateTime(2026, 10, 27, 8)));
    expect(find.text('Comme hier ?'), findsOneWidget);
    await close(tester);
    await open(tester);
    expect(find.textContaining(RegExp(r'^Comme (hier|vendredi|le )')), findsNothing, reason: 'lundi 26 a déjà « Maquettes »');
    await close(tester);
  });

  testWidgets('présence chantier : l’après-midi sur le chantier devient une proposition, avec sa raison', (tester) async {
    final site = catalog.projects.firstWhere((p) => p.name == 'Site').id;
    PresenceTracker.instance.log.value = PresenceLog()
      ..record(at(26, 13, 25), {site})
      ..record(at(26, 16, 55), {site})
      ..record(at(26, 17), {});
    await open(tester);
    await tester.tap(find.text('Site, après-midi du 23').first);
    await settle(tester);
    expect(find.text('Chantier'), findsWidgets, reason: 'dans « À compléter » et le panneau du bloc');
    expect(find.textContaining("Sur le chantier de 13:25 à 17:00, d'après ce téléphone"), findsOneWidget);
    await close(tester);
  });
}
