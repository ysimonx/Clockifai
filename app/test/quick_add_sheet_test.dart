import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/core/theme.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/time_entries/quick_add_sheet.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

const me = 'hugo';

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
  Profile? get profile => null;
  @override
  bool get isAdmin => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Le « + » du téléphone (plans/14-coller-aux-maquettes.md) : durée au pouce, Enregistrer, Annuler.
void main() {
  late TestDb db;
  late CatalogController catalog;
  late _Session session;

  setUp(() async {
    session = _Session();
    db = TestDb();
    getIt.registerSingleton<TimeEntryRepository>(TimeEntryRepository(db));
    getIt.registerSingleton<ModulesRepository>(ModulesRepository(db));
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

  testWidgets('une heure le matin, en trois touchers ; Annuler la retire', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
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
        home: Scaffold(
          body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showQuickAddSheet(context), child: const Text('+')))),
        ),
      ),
    ));
    await tester.tap(find.text('+'));
    await settle(tester);
    expect(find.text('Ajouter du temps'), findsOneWidget);
    expect(find.text('Enregistrer · 3:00'), findsOneWidget, reason: 'trois heures par défaut');

    await tester.tap(find.text('1:00'));
    await tester.tap(find.text('Matin · 08:30'));
    await tester.pump();
    expect(find.text('08:30 → 09:30'), findsOneWidget);
    await tester.tap(find.text('Enregistrer · 1:00'));
    await settle(tester);
    final rows = (await tester.runAsync(() => db.select(db.timeEntries).get()))!;
    expect(rows.single.endAt!.difference(rows.single.startAt).inMinutes, 60);
    expect(rows.single.startAt.toLocal().hour, 8);
    expect(find.textContaining('Ajouté : 1:00 · 08:30 – 09:30'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.deletedAt.isNull())).get()))!, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
