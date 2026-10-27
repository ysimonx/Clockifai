import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:clockifai/features/reports/report_model.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, GroupBy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Base de test : en production PowerSync crée les tables ; ici Drift les crée en mémoire.
class TestDb extends AppDatabase {
  TestDb() : super(NativeDatabase.memory());

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}

const ws = 'ws-1';
const me = 'user-1';

void main() {
  late TestDb db;
  late TimeEntryRepository repo;

  setUp(() {
    db = TestDb();
    repo = TimeEntryRepository(db);
  });
  tearDown(() => db.close());

  test('un seul chronomètre : démarrer arrête le précédent', () async {
    final first = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'A'), at: DateTime.utc(2026, 10, 11, 8));
    final second = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'B'), at: DateTime.utc(2026, 10, 11, 9));
    final running = await repo.watchRunning(ws, me).first;
    expect(running!.id, second);
    final a = await (db.select(db.timeEntries)..where((t) => t.id.equals(first))).getSingle();
    expect(a.endAt, DateTime.utc(2026, 10, 11, 9));
    expect(a.durationSeconds, 3600);
  });

  test('limite 2 : deux chronomètres tournent en parallèle, les plus récents d\'abord', () async {
    final a = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'A'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 2);
    final b = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'B'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 2);
    final running = await repo.watchRunningAll(ws, me).first;
    expect(running.map((e) => e.id), [b, a]);
  });

  test('limite 2 atteinte : le plus ancien s\'arrête au début du nouveau', () async {
    final a = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'A'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 2);
    final b = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'B'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 2);
    final c = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'C'), at: DateTime.utc(2026, 10, 11, 10), maxRunning: 2);
    final running = await repo.watchRunningAll(ws, me).first;
    expect(running.map((e) => e.id), [c, b]);
    final stopped = await (db.select(db.timeEntries)..where((t) => t.id.equals(a))).getSingle();
    expect(stopped.endAt, DateTime.utc(2026, 10, 11, 10));
    expect(stopped.durationSeconds, 2 * 3600);
  });

  test('limite 0 (illimité) : rien ne s\'arrête', () async {
    for (var h = 8; h < 12; h++) {
      await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'T$h'), at: DateTime.utc(2026, 10, 11, h), maxRunning: 0);
    }
    expect(await repo.watchRunningAll(ws, me).first, hasLength(4));
  });

  test('un chronomètre par tâche : relancer la même tâche ne crée rien et n\'arrête rien', () async {
    final a = await repo.start(
        workspaceId: ws, userId: me, draft: EntryDraft(description: 'Revue', projectId: 'p1', taskId: 't1'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 3);
    final again = await repo.start(
        workspaceId: ws, userId: me, draft: EntryDraft(description: 'Correctif', projectId: 'p1', taskId: 't1'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 3);
    expect(again, a);
    final running = await repo.watchRunningAll(ws, me).first;
    expect(running.map((e) => e.id), [a]);
    expect(running.single.startAt, DateTime.utc(2026, 10, 11, 8));
  });

  test('un chronomètre par tâche : deux tâches différentes tournent en parallèle', () async {
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(projectId: 'p1', taskId: 't1'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 3);
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(projectId: 'p1', taskId: 't2'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 3);
    expect(await repo.watchRunningAll(ws, me).first, hasLength(2));
  });

  test('sans tâche : même projet et même description = même chronomètre ; autre description = autre chronomètre', () async {
    final a = await repo.start(
        workspaceId: ws, userId: me, draft: EntryDraft(description: 'Réunion', projectId: 'p1'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 3);
    expect(
        await repo.start(
            workspaceId: ws, userId: me, draft: EntryDraft(description: 'Réunion ', projectId: 'p1'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 3),
        a);
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'Support', projectId: 'p1'), at: DateTime.utc(2026, 10, 11, 10), maxRunning: 3);
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'Réunion'), at: DateTime.utc(2026, 10, 11, 11), maxRunning: 3);
    expect(await repo.watchRunningAll(ws, me).first, hasLength(3));
  });

  test('sameTimerTarget : une tâche d\'un côté seulement ne correspond pas', () async {
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'Revue', projectId: 'p1', taskId: 't1'), maxRunning: 3);
    final running = (await repo.watchRunningAll(ws, me).first).single;
    expect(sameTimerTarget(running, description: 'Autre', projectId: 'p1', taskId: 't1'), isTrue);
    expect(sameTimerTarget(running, description: 'Revue', projectId: 'p1', taskId: null), isFalse);
    expect(sameTimerTarget(running, description: 'Revue', projectId: 'p1', taskId: 't2'), isFalse);
  });

  test('chronomètres en cours de plusieurs membres (bandeau « Claude travaille »)', () async {
    const agent = 'agent-1';
    final a = await repo.start(workspaceId: ws, userId: agent, draft: EntryDraft(description: 'clockifai (main)'), at: DateTime.utc(2026, 10, 11, 8), maxRunning: 0);
    final b = await repo.start(workspaceId: ws, userId: agent, draft: EntryDraft(description: 'fidwork (main)'), at: DateTime.utc(2026, 10, 11, 9), maxRunning: 0);
    final done = await repo.start(workspaceId: ws, userId: agent, draft: EntryDraft(), at: DateTime.utc(2026, 10, 11, 7), maxRunning: 0);
    await repo.stop(done, at: DateTime.utc(2026, 10, 11, 7, 30));
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'Moi'), at: DateTime.utc(2026, 10, 11, 8));
    expect((await repo.watchRunningOf(ws, [agent]).first).map((e) => e.id), [a, b]);
    expect(await repo.watchRunningOf(ws, [agent, me]).first, hasLength(3));
    expect(await repo.watchRunningOf('ws-2', [agent]).first, isEmpty);
    expect(await repo.watchRunningOf(ws, const []).first, isEmpty);
  });

  test('arrêt avec horloge en retard : fin jamais avant le début', () async {
    final id = await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(), at: DateTime.utc(2026, 10, 11, 10));
    await repo.stop(id, at: DateTime.utc(2026, 10, 11, 9, 59));
    final e = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
    expect(e.endAt, e.startAt);
  });

  test('filtre de période indépendant du format texte des dates (serveur vs client)', () async {
    // Ligne au format renvoyé par le serveur (espace, microsecondes, Z)...
    await db.customStatement(
      "INSERT INTO time_entries (id, workspace_id, user_id, description, start_at, end_at, billable, locked) "
      "VALUES ('srv', '$ws', '$me', 'serveur', '2026-10-11 15:00:00.123456Z', '2026-10-11 16:00:00Z', 1, 0)",
    );
    // ...et une ligne écrite par l'app (format ISO de Dart).
    await repo.createManual(
      workspaceId: ws,
      userId: me,
      draft: EntryDraft(description: 'client'),
      start: DateTime.utc(2026, 10, 11, 9),
      end: DateTime.utc(2026, 10, 11, 10),
    );
    final rows = await repo
        .watchEntries(workspaceId: ws, userId: me, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12))
        .first;
    expect(rows.map((r) => r.entry.description), ['serveur', 'client']); // tri décroissant correct
    final none = await repo
        .watchEntries(workspaceId: ws, userId: me, from: DateTime.utc(2026, 10, 11, 16), to: DateTime.utc(2026, 10, 12))
        .first;
    expect(none, isEmpty);
  });

  test('tags : ajout, remplacement, lecture groupée', () async {
    final id = await repo.createManual(
      workspaceId: ws,
      userId: me,
      draft: EntryDraft(tagIds: ['t1', 't2']),
      start: DateTime.utc(2026, 10, 11, 9),
      end: DateTime.utc(2026, 10, 11, 10),
    );
    expect((await repo.tagIdsOf(id)).toSet(), {'t1', 't2'});
    final entry = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
    await repo.update(entry, tagIds: ['t2', 't3']);
    expect((await repo.tagIdsOf(id)).toSet(), {'t2', 't3'});
    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12)).first;
    expect(rows.single.tagIds.toSet(), {'t2', 't3'});
  });

  test('suppression logique : disparaît des listes', () async {
    final id = await repo.createManual(
      workspaceId: ws, userId: me, draft: EntryDraft(),
      start: DateTime.utc(2026, 10, 11, 9), end: DateTime.utc(2026, 10, 11, 10),
    );
    await repo.delete(id);
    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12)).first;
    expect(rows, isEmpty);
    final raw = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
    expect(raw.deletedAt, isNotNull);
  });

  test('Annuler : une entrée supprimée revient, même déjà retirée de la base locale par la synchronisation', () async {
    Future<String> make(String desc) => repo.createManual(
          workspaceId: ws, userId: me, draft: EntryDraft(description: desc, projectId: 'p1', hourlyRateCents: 5000),
          start: DateTime.utc(2026, 10, 11, 9), end: DateTime.utc(2026, 10, 11, 10),
        );
    final a = await make('Encore là');
    final b = await make('Déjà repartie');
    final before = await repo.deleteMany([a, b]);
    expect(before.map((e) => (e.description, e.deletedAt)).toSet(), {('Encore là', null), ('Déjà repartie', null)});
    // La synchronisation retire de la base locale ce que le serveur a supprimé.
    await (db.delete(db.timeEntries)..where((t) => t.id.equals(b))).go();

    await repo.restore(before);
    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12)).first;
    expect(rows.map((r) => (r.entry.description, r.entry.projectId, r.entry.hourlyRateCents)).toSet(),
        {('Encore là', 'p1', 5000), ('Déjà repartie', 'p1', 5000)});
  });

  test('Annuler une modification : tout revient, un tarif vide compris', () async {
    final id = await repo.createManual(
      workspaceId: ws, userId: me, draft: EntryDraft(description: 'Avant'),
      start: DateTime.utc(2026, 10, 11, 9), end: DateTime.utc(2026, 10, 11, 10),
    );
    final before = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
    await repo.update(before, description: 'Après', projectId: 'p2', hourlyRateCents: 7000);
    await repo.restore([before]);
    final after = await (db.select(db.timeEntries)..where((t) => t.id.equals(id))).getSingle();
    expect((after.description, after.projectId, after.hourlyRateCents, after.deletedAt), ('Avant', null, null, null));
  });

  test('feuille de temps : ajouter puis réduire le total d\'une cellule', () async {
    final day = DateTime(2026, 10, 7);
    await repo.setDayTotal(workspaceId: ws, userId: me, projectId: 'p1', dayLocal: day, targetSeconds: 2 * 3600, billable: true);
    await repo.setDayTotal(workspaceId: ws, userId: me, projectId: 'p1', dayLocal: day, targetSeconds: 3 * 3600, billable: true);
    Future<int> total() async {
      final rows = await repo.watchEntries(workspaceId: ws, userId: me, from: day, to: day.add(const Duration(days: 1))).first;
      return rows.where((r) => r.entry.projectId == 'p1').fold<int>(0, (s, r) => s + r.seconds);
    }

    expect(await total(), 3 * 3600);
    await repo.setDayTotal(workspaceId: ws, userId: me, projectId: 'p1', dayLocal: day, targetSeconds: 30 * 60, billable: true);
    expect(await total(), 30 * 60);
    await repo.setDayTotal(workspaceId: ws, userId: me, projectId: 'p1', dayLocal: day, targetSeconds: 0, billable: true);
    expect(await total(), 0);
  });

  test('entrées récentes : une par description / projet, chronomètre et supprimées exclus', () async {
    Future<String> entry(String description, int hour, {String? projectId}) => repo.createManual(
          workspaceId: ws, userId: me, draft: EntryDraft(description: description, projectId: projectId),
          start: DateTime.utc(2026, 10, 11, hour), end: DateTime.utc(2026, 10, 11, hour, 30),
        );
    await entry('Rédaction', 8);
    await entry('Rédaction', 9, projectId: 'p1');
    final latest = await entry('Rédaction', 10);
    final deleted = await entry('Supprimée', 11);
    await repo.delete(deleted);
    await repo.createManual(
      workspaceId: ws, userId: 'user-2', draft: EntryDraft(description: 'Collègue'),
      start: DateTime.utc(2026, 10, 11, 12), end: DateTime.utc(2026, 10, 11, 13),
    );
    await repo.start(workspaceId: ws, userId: me, draft: EntryDraft(description: 'En cours'), at: DateTime.utc(2026, 10, 11, 14));

    final recent = await repo.watchRecent(ws, me).first;
    expect(recent.map((r) => (r.entry.description, r.entry.projectId)), [('Rédaction', null), ('Rédaction', 'p1')]);
    expect(recent.first.entry.id, latest);
    expect(await repo.watchRecent(ws, me, limit: 1).first, hasLength(1));
  });

  test('rapport : regroupement, montants et arrondi', () async {
    final catalogRepo = CatalogRepository(db);
    final p1 = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Site web', hourlyRateCents: const Value(5000)));
    await repo.createManual(
      workspaceId: ws, userId: me, draft: EntryDraft(projectId: p1, hourlyRateCents: 5000),
      start: DateTime.utc(2026, 10, 11, 9), end: DateTime.utc(2026, 10, 11, 10, 7),
    );
    await repo.createManual(
      workspaceId: ws, userId: me, draft: EntryDraft(billable: false),
      start: DateTime.utc(2026, 10, 11, 11), end: DateTime.utc(2026, 10, 11, 11, 30),
    );
    final catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12)).first;

    final exact = ReportCalculator(catalog: catalog, roundingMinutes: 15, applyRounding: false);
    final t = exact.totals(rows);
    expect(t.total, 67 * 60 + 30 * 60);
    expect(t.billable, 67 * 60);
    expect(t.amount, closeTo(67 / 60 * 50, 0.001));

    final rounded = ReportCalculator(catalog: catalog, roundingMinutes: 15, applyRounding: true);
    expect(rounded.totals(rows).total, 60 * 60 + 30 * 60); // 67 min → 60, 30 → 30

    final groups = exact.group(rows, GroupBy.project,
        noProject: '—', noClient: '—', noTag: '—', noDescription: '—', dayLabel: (d) => '$d');
    expect(groups.map((g) => g.label), ['Site web', '—']);
    catalog.dispose();
  });

  test('sous-tâches : catalogue, libellés et rapport par tâche (plans/16-sous-taches.md)', () async {
    final catalogRepo = CatalogRepository(db);
    final p1 = await catalogRepo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Clockifai'));
    final plan = await catalogRepo.createTask(ws, p1, 'Plan 16 · Sous-tâches');
    final migration = await catalogRepo.createTask(ws, p1, 'Migration', parentId: plan);
    final ecran = await catalogRepo.createTask(ws, p1, 'Écran des projets', parentId: plan);
    final other = await catalogRepo.createTask(ws, p1, 'Support');
    Future<void> add(String task, int h, int minutes) => repo.createManual(
          workspaceId: ws, userId: me, draft: EntryDraft(projectId: p1, taskId: task),
          start: DateTime.utc(2026, 10, 27, h), end: DateTime.utc(2026, 10, 27, h, minutes));
    await add(migration, 8, 30);
    await add(ecran, 9, 45);
    await add(plan, 10, 15);
    await add(other, 11, 20);
    final catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(catalog.tasksOf(p1).map((t) => t.name), ['Plan 16 · Sous-tâches', 'Support'], reason: 'premier niveau seulement');
    expect(catalog.subtasksOf(plan).map((t) => t.name), unorderedEquals(['Écran des projets', 'Migration']));
    expect(catalog.rootTask(migration)?.id, plan);
    expect(catalog.taskPath(migration), 'Plan 16 · Sous-tâches › Migration');
    expect(catalog.taskPath(plan), 'Plan 16 · Sous-tâches');

    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 27), to: DateTime.utc(2026, 10, 28)).first;
    final groups = ReportCalculator(catalog: catalog, roundingMinutes: 0, applyRounding: false).group(rows, GroupBy.task,
        noProject: '—', noClient: '—', noTag: '—', noDescription: '—', dayLabel: (d) => '$d', noTask: 'Sans tâche');
    expect(groups.map((g) => (g.label, g.seconds ~/ 60)), [('Plan 16 · Sous-tâches', 90), ('Support', 20)]);
    expect(groups.first.children.map((c) => (c.label, c.seconds ~/ 60)), [('Écran des projets', 45), ('Migration', 30)],
        reason: 'le temps posé sur la tâche elle-même compte dans la tâche, pas dans une sous-tâche');

    await catalogRepo.deleteTask(plan);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(catalog.task(migration), isNull, reason: 'les sous-tâches partent avec leur tâche');
    catalog.dispose();
  });

  test('usage IA d\'une entrée d\'agent : cumulé sur la ligne et dans le rapport (plan 10, D17)', () async {
    final catalogRepo = CatalogRepository(db);
    final claude = await repo.createManual(
      workspaceId: ws, userId: 'agent-1', draft: EntryDraft(description: 'Export PDF'),
      start: DateTime.utc(2026, 10, 11, 9), end: DateTime.utc(2026, 10, 11, 10),
    );
    await repo.createManual(
      workspaceId: ws, userId: me, draft: EntryDraft(description: 'Relecture'),
      start: DateTime.utc(2026, 10, 11, 11), end: DateTime.utc(2026, 10, 11, 12),
    );
    Future<void> usage(String model, {int? cost, DateTime? deletedAt}) => db.into(db.agentUsage).insert(AgentUsageCompanion.insert(
          workspaceId: ws, timeEntryId: claude, userId: 'agent-1', model: model,
          inputTokens: const Value(10), outputTokens: const Value(2000), cacheWrite5mTokens: const Value(1000),
          cacheWrite1hTokens: const Value(20000), cacheReadTokens: const Value(300000), costMicros: Value(cost),
          deletedAt: Value(deletedAt),
        ));
    await usage('claude-opus-5-5', cost: 265040);
    await usage('claude-futur-9'); // tarif inconnu : tokens comptés, pas de coût
    await usage('claude-haiku-5-5', cost: 8126, deletedAt: DateTime.utc(2026, 10, 12)); // usage passé à une autre entrée

    final rows = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 11), to: DateTime.utc(2026, 10, 12)).first;
    final agent = rows.singleWhere((r) => r.entry.id == claude);
    expect(agent.aiTokens, 2 * 323010);
    expect(agent.aiCostMicros, 265040);
    final human = rows.singleWhere((r) => r.entry.id != claude);
    expect((human.aiTokens, human.aiCostMicros), (0, null));
    expect((await repo.watchUsage(claude).first).map((u) => u.model), ['claude-opus-5-5', 'claude-futur-9']);

    final catalog = CatalogController(catalogRepo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    final t = ReportCalculator(catalog: catalog, roundingMinutes: 0, applyRounding: false).totals(rows);
    expect((t.aiTokens, t.aiCostMicros), (2 * 323010, 265040));
    catalog.dispose();
  });
}
