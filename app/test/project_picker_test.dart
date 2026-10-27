import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/core/widgets/pickers.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'time_entry_repository_test.dart' show TestDb;

const ws = 'ws-1';

/// Session minimale : seuls les droits lus par le sélecteur.
class _Session extends ChangeNotifier implements SessionController {
  _Session({required this.canCreateTasks});
  @override
  final bool canCreateTasks;
  @override
  bool get isManager => false;
  @override
  String? get workspaceId => ws;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestDb db;
  late CatalogRepository repo;
  late CatalogController catalog;
  late String chantier;
  late String bureau;
  late String pose;

  setUp(() async {
    db = TestDb();
    repo = CatalogRepository(db);
    getIt.registerSingleton<CatalogRepository>(repo);
    chantier = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
    bureau = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Bureau'));
    pose = await repo.createTask(ws, chantier, 'Pose');
    catalog = CatalogController(repo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    catalog.dispose();
    await getIt.reset();
    await db.close();
  });

  /// Ouvre le sélecteur ; la valeur retournée est lue via [result] après fermeture.
  Future<ProjectPick? Function()> open(WidgetTester tester, {bool canCreateTasks = true, String? projectId, String? taskId}) async {
    ProjectPick? picked;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _Session(canCreateTasks: canCreateTasks)),
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
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showProjectPicker(context, projectId: projectId, taskId: taskId),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return () => picked;
  }

  /// Laisse Drift écrire et notifier (vraie asynchronie), puis reconstruit.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('tâches repliées sous leur projet, dépliées à la demande', (tester) async {
    final result = await open(tester);
    expect(find.text('Pose'), findsNothing);
    await tester.tap(find.text('1 tâche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pose'));
    await tester.pumpAndSettle();
    expect(result()?.projectId, chantier);
    expect(result()?.taskId, pose);
  });

  testWidgets('la tâche courante est dépliée d\'office et la recherche montre les tâches', (tester) async {
    await open(tester, projectId: chantier, taskId: pose);
    expect(find.text('Pose'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pos');
    await tester.pumpAndSettle();
    expect(find.text('Pose'), findsOneWidget);
    expect(find.text('Bureau'), findsNothing);
  });

  testWidgets('recherche sans résultat : crée la tâche dans le projet choisi', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), 'Peinture ');
    await tester.pumpAndSettle();
    expect(find.text('Créer la tâche « Peinture » dans :'), findsOneWidget);
    await tester.tap(find.text('Bureau'));
    await settle(tester);

    final created = catalog.tasksOf(bureau).single;
    expect(created.name, 'Peinture');
    expect(result()?.projectId, bureau);
    expect(result()?.taskId, created.id);
  });

  testWidgets('bouton + : un nom déjà pris sélectionne la tâche existante', (tester) async {
    final result = await open(tester);
    await tester.tap(find.byTooltip('Créer une tâche').first); // Bureau (tri par nom)
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle tâche dans Bureau'), findsOneWidget);
    await tester.tap(find.text('Annuler').last); // celui de la saisie du nom
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Créer une tâche').last); // Chantier
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.widgetWithText(AlertDialog, 'Nouvelle tâche dans Chantier'), matching: find.byType(TextField)),
        'pose');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(catalog.tasksOf(chantier), hasLength(1));
    expect(result()?.taskId, pose);
  });

  testWidgets('URL de ticket collée : retrouve sa tâche, sinon la crée avec son titre', (tester) async {
    const url = 'https://linear.app/acme/issue/ENG-123/formulaire-de-commande';
    var result = await open(tester);
    await tester.enterText(find.byType(TextField), url);
    await tester.pumpAndSettle();
    expect(find.text('Créer la tâche du ticket ENG-123 dans :'), findsOneWidget);
    await tester.tap(find.text('Bureau'));
    await tester.pumpAndSettle();
    expect(find.text('Tâche du ticket ENG-123'), findsOneWidget);
    await tester.enterText(
        find.descendant(of: find.widgetWithText(AlertDialog, 'Tâche du ticket ENG-123'), matching: find.byType(TextField)),
        'Formulaire de commande');
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    final created = catalog.tasksOf(bureau).single;
    expect((created.name, created.ticketKey, created.ticketUrl), ('ENG-123 · Formulaire de commande', 'ENG-123', url));
    expect(result()?.taskId, created.id);

    // La clé seule, ou une autre URL du même ticket, la retrouve.
    result = await open(tester);
    await tester.enterText(find.byType(TextField), 'https://acme.atlassian.net/browse/eng-123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENG-123 · Formulaire de commande'));
    await tester.pumpAndSettle();
    expect(result()?.taskId, created.id);
    expect(catalog.tasksOf(bureau), hasLength(1));
  });

  testWidgets('sans le droit de créer : ni bouton +, ni proposition', (tester) async {
    await open(tester, canCreateTasks: false);
    expect(find.byTooltip('Créer une tâche'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Peinture');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
  });
}
