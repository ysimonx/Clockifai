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
