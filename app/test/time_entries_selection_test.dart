import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/display_prefs.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/core/shortcuts.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/time_entries/time_entries_page.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Sélection multiple, barre d'actions et clavier du « Suivi du temps » (plans/13-ux-moderne.md, lot 1).
void main() {
  late TestDb db;
  late CatalogController catalog;
  late DisplayPrefs prefs;
  late Workspace workspace;

  // Aujourd'hui (horloge réelle : la page affiche les deux dernières semaines).
  final today = DateTime.now();
  DateTime at(int h) => DateTime(today.year, today.month, today.day, h);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'group_similar_entries': false});
    prefs = DisplayPrefs(await SharedPreferences.getInstance());
    db = TestDb();
    await db.into(db.workspaces).insert(WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier'));
    workspace = await db.select(db.workspaces).getSingle();
    final catalogRepo = CatalogRepository(db);
    final project = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
    catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    final repo = TimeEntryRepository(db);
    getIt.registerSingleton<TimeEntryRepository>(repo);
    for (final (desc, h) in [('Pose', 8), ('Câblage', 9), ('Réunion', 10)]) {
      await repo.createManual(
        workspaceId: ws,
        userId: me,
        start: at(h),
        end: at(h + 1),
        draft: EntryDraft(description: desc, projectId: project),
      );
    }
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

  Future<void> open(WidgetTester tester, {Size size = const Size(1200, 900), String? user}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _Session(workspace)),
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
        home: Scaffold(body: AppShortcuts(onKey: (_) => false, child: TimeEntriesPage(initialUserId: user))),
      ),
    ));
    await settle(tester);
  }

  /// Démonte l'écran : arrête les flux Drift et le minuteur du bandeau avant la fermeture de la base.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<Map<String, (bool, bool)>> entries(WidgetTester tester) async => {
        for (final e in (await tester.runAsync(() => db.select(db.timeEntries).get()))!) e.description: (e.billable, e.deletedAt != null),
      };

  testWidgets('J / X sélectionnent au clavier ; la barre rend deux entrées non facturables, Annuler les rend', (tester) async {
    await open(tester);
    expect(find.text('Non facturable'), findsNothing, reason: 'pas de barre sans sélection');

    for (final key in [LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyX]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(find.text('2 sélectionnées · 2:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Non facturable'));
    await settle(tester);
    final after = await entries(tester);
    expect(after.values.where((v) => !v.$1), hasLength(2));
    expect(after['Pose']!.$1, isTrue, reason: 'la troisième (la plus ancienne) n’était pas sélectionnée');
    expect(find.text('2 entrées modifiées'), findsOneWidget);
    expect(find.textContaining('sélectionnées'), findsNothing, reason: 'la sélection se vide après l’action');

    await tester.pump(const Duration(milliseconds: 500)); // le bandeau finit d'entrer
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await entries(tester)).values.every((v) => v.$1), isTrue);
    await close(tester);
  });

  testWidgets('appui long : sélectionner ; Échap : tout désélectionner', (tester) async {
    await open(tester);
    await tester.longPress(find.text('Pose'));
    await tester.pump();
    expect(find.text('1 sélectionnée · 1:00'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.textContaining('sélectionnée'), findsNothing);
    await close(tester);
  });

  testWidgets('⌫ supprime l’entrée sous le curseur, Annuler la rend', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(tester);
    expect((await entries(tester)).values.where((v) => v.$2), hasLength(1));
    expect(find.text('1 entrée supprimée'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await entries(tester)).values.where((v) => v.$2), isEmpty);
    await close(tester);
  });

  testWidgets('une touche seule n’agit pas pendant la saisie', (tester) async {
    await open(tester);
    await tester.tap(find.text('Pose')); // description modifiable sur place
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(tester);
    expect(find.textContaining('sélectionnée'), findsNothing);
    expect((await entries(tester)).values.where((v) => v.$2), isEmpty);
    await close(tester);
  });

  testWidgets('téléphone : glisser à gauche supprime (Annuler), à droite duplique sur aujourd’hui', (tester) async {
    await open(tester, size: const Size(600, 900));
    Future<void> swipe(String text, double dx) async {
      await tester.drag(find.text(text), Offset(dx, 0));
      // L'animation du glisser (deux images : départ, puis fin), puis l'action en base.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await swipe('Pose', -400);
    await settle(tester);
    expect((await entries(tester))['Pose']!.$2, isTrue);
    expect(find.text('Entrée supprimée'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect((await entries(tester))['Pose']!.$2, isFalse);

    await swipe('Câblage', 400);
    await settle(tester);
    final copies = (await tester.runAsync(() => (db.select(db.timeEntries)..where((t) => t.description.equals('Câblage'))).get()))!;
    expect(copies, hasLength(2));
    expect(copies.map((e) => e.startAt.toLocal()).toSet(), {at(9)}, reason: 'même heure, aujourd’hui');
    expect(find.text('1 entrée dupliquée'), findsOneWidget);
    await close(tester);
  });

  testWidgets('écran large : pas de glisser', (tester) async {
    await open(tester);
    expect(find.byType(Dismissible), findsNothing);
    await close(tester);
  });

  group('personne affichée', () {
    const agent = 'agent-1';

    setUp(() async {
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(
          workspaceId: ws, userId: me, displayName: const Value('Yannick'), kind: const Value('human')));
      await db.into(db.workspaceMembers).insert(WorkspaceMembersCompanion.insert(
          workspaceId: ws, userId: agent, displayName: const Value('Claude - Yannick'), kind: const Value('agent'),
          agentOwnerId: const Value(me)));
      // Le pilote voit son agent (team_scope, recalculé par le serveur).
      await db.into(db.teamScope).insert(TeamScopeCompanion.insert(workspaceId: ws, managerId: me, userId: agent));
      await getIt<TimeEntryRepository>().createManual(
          workspaceId: ws, userId: agent, start: at(14), end: at(15), draft: EntryDraft(description: 'Plan 19'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    testWidgets('le pilote choisit son agent Claude dans la liste et voit ses entrées', (tester) async {
      await open(tester);
      expect(find.text('Pose'), findsOneWidget);
      expect(find.text('Plan 19'), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await settle(tester);
      await tester.tap(find.text('Claude - Yannick').last);
      await settle(tester);
      expect(find.text('Plan 19'), findsOneWidget);
      expect(find.text('Pose'), findsNothing);
      expect(find.text('Temps de Claude - Yannick : vous pouvez corriger ses entrées, pas en ajouter.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('la personne arrive d’une autre vue de la semaine (?user=)', (tester) async {
      await open(tester, user: agent);
      expect(find.text('Plan 19'), findsOneWidget);
      expect(find.text('Pose'), findsNothing);
      await close(tester);
    });
  });
}
