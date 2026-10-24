import 'package:clockifai/features/time_entries/entry_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('changedTime : n\'écrire que les heures modifiées', () {
    // Entrée d'agent : heures à la seconde, posées par le serveur.
    final start = DateTime.utc(2026, 10, 23, 21, 9, 39, 424);
    final end = DateTime.utc(2026, 10, 23, 21, 9, 58);

    test('heure inchangée à la minute près : rien à écrire, les secondes restent', () {
      final shown = start.toLocal();
      expect(changedTime(start, DateTime(shown.year, shown.month, shown.day, shown.hour, shown.minute)), isNull);
      final shownEnd = end.toLocal();
      expect(changedTime(end, DateTime(shownEnd.year, shownEnd.month, shownEnd.day, shownEnd.hour, shownEnd.minute)), isNull);
    });

    test('heure changée : la nouvelle valeur est écrite', () {
      final edited = end.toLocal().add(const Duration(minutes: 5));
      expect(changedTime(end, edited), edited);
      final otherDay = start.toLocal().add(const Duration(days: 1));
      expect(changedTime(start, otherDay), otherDay);
    });

    test('pas d\'heure d\'origine (chronomètre arrêté depuis le dialogue) ou pas de saisie', () {
      final edited = DateTime(2026, 10, 23, 23, 30);
      expect(changedTime(null, edited), edited);
      expect(changedTime(end, null), isNull);
    });
  });
}
