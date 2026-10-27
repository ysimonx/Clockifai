import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/features/projects/budget_watch.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class TestDb extends AppDatabase {
  TestDb() : super(NativeDatabase.memory());
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}

const ws = 'ws-1';
const me = 'user-1';

void main() {
  late TestDb db;
  late CatalogRepository catalog;
  late TimeEntryRepository entries;

  setUp(() {
    db = TestDb();
    catalog = CatalogRepository(db);
    entries = TimeEntryRepository(db);
  });
  tearDown(() => db.close());

  Future<void> add(String? project, int hours, {String? task, int? rate, bool billable = true, bool running = false}) =>
      running
          ? entries.start(workspaceId: ws, userId: me, draft: EntryDraft(projectId: project, taskId: task), maxRunning: 0)
          : entries.createManual(
              workspaceId: ws,
              userId: me,
              draft: EntryDraft(projectId: project, taskId: task, hourlyRateCents: rate, billable: billable),
              start: DateTime.utc(2026, 10, 1, 8),
              end: DateTime.utc(2026, 10, 1, 8 + hours),
            );

  test('consommation : temps et montant au taux de l\'entrée, sinon du projet, sinon du membre', () async {
    await db.into(db.workspaceMembers).insert(
        WorkspaceMembersCompanion.insert(workspaceId: ws, userId: me, hourlyRateCents: const Value(5000)));
    final withRate = await catalog.createProject(
        ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Régie', hourlyRateCents: const Value(8000)));
    final noRate = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Forfait'));
    final task = await catalog.createTask(ws, noRate, 'Montage');
    await add(withRate, 2); // 2 × 80
    await add(withRate, 1, rate: 10000); // 1 × 100
    await add(withRate, 3, billable: false); // compte en temps, pas en montant
    await add(noRate, 2, task: task); // 2 × 50 (membre)
    await add(noRate, 1, running: true); // en cours : ignorée
    final usage = await entries.watchBudgetUsage(ws).first;
    expect(usage.projects[withRate], (seconds: 6 * 3600, amountCents: 26000));
    expect(usage.projects[noRate], (seconds: 2 * 3600, amountCents: 10000));
    expect(usage.tasks, {task: 2 * 3600});
  });

  test('à surveiller : seuil de 80 %, montant, estimation avec sous-tâches, archivés et tâches finies écartés', () async {
    final big = await catalog.createProject(ws,
        ProjectsCompanion.insert(workspaceId: ws, name: 'Chantier', budgetHours: const Value(10), budgetAmountCents: const Value(100000)));
    final calm = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Calme', budgetHours: const Value(10)));
    final old = await catalog.createProject(
        ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Ancien', budgetHours: const Value(1), archived: const Value(true)));
    final montage = await catalog.createTask(ws, big, 'Montage');
    final niveau = await catalog.createTask(ws, big, 'Niveau 3', parentId: montage);
    final done = await catalog.createTask(ws, big, 'Fini');
    await (db.update(db.tasks)..where((t) => t.id.equals(montage))).write(const TasksCompanion(estimateSeconds: Value(4 * 3600)));
    await (db.update(db.tasks)..where((t) => t.id.equals(done)))
        .write(const TasksCompanion(estimateSeconds: Value(3600), status: Value('done')));
    final alerts = budgetWatch(
      projects: await db.select(db.projects).get(),
      tasks: await db.select(db.tasks).get(),
      usage: {big: (seconds: 11 * 3600, amountCents: 85000), calm: (seconds: 7 * 3600, amountCents: 0), old: (seconds: 9 * 3600, amountCents: 0)},
      taskSeconds: {montage: 2 * 3600, niveau: 3600 + 1800, done: 7200},
    );
    expect([for (final a in alerts) (a.kind, a.name, a.percent)], [
      (BudgetKind.hours, 'Chantier', 110),
      (BudgetKind.estimate, 'Montage', 87), // 3 h 30 sur 4 h, sous-tâche comprise
      (BudgetKind.amount, 'Chantier', 85),
    ]);
    expect(alerts[1].projectName, 'Chantier');
  });
}
