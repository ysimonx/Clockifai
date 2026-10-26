import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/time_entries/inline_edit.dart';
import 'package:clockifai/features/time_entries/time_entries_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Annuler plutôt que confirmer, description modifiable sur place (plans/13-ux-moderne.md, lot 1).
void main() {
  late TestDb db;
  late CatalogController catalog;
  late Workspace workspace;
  late TimeEntryRepository repo;
  late String entryId;

  setUp(() async {
    db = TestDb();
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    workspace = await db.select(db.workspaces).getSingle();
    final catalogRepo = CatalogRepository(db);
    final project = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
    catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    repo = TimeEntryRepository(db);
    getIt.registerSingleton<TimeEntryRepository>(repo);
    entryId = await repo.createManual(
      workspaceId: ws,
      userId: me,
      start: DateTime.utc(2026, 10, 22, 8),
      end: DateTime.utc(2026, 10, 22, 9, 30),
      draft: EntryDraft(description: 'Pose', projectId: project),
    );
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
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rows = repo.watchEntries(workspaceId: ws, userId: me, from: DateTime.utc(2026, 10, 22), to: DateTime.utc(2026, 10, 23));
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
          body: StreamBuilder<List<EntryRow>>(
            stream: rows,
            builder: (context, snap) => ListView(children: [
              if (snap.data case final rows? when rows.isNotEmpty) DayCard(day: DateTime(2026, 10, 22), rows: rows, grouped: false, inlineEdit: true),
            ]),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  /// Démonte l'écran : arrête les flux Drift et le minuteur du bandeau avant la fermeture de la base.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('la description se modifie sur place, et Annuler la rend', (tester) async {
    await open(tester);
    expect(tester.widget<InlineProject>(find.byType(InlineProject)).onPick, isNotNull);
    await tester.tap(find.text('Pose'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Pose du placo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Pose du placo'), findsOneWidget);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.description, 'Pose du placo');
    expect(find.text('Entrée modifiée'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // le bandeau finit d'entrer
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.description, 'Pose');
    expect(find.text('Pose'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Échap abandonne la modification', (tester) async {
    await open(tester);
    await tester.tap(find.text('Pose'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Autre chose');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(TextField), findsNothing);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.description, 'Pose');
    await close(tester);
  });

  testWidgets('supprimer ne demande rien ; Annuler rend l’entrée', (tester) async {
    await open(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Pose'), findsNothing);
    expect(find.text('Entrée supprimée'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // le bandeau finit d'entrer
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect(find.text('Pose'), findsOneWidget);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.deletedAt, isNull);
    await close(tester);
  });

  testWidgets('une entrée verrouillée ne se modifie pas sur place', (tester) async {
    await (db.update(db.timeEntries)..where((t) => t.id.equals(entryId))).write(const TimeEntriesCompanion(locked: Value(true)));
    await open(tester);
    expect(tester.widget<InlineDescription>(find.byType(InlineDescription)).onSave, isNull);
    expect(tester.widget<InlineProject>(find.byType(InlineProject)).onPick, isNull);
    await close(tester);
  });
}
