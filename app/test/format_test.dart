import 'package:clockifai/core/format.dart';
import 'package:clockifai/features/time_entries/ai_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDuration', () {
    test('formats acceptés', () {
      expect(parseDuration('1:30'), 5400);
      expect(parseDuration('1,5'), 5400);
      expect(parseDuration('1.5'), 5400);
      expect(parseDuration('90m'), 5400);
      expect(parseDuration('90min'), 5400);
      expect(parseDuration('2h'), 7200);
      expect(parseDuration('1h30'), 5400);
      expect(parseDuration(' 0:05 '), 300);
      expect(parseDuration(''), 0);
    });

    test('saisie invalide', () {
      expect(parseDuration('abc'), isNull);
      expect(parseDuration('1:3a'), isNull);
      expect(parseDuration('-2'), isNull);
    });
  });

  test('formatClock / formatHm', () {
    expect(formatClock(0), '0:00:00');
    expect(formatClock(3725), '1:02:05');
    expect(formatClock(-5), '0:00:00');
    expect(formatHm(27000), '7:30');
  });

  group('startOfWeek', () {
    // Samedi 11 octobre 2026
    final saturday = DateTime(2026, 10, 11, 15, 30);
    test('semaine ISO (lundi)', () => expect(startOfWeek(saturday, 1), DateTime(2026, 10, 5)));
    test('semaine commençant le dimanche', () => expect(startOfWeek(saturday, 7), DateTime(2026, 10, 11)));
    test('le jour même est le début de semaine', () => expect(startOfWeek(DateTime(2026, 10, 5, 8), 1), DateTime(2026, 10, 5)));
    // Le 25 octobre 2026 compte 25 heures en Europe : le début de semaine reste à minuit, pas 48 h plus tôt.
    test('changement d\'heure', () => expect(startOfWeek(DateTime(2026, 10, 27, 9), 7), DateTime(2026, 10, 25)));
  });

  test('colorFromHex', () {
    expect(colorFromHex('#FF0000').toARGB32(), 0xFFFF0000);
    expect(colorFromHex('nope').toARGB32(), 0xFF3B82F6);
  });

  test('usage IA : nom du modèle, tokens et coût en dollars (plan 10, D17)', () {
    expect(modelLabel('claude-opus-5-5'), 'Opus 5.5');
    expect(modelLabel('claude-haiku-4-5-20251001'), 'Haiku 4.5');
    expect(modelLabel('claude-fable-5'), 'Fable 5');
    expect(modelLabel('<synthetic>'), '<synthetic>');
    expect(formatTokens(1234567, 'en'), '1.23M');
    expect(formatAiCost(4560000, 'en'), r'$4.56');
  });
}
