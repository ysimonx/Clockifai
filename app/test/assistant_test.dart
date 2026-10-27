import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/assistant/assistant.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';
const me = 'user-1';

class _Session extends ChangeNotifier implements SessionController {
  @override
  String? get workspaceId => ws;
  @override
  String? get userId => me;
  @override
  String get role => 'owner';
  @override
  bool get isAdmin => true;
  @override
  Workspace? get workspace => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// « Demander à Clockifai » (plans/13-ux-moderne.md, lot 12) : réponse, proposition en aperçu, appliquer, annuler.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late String entryId;
  final asked = <(String, String, int)>[];

  setUp(() async {
    db = TestDb();
    final repo = TimeEntryRepository(db);
    getIt.registerSingleton<TimeEntryRepository>(repo);
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    final catalogRepo = CatalogRepository(db);
    final project = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Site'));
    catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    entryId = await repo.createManual(
        workspaceId: ws, userId: me, start: DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 11),
        draft: EntryDraft(description: 'Réunion', projectId: project, billable: true));
    asked.clear();
    AssistantApi.override = (w, q, history) async {
      asked.add((w, q, history.length));
      return {
        'answer': '2:00 sur Site la semaine dernière.',
        'refused': false,
        'proposals': [
          {'entry_ids': [entryId], 'billable': false, 'summary': 'Passer la réunion en non facturable'},
        ],
      };
    };
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    AssistantApi.override = null;
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

  testWidgets('une question, une réponse, une proposition appliquée puis annulée', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _Session()),
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
        home: const Scaffold(body: Align(alignment: Alignment.centerRight, child: AssistantPanel())),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('jamais vos descriptions'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton).first);
    await settle(tester);
    expect(asked.single.$1, ws);
    expect(find.text('2:00 sur Site la semaine dernière.'), findsOneWidget);
    expect(find.text('Passer la réunion en non facturable'), findsOneWidget);
    expect(find.textContaining('1 entrée → Non facturable'), findsOneWidget);

    await tester.tap(find.text("Voir l'aperçu"));
    await tester.pump();
    expect(find.textContaining('Réunion · Site'), findsOneWidget, reason: 'la description reste sur l’appareil');

    await tester.tap(find.text('Appliquer'));
    await settle(tester);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.billable, isFalse);
    expect(find.text('Appliqué'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!.billable, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
