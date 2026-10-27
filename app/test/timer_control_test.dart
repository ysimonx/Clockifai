import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/core/theme.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/timer/timer_control.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

const me = 'camille';

class _Session extends ChangeNotifier implements SessionController {
  @override
  String? get workspaceId => ws;
  @override
  String? get userId => me;
  @override
  Workspace? workspace;
  @override
  int get runningTimersLimit => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Le chronomètre des maquettes (plans/14-coller-aux-maquettes.md, lot 1) : « Démarrer », la pastille, l'arrêt.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late _Session session;

  setUp(() async {
    session = _Session();
    db = TestDb();
    getIt.registerSingleton<TimeEntryRepository>(TimeEntryRepository(db));
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Échafaudages du Nord'));
    await db.into(db.workspaceMembers).insert(member(me));
    session.workspace = await db.select(db.workspaces).getSingle();
    catalog = CatalogController(CatalogRepository(db), WorkspaceRepository(db), TeamRepository(db))..bind(ws);
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
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<CatalogController>.value(value: catalog),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(appBar: AppBar(actions: [TimerControl(compact: size.width < 600)])),
      ),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<List<TimeEntry>> entries() => db.select(db.timeEntries).get();

  for (final (name, size) in [('ordinateur', const Size(1400, 900)), ('téléphone', const Size(390, 844))]) {
    testWidgets('démarrer puis arrêter le chronomètre ($name)', (tester) async {
      await open(tester, size);
      final start = size.width < 600 ? find.byTooltip('Démarrer le chronomètre') : find.widgetWithText(FilledButton, 'Démarrer');
      await tester.tap(start);
      await settle(tester);
      expect(find.text('Démarrer le chronomètre'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextField, 'Sur quoi travaillez-vous ?'), 'Pose garde-corps');
      await tester.tap(find.widgetWithText(FilledButton, 'Démarrer').last);
      await settle(tester);
      final running = await tester.runAsync(entries);
      expect(running!.single.description, 'Pose garde-corps');
      expect(running.single.endAt, isNull);
      // La pastille remplace le bouton ; sur téléphone, la durée seule.
      expect(find.widgetWithText(FilledButton, 'Démarrer'), findsNothing);
      expect(find.text('Pose garde-corps'), size.width < 600 ? findsNothing : findsOneWidget);

      await tester.tap(find.byTooltip('Arrêter le chronomètre'));
      await settle(tester);
      expect((await tester.runAsync(entries))!.single.endAt, isNotNull);
      await close(tester);
    });
  }
}
