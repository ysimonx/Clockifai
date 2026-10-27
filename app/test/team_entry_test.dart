import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/team_entry/team_entry_page.dart';
import 'package:clockifai/features/time_entries/duration_chips.dart';
import 'package:clockifai/features/today/day_plan.dart' show Span, TypicalDay;
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'team_test.dart' show member, ws;
import 'time_entry_repository_test.dart' show TestDb;

class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace);
  @override
  final Workspace workspace;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => 'karim';
  @override
  String get role => 'owner';
  @override
  bool get isAdmin => true;
  @override
  bool get isManager => true;
  @override
  Profile? get profile => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, {SessionController? session, CatalogController? catalog}) {
  final app = MaterialApp(
    locale: const Locale('fr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
  if (session == null) return app;
  return MultiProvider(providers: [
    ChangeNotifierProvider<SessionController>.value(value: session),
    ChangeNotifierProvider<CatalogController>.value(value: catalog!),
  ], child: app);
}

/// Téléphone (plans/13-ux-moderne.md, lot 9) : durée au pouce, pointage d'équipe.
void main() {
  group('durée au pouce', () {
    testWidgets('±15 min, durées toutes faites, matin et après-midi de la journée type', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_app(DurationChips(
        typical: TypicalDay.fallback,
        onNudge: (m) => calls.add('nudge $m'),
        onLength: (m) => calls.add('length $m'),
        onRange: (s, e) => calls.add('range ${s.hour}:${s.minute} ${e.hour}:${e.minute}'),
      )));
      for (final label in ['−15 min', '+15 min', '30 min', '2 h', 'Matin', 'Après-midi']) {
        await tester.tap(find.text(label));
      }
      expect(calls, ['nudge -15', 'nudge 15', 'length 30', 'length 120', 'range 8:30 12:30', 'range 14:0 17:30']);
    });

    test('sans pause : la journée coupée en deux, au quart d’heure', () {
      const chips = DurationChips(typical: TypicalDay(start: 480, lunch: null, end: 1000, target: 520, fromHistory: false));
      expect(chips.halves, (const Span(480, 735), const Span(735, 1000)));
    });
  });

  group('pointage d’équipe', () {
    late TestDb db;
    late CatalogController catalog;
    late Workspace workspace;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setUp(() async {
      db = TestDb();
      getIt
        ..registerSingleton<TimeEntryRepository>(TimeEntryRepository(db))
        ..registerSingleton<ModulesRepository>(ModulesRepository(db));
      await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Chantier'));
      workspace = await db.select(db.workspaces).getSingle();
      for (final m in [member('karim', role: 'owner'), member('camille'), member('leo'), member('nina')]) {
        await db.into(db.workspaceMembers).insert(m);
      }
      // Camille est en congé validé aujourd'hui ; Léo a déjà 2 h.
      await db.into(db.timeOffRequests).insert(TimeOffRequestsCompanion.insert(
          workspaceId: ws, userId: 'camille', policyId: 'conges', startDate: dayKey(today), endDate: dayKey(today), amount: 1,
          status: const Value('approved')));
      await getIt<TimeEntryRepository>().createManual(
          workspaceId: ws, userId: 'leo', start: today.add(const Duration(hours: 7)), end: today.add(const Duration(hours: 9)),
          draft: EntryDraft(description: 'Livraison'));
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

    testWidgets('présents cochés d’office, absence validée exclue, journée déjà saisie décochée ; Annuler', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const TeamEntryPage(), session: _Session(workspace), catalog: catalog));
      await settle(tester);

      bool? ticked(String name) => tester
          .widget<Checkbox>(find.descendant(of: find.widgetWithText(ListTile, name), matching: find.byType(Checkbox)))
          .value;
      expect(find.text('Absence validée'), findsOneWidget);
      expect(find.text('Déjà saisi : 2:00'), findsOneWidget);
      expect((ticked('camille'), ticked('leo'), ticked('nina'), ticked('karim')), (false, false, true, false));
      expect(
          tester.widget<Checkbox>(find.descendant(of: find.widgetWithText(ListTile, 'camille'), matching: find.byType(Checkbox))).onChanged,
          isNull,
          reason: 'absence validée : la case ne se coche pas');

      await tester.ensureVisible(find.text('Créer les entrées'));
      await tester.tap(find.text('Créer les entrées'));
      await settle(tester);
      Future<List<TimeEntry>> created() async =>
          (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.deletedAt.isNull() & t.description.equals(''))).get()))!;
      expect([for (final e in await created()) e.userId], ['nina']);
      expect(find.text('1 entrée créée'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Annuler'));
      await settle(tester);
      expect(await created(), isEmpty);
      expect(ticked('nina'), isTrue, reason: 'les présents se recochent');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });
}
