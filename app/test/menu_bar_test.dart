import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/di.dart';
import 'package:clockifai/core/session.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/timer/menu_bar.dart';
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
const channel = MethodChannel('clockifai/menu_bar');
const codec = StandardMethodCodec();

/// Session minimale : utilisateur connecté dans un workspace.
class _Session extends ChangeNotifier implements SessionController {
  _Session(this.workspace);
  @override
  final Workspace workspace;
  @override
  String? get workspaceId => workspace.id;
  @override
  String? get userId => me;
  @override
  bool get isSignedIn => true;
  @override
  bool get waitingForFirstSync => false;
  @override
  int get runningTimersLimit => workspace.maxRunningTimers ?? 1;
  @override
  Profile? profile;
  @override
  bool get isAdmin => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestDb db;
  late CatalogController catalog;
  late Workspace workspace;
  late String chantier;
  final updates = <Map<Object?, Object?>>[];

  setUp(() async {
    db = TestDb();
    getIt.registerSingleton<TimeEntryRepository>(TimeEntryRepository(db));
    getIt.registerSingleton<ModulesRepository>(ModulesRepository(db));
    await db.into(db.workspaces).insert(
        WorkspacesCompanion.insert(id: const Value(ws), name: 'Atelier', requireProject: const Value(true)));
    workspace = await db.select(db.workspaces).getSingle();
    final repo = CatalogRepository(db);
    chantier = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier'));
    catalog = CatalogController(repo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    updates.clear();
  });

  tearDown(() async {
    catalog.dispose();
    await getIt.reset();
    await db.close();
  });

  /// Laisse passer les requêtes Drift puis l'envoi groupé de l'état.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  /// Commande du panneau natif ; renvoie la réponse de Flutter.
  Future<Object?> send(WidgetTester tester, String method, Map<String, Object?> args) async {
    Object? reply;
    await tester.runAsync(() => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name, codec.encodeMethodCall(MethodCall(method, args)), (data) => reply = codec.decodeEnvelope(data!)));
    await settle(tester);
    return reply;
  }

  Map<Object?, Object?>? running() => updates.last['running'] as Map<Object?, Object?>?;
  List<Object?> recent() => updates.last['recent']! as List<Object?>;

  testWidgets('panneau de la barre de menus : état envoyé et commandes du chronomètre', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') updates.add((call.arguments as Map).cast());
      return null;
    });
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
        builder: (context, child) => MacMenuBar(child: child!),
        home: const SizedBox(),
      ),
    ));
    await settle(tester);

    expect(updates.last['signedIn'], true);
    expect(updates.last['ready'], true);
    expect(running(), null);
    expect((updates.last['labels'] as Map)['whatAreYouWorkingOn'], 'Sur quoi travaillez-vous ?');
    expect((updates.last['projects'] as List).map((p) => (p as Map)['name']), ['Chantier']);

    // Règle du workspace : projet obligatoire, le message s'affiche dans le panneau.
    expect(await send(tester, 'start', {'description': 'Pose', 'projectId': null}), 'Un projet est obligatoire dans ce workspace.');
    expect(running(), null);

    expect(await send(tester, 'start', {'description': 'Pose', 'projectId': chantier}), null);
    expect(running()!['description'], 'Pose');
    expect(running()!['project'], 'Chantier');
    expect(running()!['start'], isA<int>());

    await send(tester, 'setDescription', {'description': 'Pose carrelage'});
    expect(running()!['description'], 'Pose carrelage');

    await send(tester, 'stop', {'description': 'Pose carrelage'});
    expect(running(), null);
    expect(recent(), hasLength(1));
    final last = recent().single! as Map<Object?, Object?>;
    expect(last['description'], 'Pose carrelage');

    // « Continuer » relance la même description et le même projet.
    await send(tester, 'continue', {'id': last['id']});
    expect(running()!['description'], 'Pose carrelage');
    expect(running()!['project'], 'Chantier');
    expect(running()!['id'], isNot(last['id']));

    // Un chronomètre par tâche : relancer ou redémarrer la même activité est refusé, rien ne change.
    final current = running()!['id'];
    const alreadyRunning = 'Un chronomètre tourne déjà sur cette tâche';
    expect(await send(tester, 'continue', {'id': last['id']}), alreadyRunning);
    expect(await send(tester, 'start', {'description': 'Pose carrelage', 'projectId': chantier}), alreadyRunning);
    expect(running()!['id'], current);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero); // minuteurs de Drift à la fermeture des flux
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('saisie express dans la barre de menus : aperçu à la frappe, puis l’entrée rangée', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') updates.add((call.arguments as Map).cast());
      return null;
    });
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
        builder: (context, child) => MacMenuBar(child: child!),
        home: const SizedBox(),
      ),
    ));
    await settle(tester);
    expect((updates.last['labels'] as Map)['quickEntry'], 'Saisie express');

    final preview = (await send(tester, 'previewQuick', {'text': '1h30 pose chantier hier'}))! as Map;
    expect(preview['ready'], true);
    expect(preview['preview'], '1:30 · Chantier · « Pose » · Hier 08:30 → 10:00');
    expect(((await send(tester, 'previewQuick', {'text': 'pose chantier'}))! as Map)['ready'], false, reason: 'pas de durée');

    final saved = (await send(tester, 'quickEntry', {'text': '1h30 pose chantier hier'}))! as Map;
    expect(saved, {'ok': true, 'message': 'Ajouté : Pose · Hier, 08:30 → 10:00'});
    final entry = (await tester.runAsync(() => db.select(db.timeEntries).getSingle()))!;
    final now = DateTime.now();
    expect((entry.description, entry.projectId, entry.startAt.toLocal()), ('Pose', chantier, DateTime(now.year, now.month, now.day - 1, 8, 30)));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
