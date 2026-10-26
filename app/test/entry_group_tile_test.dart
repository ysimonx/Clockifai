import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/format.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/time_entries/entry_groups.dart';
import 'package:clockifai/features/time_entries/time_entries_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';
const me = 'user-1';

/// Session minimale : propriétaire connecté dans un workspace.
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestDb db;
  late CatalogController catalog;
  late Workspace workspace;
  late EntryGroup group;
  late TimeEntryRepository repo;
  late String project;

  setUp(() async {
    db = TestDb();
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    workspace = await db.select(db.workspaces).getSingle();
    final catalogRepo = CatalogRepository(db);
    project = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
    catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    repo = TimeEntryRepository(db);
    for (final (hour, minutes) in [(8, 30), (10, 15), (14, 45)]) {
      final start = DateTime.utc(2026, 10, 22, hour);
      await repo.createManual(
        workspaceId: ws,
        userId: me,
        start: start,
        end: start.add(Duration(minutes: minutes)),
        draft: EntryDraft(description: 'Pose', projectId: project),
      );
    }
    final rows = await repo
        .watchEntries(workspaceId: ws, userId: me, from: DateTime.utc(2026, 10, 22), to: DateTime.utc(2026, 10, 23))
        .first;
    group = groupSimilar(rows).single;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    catalog.dispose();
    await db.close();
  });

  Future<void> pumpTile(WidgetTester tester, Size size, {List<TimeEntry> running = const []}) async {
    tester.view.physicalSize = size;
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
        home: Scaffold(
          body: SingleChildScrollView(child: EntryGroupTile(group: group, day: DateTime(2026, 10, 22), running: running)),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final (label, size) in [('écran large', const Size(1200, 900)), ('écran étroit', const Size(390, 900))]) {
    testWidgets('groupe de 3 entrées ($label) : résumé, dépliage, repliage, menu', (tester) async {
      await pumpTile(tester, size);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Pose'), findsOneWidget);
      expect(find.text(formatHm((30 + 15 + 45) * 60)), findsOneWidget);
      expect(find.byType(EntryTile), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.text('3'));
      await tester.pump();
      expect(find.byType(EntryTile), findsNWidgets(3));
      expect(find.text('Pose'), findsNWidgets(4));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: 'on relance depuis la ligne du groupe');

      await tester.tap(find.text('Pose').first);
      await tester.pump();
      expect(find.byType(EntryTile), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Modifier les 3 entrées'), findsOneWidget);
      expect(find.text('Supprimer les 3 entrées'), findsOneWidget);
    });
  }

  testWidgets('la tâche du groupe tourne déjà : ■ Arrêter à la place de ▶', (tester) async {
    await tester.runAsync(() => repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'Pose', projectId: project), maxRunning: 3));
    final running = await tester.runAsync(() => repo.watchRunningAll(ws, me).first);
    await pumpTile(tester, const Size(1200, 900), running: running!);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}
