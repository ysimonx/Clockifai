import 'package:clockifai/features/today/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saisie express (plans/13-ux-moderne.md, lot 3).
const projects = [
  QuickProject('boul', 'Site de la boulangerie', client: 'Boulangerie Martin'),
  QuickProject('rdv', 'Appli de rendez-vous', client: 'Cabinet Dupuis'),
  QuickProject('int', 'Interne'),
];
const tasks = [
  QuickTask('maq', 'Maquettes', 'boul'),
  QuickTask('rec', 'Recette', 'rdv'),
  QuickTask('reu', 'Réunion client', 'rdv'),
  QuickTask('hebdo', 'Point hebdo', 'int'),
  QuickTask('sms', 'Rappels par SMS', 'rdv'),
];
const tags = [QuickTag('urg', 'Urgent')];

QuickEntry q(String text, {int weekday = DateTime.monday}) =>
    parseQuickEntry(text, weekday: weekday, projects: projects, tasks: tasks, tags: tags)!;

void main() {
  test('durée, projet, tâche et description', () {
    final e = q('1h20 point hebdo interne');
    expect((e.minutes, e.projectId, e.taskId, e.description, e.dayOffset), (80, 'int', 'hebdo', 'Point hebdo', 0));
    expect(e.isComplete, isTrue);
    expect(q('2h maquettes boulangerie').description, 'Maquettes', reason: 'le nom du projet sort de la description');
    expect(q('45min appel dupuis').projectId, 'rdv', reason: 'par le client');
    expect(q('45min appel dupuis').taskId, isNull, reason: 'début de mot seulement : « appel » n’est pas « Rappels »');
    expect(q('45min rappels dupuis').taskId, 'sms');
    expect(q('45 min appel dupuis').minutes, 45);
    expect(q('1,5h relecture').minutes, 90);
    expect(q('1:30 relecture').minutes, 90);
    expect(q('90m relecture').minutes, 90);
  });

  test('plage horaire et jour', () {
    final e = q('9h-10h30 maquettes boulangerie hier');
    expect((e.startMinute, e.endMinute, e.duration, e.dayOffset, e.taskId), (540, 630, 90, -1, 'maq'));
    expect((q('14:00 - 15:30 recette rdv').startMinute, q('14:00 - 15:30 recette rdv').taskId), (840, 'rec'));
    expect(q('9h à 11h réunion dupuis').duration, 120);
    expect(q('3h recette vendredi', weekday: DateTime.monday).dayOffset, -3);
    expect(q('3h recette lundi', weekday: DateTime.monday).dayOffset, 0);
    expect(q('2h recette avant-hier').dayOffset, -2);
    expect(q('2h review yesterday').dayOffset, -1);
  });

  test('tags, facturation, et ce qui reste dans la description', () {
    final e = q('30min appel dupuis #urgent non facturable');
    expect(e.tagIds, ['urg']);
    expect((e.billable, e.description), (false, 'Appel'));
    expect(q('1h devis #nf').billable, isFalse);
    expect(q('1h relecture facturable').billable, isTrue);
    expect(q('1h relecture').billable, isNull);
  });

  test('sans projet reconnu : la description seule', () {
    final e = q('1h appel au fournisseur');
    expect((e.projectId, e.description, e.isComplete), (null, 'Appel au fournisseur', true));
    expect(q('appel au fournisseur').isComplete, isFalse, reason: 'pas de durée');
    expect(parseQuickEntry('   ', weekday: 1), isNull);
  });
}
