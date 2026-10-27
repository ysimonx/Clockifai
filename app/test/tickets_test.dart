import 'package:clockifai/core/catalog.dart';
import 'package:clockifai/core/tickets.dart';
import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/data/repositories/catalog_repository.dart';
import 'package:clockifai/data/repositories/team_repository.dart';
import 'package:clockifai/data/repositories/workspace_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'time_entry_repository_test.dart' show TestDb;

/// Tickets des clients (plans/19-tickets-clients.md, lot 1).
void main() {
  group('parseTicket', () {
    String? key(String input) => parseTicket(input)?.key;

    test('Jira, Linear, GitHub et clé seule', () {
      expect(key('https://acme.atlassian.net/browse/ENG-123'), 'ENG-123');
      expect(key('https://jira.acme.fr/browse/abc_1-7?focusedId=3'), 'ABC_1-7');
      expect(key('https://acme.atlassian.net/jira/software/projects/ENG/boards/1?selectedIssue=ENG-42'), 'ENG-42');
      expect(key('https://linear.app/acme/issue/ENG-123/formulaire-de-commande'), 'ENG-123');
      expect(key('https://github.com/acme/site/issues/45'), 'site#45');
      expect(key('https://github.com/acme/site/pull/46'), 'site#46');
      expect(key('  eng-123 '), 'ENG-123');
      expect(parseTicket('ENG-123')!.url, isNull);
    });

    test('autre URL : pas de clé, l\'URL désigne le ticket', () {
      final t = parseTicket(' https://trello.com/c/AbCd/12-formulaire ')!;
      expect(t.key, isNull);
      expect(t.url, 'https://trello.com/c/AbCd/12-formulaire');
      expect(t.label, t.url);
      expect(key('https://github.com/acme/site'), isNull);
    });

    test('ni URL http(s) ni clé : rien', () {
      for (final input in ['', 'Formulaire de commande', 'ftp://acme.fr/ENG-1', 'ENG-', '123-ENG', 'https://${'a' * 500}.fr']) {
        expect(parseTicket(input), isNull, reason: input);
      }
    });
  });

  test('nom de la tâche et ticket retrouvé par la clé ou l\'URL', () {
    const linear = TicketRef(key: 'ENG-123', url: 'https://linear.app/acme/issue/ENG-123/x');
    expect(ticketTaskName(linear, ' Formulaire de commande '), 'ENG-123 · Formulaire de commande');
    expect(ticketTaskName(linear, ''), 'ENG-123');
    expect(ticketTaskName(const TicketRef(url: 'https://trello.com/c/x'), null), 'https://trello.com/c/x');
    expect(isTicket(linear, key: 'eng-123', url: 'https://acme.atlassian.net/browse/ENG-123'), isTrue);
    expect(isTicket(linear, key: null, url: linear.url), isFalse, reason: 'la clé prime sur l\'URL');
    expect(isTicket(const TicketRef(url: 'https://trello.com/c/x'), url: 'https://trello.com/c/x'), isTrue);
  });

  test('tâche d\'un ticket : enregistrée, retrouvée dans son projet, retirée', () async {
    const ws = 'ws-1';
    final db = TestDb();
    final repo = CatalogRepository(db);
    final site = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Site Acme'));
    final appli = await repo.createProject(ws, ProjectsCompanion.insert(workspaceId: ws, name: 'Appli Acme'));
    final ticket = parseTicket('https://linear.app/acme/issue/ENG-123/formulaire')!;
    final id = await repo.createTask(ws, site, ticketTaskName(ticket, 'Formulaire'), ticket: ticket);
    await repo.createTask(ws, site, 'Sous-tâche', parentId: id);
    final catalog = CatalogController(repo, WorkspaceRepository(db), TeamRepository(db))..bind(ws);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final task = catalog.ticketTask(parseTicket('eng-123')!)!;
    expect((task.id, task.name, task.ticketKey, task.ticketUrl), (id, 'ENG-123 · Formulaire', 'ENG-123', ticket.url));
    expect(catalog.ticketTask(ticket, projectId: site)?.id, id);
    expect(catalog.ticketTask(ticket, projectId: appli), isNull);

    await repo.updateTask(id, ticket: const Value(null));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(catalog.ticketTask(ticket), isNull);
    expect(catalog.task(id)!.name, 'ENG-123 · Formulaire', reason: 'le nom reste');

    catalog.dispose();
    await db.close();
  });
}
