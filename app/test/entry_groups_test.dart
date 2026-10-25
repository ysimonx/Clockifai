import 'package:clockifai/data/repositories/time_entry_repository.dart';
import 'package:clockifai/features/time_entries/entry_groups.dart';
import 'package:flutter_test/flutter_test.dart';

import 'time_entry_repository_test.dart' show TestDb;

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

  Future<String> add(int hour, int minutes,
      {String description = 'Revue', String? projectId = 'p1', String? taskId = 't1', List<String> tags = const ['a', 'b'], bool billable = true, String userId = me}) {
    final start = DateTime.utc(2026, 10, 22, hour);
    return repo.createManual(
      workspaceId: ws,
      userId: userId,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      draft: EntryDraft(description: description, projectId: projectId, taskId: taskId, billable: billable, tagIds: tags),
    );
  }

  Future<List<EntryRow>> rows() =>
      repo.watchEntries(workspaceId: ws, userId: me, from: DateTime.utc(2026, 10, 22), to: DateTime.utc(2026, 10, 23)).first;

  test('mêmes description, projet, tâche, tags et facturable : un seul groupe, tags dans n\'importe quel ordre', () async {
    await add(8, 30);
    await add(10, 15, tags: ['b', 'a']);
    final groups = groupSimilar(await rows());
    expect(groups, hasLength(1));
    expect(groups.single.rows, hasLength(2));
  });

  test('un seul critère différent suffit à séparer', () async {
    await add(8, 10);
    await add(9, 10, description: 'Autre');
    await add(10, 10, projectId: 'p2');
    await add(11, 10, taskId: 't2');
    await add(12, 10, tags: ['a']);
    await add(13, 10, billable: false);
    await add(14, 10, projectId: null, taskId: null);
    expect(groupSimilar(await rows()), hasLength(7));
  });

  test('rapport détaillé : la même activité de deux personnes fait deux groupes', () async {
    await add(8, 30);
    await add(9, 30);
    await add(10, 30, userId: 'user-2');
    final all = await repo.watchEntries(workspaceId: ws, from: DateTime.utc(2026, 10, 22), to: DateTime.utc(2026, 10, 23)).first;
    expect([for (final g in groupSimilar(all)) (g.first.entry.userId, g.rows.length)], [('user-2', 1), (me, 2)]);
  });

  test('ordre : le groupe prend la place de son entrée la plus récente ; totaux et plage', () async {
    final a1 = await add(8, 30);
    await add(9, 20, description: 'Autre');
    final a2 = await add(11, 45);
    final groups = groupSimilar(await rows());
    expect(groups.map((g) => g.first.entry.description), ['Revue', 'Autre']);
    final revue = groups.first;
    expect(revue.rows.map((r) => r.entry.id), [a2, a1]);
    expect(revue.seconds, (30 + 45) * 60);
    expect(revue.startAt, DateTime.utc(2026, 10, 22, 8));
    expect(revue.endAt, DateTime.utc(2026, 10, 22, 11, 45));
    expect(revue.isSingle, isFalse);
    expect(groups.last.isSingle, isTrue);
  });

  test('updateMany : mêmes champs pour toutes les entrées, horaires inchangés, taux du nouveau projet', () async {
    await add(8, 30);
    await add(10, 15);
    final before = await rows();
    await repo.updateMany(
      [for (final r in before) r.entry],
      description: 'Revue de code',
      projectId: 'p2',
      taskId: null,
      billable: false,
      tagIds: ['c'],
      hourlyRateFor: (_) => 9000,
    );
    final after = await rows();
    for (final r in after) {
      expect(r.entry.description, 'Revue de code');
      expect(r.entry.projectId, 'p2');
      expect(r.entry.taskId, isNull);
      expect(r.entry.billable, isFalse);
      expect(r.entry.hourlyRateCents, 9000);
      expect(r.tagIds, ['c']);
    }
    expect([for (final r in after) r.seconds], [for (final r in before) r.seconds]);
    expect(groupSimilar(after), hasLength(1));
  });

  test('updateMany sans changement de projet : taux inchangé', () async {
    await add(8, 30);
    final before = await rows();
    final rate = before.single.entry.hourlyRateCents;
    await repo.updateMany([before.single.entry],
        description: 'Revue', projectId: 'p1', taskId: 't1', billable: true, tagIds: ['a', 'b'], hourlyRateFor: (_) => 9000);
    expect((await rows()).single.entry.hourlyRateCents, rate);
  });

  test('deleteMany : suppression logique de toutes les entrées du groupe', () async {
    await add(8, 30);
    await add(10, 15);
    final keep = await add(12, 5, description: 'Autre');
    final group = groupSimilar(await rows()).firstWhere((g) => !g.isSingle);
    await repo.deleteMany([for (final r in group.rows) r.entry.id]);
    expect((await rows()).map((r) => r.entry.id), [keep]);
  });
}
