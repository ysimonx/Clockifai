import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/modules_repository.dart';
import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/features/time_off/time_off_page.dart' show workingDays;
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
  late ModulesRepository modules;
  late TimeEntryRepository entries;
  late CatalogRepository catalog;

  setUp(() {
    db = TestDb();
    modules = ModulesRepository(db);
    entries = TimeEntryRepository(db);
    catalog = CatalogRepository(db);
  });
  tearDown(() => db.close());

  test('jours ouvrés : week-ends et jours fériés exclus', () {
    // Du lundi 9 au dimanche 15 novembre 2026, avec le 11 novembre férié.
    expect(workingDays(DateTime(2026, 11, 9), DateTime(2026, 11, 15), {'2026-11-11'}), 4);
    expect(workingDays(DateTime(2026, 11, 14), DateTime(2026, 11, 14), {}), 0);
  });

  test('soumission : une seule ligne par période, re-soumission après retrait', () async {
    final start = DateTime(2026, 10, 5), end = DateTime(2026, 10, 11);
    await modules.submitPeriod(workspaceId: ws, userId: me, start: start, end: end, totalSeconds: 3600);
    var subs = await modules.watchSubmissions(ws, userId: me).first;
    expect(subs.single.status, 'submitted');
    await modules.withdrawSubmission(subs.single.id);
    await modules.submitPeriod(workspaceId: ws, userId: me, start: start, end: end, totalSeconds: 7200);
    subs = await modules.watchSubmissions(ws, userId: me).first;
    expect(subs, hasLength(1));
    expect(subs.single.status, 'submitted');
    expect(subs.single.totalSeconds, 7200);
  });

  test('facture depuis le temps : une ligne par projet et taux, entrées non refacturées', () async {
    final client = await catalog.createClient(ws, name: 'ACME');
    final p1 = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Montage', clientId: Value(client)));
    final p2 = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Démontage', clientId: Value(client)));
    final other = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Autre client'));
    Future<void> add(String project, int hour, int minutes, {int rate = 5000, bool billable = true}) => entries.createManual(
          workspaceId: ws,
          userId: me,
          draft: EntryDraft(projectId: project, hourlyRateCents: rate, billable: billable),
          start: DateTime.utc(2026, 9, 10, hour),
          end: DateTime.utc(2026, 9, 10, hour).add(Duration(minutes: minutes)),
        );
    await add(p1, 8, 90);
    await add(p1, 10, 30);
    await add(p2, 13, 60, rate: 6000);
    await add(p2, 15, 60, billable: false); // non facturable : ignoré
    await add(other, 16, 60); // autre client : ignoré

    final names = {p1: 'Montage', p2: 'Démontage'};
    final id = await modules.createInvoiceFromTime(
      workspaceId: ws, userId: me, clientId: client,
      from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 10, 1),
      currency: 'EUR', taxPercent: 20, projectNames: names,
    );
    expect(id, isNotNull);
    final items = await modules.watchItems(id!).first;
    expect(items.map((i) => (i.description, i.quantity, i.unitPriceCents)), [
      ('Démontage', 1.0, 6000),
      ('Montage', 2.0, 5000),
    ]);
    expect((await modules.invoicedEntryIds(ws)).length, 3);

    // Rien de plus à facturer sur la période.
    final again = await modules.createInvoiceFromTime(
      workspaceId: ws, userId: me, clientId: client,
      from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 10, 1),
      currency: 'EUR', taxPercent: 20, projectNames: names,
    );
    expect(again, isNull);

    // Supprimer la facture libère les entrées.
    await modules.deleteInvoice(id);
    expect(await modules.invoicedEntryIds(ws), isEmpty);
  });

  test('facture : taux actuel pour une entrée sans taux, détail par tâche', () async {
    final client = await catalog.createClient(ws, name: 'ACME');
    final p = await catalog.createProject(ws,
        ProjectsCompanion.insert(workspaceId: ws, name: 'cvad', clientId: Value(client), hourlyRateCents: const Value(14285)));
    final free = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Conseil', clientId: Value(client)));
    await db.into(db.workspaceMembers).insert(
        WorkspaceMembersCompanion.insert(workspaceId: ws, userId: me, hourlyRateCents: const Value(9000)));
    final export = await catalog.createTask(ws, p, 'Export PDF');
    final audit = await catalog.createTask(ws, p, 'Audit');
    Future<void> add(String project, int hour, {String? task, int? rate}) => entries.createManual(
          workspaceId: ws,
          userId: me,
          draft: EntryDraft(projectId: project, taskId: task, hourlyRateCents: rate),
          start: DateTime.utc(2026, 10, 23, hour),
          end: DateTime.utc(2026, 10, 23, hour, 30),
        );
    await add(p, 8); // saisie avant que le projet ait un taux
    await add(p, 9, rate: 14285);
    await add(p, 10, task: export, rate: 14285);
    await add(p, 11, task: audit);
    await add(p, 12, task: 'tache-supprimee', rate: 14285);
    await add(free, 13); // projet sans taux : celui du membre

    Future<List<(String, double, int)>> invoice({required bool byTask}) async {
      final id = await modules.createInvoiceFromTime(
        workspaceId: ws, userId: me, clientId: client,
        from: DateTime.utc(2026, 10, 1), to: DateTime.utc(2026, 11, 1),
        currency: 'EUR', taxPercent: 20, projectNames: {p: 'cvad', free: 'Conseil'},
        byTask: byTask, taskNames: {export: 'Export PDF', audit: 'Audit'},
      );
      final items = await modules.watchItems(id!).first;
      await modules.deleteInvoice(id);
      return [for (final i in items) (i.description, i.quantity, i.unitPriceCents)];
    }

    expect(await invoice(byTask: false), [('Conseil', 0.5, 9000), ('cvad', 2.5, 14285)]);
    expect(await invoice(byTask: true), [
      ('Conseil', 0.5, 9000),
      ('cvad', 1.5, 14285), // sans tâche, et tâche supprimée
      ('cvad — Audit', 0.5, 14285),
      ('cvad — Export PDF', 0.5, 14285),
    ]);
  });

  test('nouveau taux : seules les entrées non facturées et modifiables le prennent', () async {
    final client = await catalog.createClient(ws, name: 'ACME');
    final p = await catalog.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'cvad', clientId: Value(client)));
    Future<String> add(int day) => entries.createManual(
          workspaceId: ws,
          userId: me,
          draft: EntryDraft(projectId: p, hourlyRateCents: 10000),
          start: DateTime.utc(2026, 10, day, 9),
          end: DateTime.utc(2026, 10, day, 10),
        );
    final open = await add(20);
    final locked = await add(21);
    await (db.update(db.timeEntries)..where((t) => t.id.equals(locked))).write(const TimeEntriesCompanion(locked: Value(true)));
    final early = await add(2);
    final approvedDay = await add(14);
    await db.into(db.timesheetSubmissions).insert(TimesheetSubmissionsCompanion.insert(
        workspaceId: ws, userId: me, periodStart: '2026-10-12', periodEnd: '2026-10-18', status: const Value('approved')));
    final billed = await add(9);
    final invoiceId = await modules.createInvoiceFromTime(
      workspaceId: ws, userId: me, clientId: client,
      from: DateTime.utc(2026, 10, 9), to: DateTime.utc(2026, 10, 10),
      currency: 'EUR', taxPercent: 20, projectNames: {p: 'cvad'},
    );
    expect(invoiceId, isNotNull);

    Future<Set<String>> ids({required bool isAdmin}) async => {
          for (final e in await modules.rerateableEntries(ws,
              projectId: p, isAdmin: isAdmin, lockBefore: DateTime(2026, 10, 5)))
            e.id
        };
    expect(await ids(isAdmin: false), {open});
    // Un admin passe outre le verrouillage et les approbations, pas la facture.
    expect(await ids(isAdmin: true), {open, locked, early, approvedDay});

    await modules.setEntryRates({open: 14285});
    final rates = {
      for (final e in await (db.select(db.timeEntries)..where((t) => t.projectId.equals(p))).get()) e.id: e.hourlyRateCents
    };
    expect(rates[open], 14285);
    expect(rates[billed], 10000);
  });

  test('planning : chevauchement de période', () async {
    await modules.saveAssignment(ws, ScheduleAssignmentsCompanion.insert(
      workspaceId: ws, userId: me, startDate: '2026-10-08', endDate: '2026-10-14',
    ));
    final week = await modules.watchAssignments(ws, from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 18)).first;
    expect(week, hasLength(1));
    final before = await modules.watchAssignments(ws, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 7)).first;
    expect(before, isEmpty);
  });
}
