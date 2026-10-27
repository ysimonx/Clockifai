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
import 'package:clockifai/features/approvals/late_board.dart';
import 'package:clockifai/features/approvals/reminder_banner.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace, this.me, this.role);
  @override
  final Workspace workspace;
  final String me;
  @override
  final String role;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => me;
  @override
  bool get isAdmin => role == 'owner';
  @override
  bool get isManager => role == 'owner';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Équipe (plans/13-ux-moderne.md, lot 8) : tableau des retards, relance, bandeau chez le membre.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late Workspace workspace;
  final now = DateTime.now();
  final lastWeek = startOfWeek(now, 1).subtract(const Duration(days: 7));

  setUp(() async {
    db = TestDb();
    getIt
      ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db))
      ..registerSingleton<ModulesRepository>(ModulesRepository(db));
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier', weekStart: const Value(1)));
    workspace = await db.select(db.workspaces).getSingle();
    await db.into(db.workspaceMembers).insert(member('karim', role: 'owner'));
    await db.into(db.workspaceMembers).insert(member('camille'));
    await db.into(db.workspaceMembers).insert(member('leo'));
    // Léo a soumis ; Camille non (2 h saisies, 7 h prévues chaque jour ouvré).
    await db.into(db.timesheetSubmissions).insert(TimesheetSubmissionsCompanion.insert(
        workspaceId: ws, userId: 'leo', periodStart: dayKey(lastWeek), periodEnd: dayKey(lastWeek.add(const Duration(days: 6))),
        status: const Value('submitted')));
    await getIt<TimeEntryRepository>().createManual(
        workspaceId: ws, userId: 'camille', start: lastWeek.add(const Duration(hours: 9)), end: lastWeek.add(const Duration(hours: 11)),
        draft: EntryDraft(description: 'Pose'));
    await db.into(db.scheduleAssignments).insert(ScheduleAssignmentsCompanion.insert(
        workspaceId: ws, userId: 'camille', startDate: dayKey(lastWeek), endDate: dayKey(lastWeek.add(const Duration(days: 6))),
        hoursPerDay: const Value(7)));
    catalog = CatalogController(CatalogRepository(db), WorkspaceRepository(db), TeamRepository(db))..bind(ws);
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

  Future<void> open(WidgetTester tester, String me, String role, Widget body) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _Session(workspace, me, role)),
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
        home: Scaffold(body: Column(children: [body])),
      ),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('le manager voit qui n’a pas soumis, et relance', (tester) async {
    await open(tester, 'karim', 'owner', const LateBoard());
    expect(find.text('camille'), findsOneWidget);
    expect(find.text('leo'), findsNothing, reason: 'Léo a soumis');
    expect(find.textContaining('2:00 saisies sur 35:00 prévues'), findsOneWidget);

    await tester.tap(find.text('Relancer'));
    await settle(tester);
    final reminders = (await tester.runAsync(() => db.select(db.reminders).get()))!;
    expect((reminders.single.userId, reminders.single.periodStart), ('camille', dayKey(lastWeek)));
    expect(find.text('Relancé'), findsOneWidget);
    await close(tester);
  });

  testWidgets('le membre relancé voit le bandeau, puis le marque vu', (tester) async {
    await getIt<ModulesRepository>().remind(workspaceId: ws, userId: 'camille', periodStart: lastWeek, by: 'karim');
    await open(tester, 'camille', 'member', const ReminderBanner());
    expect(find.textContaining('karim vous rappelle de soumettre votre semaine du'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.textContaining('vous rappelle'), findsNothing);
    expect((await tester.runAsync(() => db.select(db.reminders).getSingle()))!.seenAt, isNotNull);
    await close(tester);
  });
}
