import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/projects/projects_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';
const me = 'user-1';

/// Session minimale : manager connecté dans un workspace.
class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace);
  @override
  final Workspace workspace;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => me;
  @override
  bool get isManager => true;
  @override
  bool get isAdmin => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tâches terminées repliées dans Projets et clients (plans/20-cloture-des-taches.md).
void main() {
  late TestDb db;
  late CatalogController catalog;
  late Workspace workspace;
  late Map<String, String> ids;

  setUp(() async {
    db = TestDb();
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    workspace = await db.select(db.workspaces).getSingle();
    final repo = CatalogRepository(db);
    getIt
      ..registerSingleton<CatalogRepository>(repo)
      ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db));
    final project = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Clockifai'));
    final plan20 = await repo.createTask(ws, project, 'Plan 20');
    final plan16 = await repo.createTask(ws, project, 'Plan 16');
    ids = {
      'Plan 20': plan20,
      'Job de nuit': await repo.createTask(ws, project, 'Job de nuit', parentId: plan20),
      'Lecture': await repo.createTask(ws, project, 'Lecture', parentId: plan20),
      'Plan 16': plan16,
      'Migration': await repo.createTask(ws, project, 'Migration', parentId: plan16),
      'Écran': await repo.createTask(ws, project, 'Écran', parentId: plan16),
    };
    // Plan 16 et son étape « Migration » terminés (« Écran », restée ouverte, se replie avec eux) ; l'étape
    // « Lecture » du plan 20 aussi.
    for (final name in ['Plan 16', 'Migration', 'Lecture']) {
      await repo.updateTask(ids[name]!, status: 'done');
    }
    catalog = CatalogController(repo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
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
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
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
        home: const Scaffold(body: ProjectsPage()),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('Clockifai'));
    await tester.pumpAndSettle();
  }

  /// Démonte l'écran : arrête les flux Drift avant la fermeture de la base.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<String> status(WidgetTester tester, String name) async =>
      (await tester.runAsync(() => (db.select(db.tasks)..where((t) => t.id.equals(ids[name]!))).getSingle()))!.status;

  testWidgets('les tâches terminées sont repliées sous « Terminées (2) »', (tester) async {
    await open(tester);
    expect(find.text('Plan 20'), findsOneWidget);
    expect(find.text('Job de nuit'), findsOneWidget);
    for (final hidden in ['Plan 16', 'Migration', 'Écran', 'Lecture', 'Plan 20 › Lecture']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }

    await tester.tap(find.text('Terminées (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Plan 16'), findsOneWidget);
    expect(find.text('Migration'), findsOneWidget);
    expect(find.text('Écran'), findsOneWidget, reason: 'une tâche terminée se replie avec toutes ses sous-tâches');
    expect(find.text('Plan 20 › Lecture'), findsOneWidget, reason: 'étape terminée d’une tâche ouverte, sous son chemin');
    await close(tester);
  });

  testWidgets('Rouvrir une sous-tâche sous une tâche terminée rouvre les deux', (tester) async {
    await open(tester);
    await tester.tap(find.text('Terminées (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'Migration'), matching: find.byTooltip('Rouvrir')));
    await settle(tester);

    expect(await status(tester, 'Migration'), 'active');
    expect(await status(tester, 'Plan 16'), 'active');
    expect(find.text('Terminées (1)'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Marquer terminée replie la tâche', (tester) async {
    await open(tester);
    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'Job de nuit'), matching: find.byTooltip('Marquer terminée')));
    await settle(tester);
    expect(await status(tester, 'Job de nuit'), 'done');
    expect(find.text('Job de nuit'), findsNothing);
    expect(find.text('Terminées (3)'), findsOneWidget);
    await close(tester);
  });
}
