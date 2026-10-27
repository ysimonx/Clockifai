import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/time_entries/agents_banner.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

const me = 'pilote';

/// Session minimale : membre connecté dans un workspace.
class _Session extends ChangeNotifier implements SessionController {
  @override
  String? get workspaceId => ws;
  @override
  String? get userId => me;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestDb db;
  late CatalogController catalog;
  late TimeEntryRepository repo;
  late String chantier;

  setUp(() async {
    db = TestDb();
    repo = TimeEntryRepository(db);
    getIt.registerSingleton<TimeEntryRepository>(repo);
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    for (final m in [member(me), member('autre'), member('claude-pilote', pilot: me), member('claude-autre', pilot: 'autre')]) {
      await db.into(db.workspaceMembers).insert(m);
    }
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

  /// Laisse passer les requêtes Drift.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<String> start(WidgetTester tester, String userId, String description, {String? projectId}) async =>
      (await tester.runAsync(() => repo.start(
          workspaceId: ws, userId: userId, draft: EntryDraft(description: description, projectId: projectId), maxRunning: 0)))!;

  Widget app(Widget body) => MultiProvider(
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
          home: Scaffold(body: body),
        ),
      );

  testWidgets('bandeau « Claude travaille » : sessions en cours de mon agent seulement', (tester) async {
    await tester.pumpWidget(app(const AgentsWorkingBanner()));
    await settle(tester);
    expect(find.text('Claude travaille'), findsNothing, reason: 'aucune session en cours');

    final clockifai = await start(tester, 'claude-pilote', 'clockifai (main)', projectId: chantier);
    final fidwork = await start(tester, 'claude-pilote', 'fidwork (main)');
    await start(tester, 'claude-autre', 'Session d\'un autre pilote');
    await start(tester, me, 'Mon propre chronomètre');
    await settle(tester);
    expect(find.text('Claude travaille'), findsOneWidget);
    expect(find.text('clockifai (main)'), findsOneWidget);
    expect(find.text('Chantier'), findsOneWidget);
    expect(find.text('fidwork (main)'), findsOneWidget);
    expect(find.text('Sans projet'), findsOneWidget);
    expect(find.text('Session d\'un autre pilote'), findsNothing);
    expect(find.text('Mon propre chronomètre'), findsNothing);

    // Écrite dans runAsync, l'arrêt ne se termine jamais ici (flux Drift du bandeau) ; dans la zone du test, si.
    await repo.stop(clockifai);
    await repo.stop(fidwork);
    await settle(tester);
    expect(find.text('Claude travaille'), findsNothing, reason: 'sessions closes');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero); // minuteurs de Drift à la fermeture des flux
  });

  testWidgets('pastille « Claude » de la barre du haut : la session la plus récente, un clic les liste', (tester) async {
    await tester.pumpWidget(app(const Align(alignment: Alignment.topRight, child: AgentsWorkingChip())));
    await settle(tester);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing, reason: 'aucune session en cours');

    await start(tester, me, 'Mon propre chronomètre');
    await settle(tester);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing, reason: 'mon chronomètre a sa propre pastille');

    final ancienne = await start(tester, 'claude-pilote', 'Export PDF', projectId: chantier);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    final recente = await start(tester, 'claude-pilote', 'Version 0.2.6 des applications');
    await settle(tester);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    expect(find.text('Version 0.2.6 des applications'), findsOneWidget);
    expect(find.text('Export PDF'), findsNothing, reason: 'la pastille ne montre que la plus récente');
    expect(find.text('+ 1 autre'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await settle(tester);
    expect(find.text('Claude travaille'), findsOneWidget, reason: 'titre du panneau');
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Chantier'), findsOneWidget);
    expect(find.text('Version 0.2.6 des applications'), findsNWidgets(2), reason: 'pastille et panneau');

    await repo.stop(ancienne);
    await repo.stop(recente);
    await settle(tester);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing, reason: 'sessions closes : pastille et panneau partis');
    expect(find.text('Claude travaille'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
