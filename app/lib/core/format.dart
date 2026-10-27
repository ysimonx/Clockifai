import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 1:05:09 (ou 0:05:09) — affichage chronomètre.
String formatClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// 7:30 — heures:minutes (totaux).
String formatHm(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// 7,50 — heures décimales selon la locale.
String formatDecimalHours(int seconds, String locale) =>
    NumberFormat('0.00', locale).format(seconds / 3600);

String formatMoney(num amount, String currency, String locale) =>
    NumberFormat.simpleCurrency(locale: locale, name: currency).format(amount);

/// Nombre saisi avec une virgule ou un point (« 7,5 »), ou null.
double? parseDecimal(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// Montant saisi en unités (« 85,50 ») converti en centimes, ou null.
int? textToCents(String text) => switch (parseDecimal(text)) { final v? => (v * 100).round(), null => null };

/// Centimes en texte à modifier (« 85.50 ») ; vide sans montant.
String centsToText(int? cents) => cents == null ? '' : (cents / 100).toStringAsFixed(2);

/// Quantité sans décimale inutile : « 7 », « 7.5 » (une décimale au plus).
String formatQuantity(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Interprète une durée saisie : "1.5", "1,5", "1:30", "90m", "2h", "1h30".
int? parseDuration(String input) {
  final s = input.trim().toLowerCase().replaceAll(' ', '');
  if (s.isEmpty) return 0;
  final hm = RegExp(r'^(\d+):(\d{1,2})$').firstMatch(s);
  if (hm != null) return int.parse(hm[1]!) * 3600 + int.parse(hm[2]!) * 60;
  final hMin = RegExp(r'^(\d+)h(\d{1,2})?m?$').firstMatch(s);
  if (hMin != null) return int.parse(hMin[1]!) * 3600 + (hMin[2] == null ? 0 : int.parse(hMin[2]!) * 60);
  final mins = RegExp(r'^(\d+)m(in)?$').firstMatch(s);
  if (mins != null) return int.parse(mins[1]!) * 60;
  final dec = double.tryParse(s.replaceAll(',', '.'));
  if (dec != null && dec >= 0) return (dec * 3600).round();
  return null;
}

/// Début de semaine (minuit local) ; [weekStart] ISO : 1 = lundi … 7 = dimanche.
DateTime startOfWeek(DateTime date, int weekStart) => addDays(date, -((date.weekday - weekStart) % 7));

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Le jour [days] jours après [d], à minuit : pas 24 h plus tard, un jour de changement d'heure en compte 23 ou 25.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Jour sans heure en texte `yyyy-MM-dd`, comme les colonnes `date` de la base (`period_start`, `start_date`…).
String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) => DateTime.parse(s);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// « Aujourd'hui », « Hier », sinon le jour en toutes lettres ; [now] : l'horloge de la page (par défaut l'heure réelle).
String dayLabel(BuildContext context, DateTime day, {required String today, required String yesterday, DateTime? now}) {
  final at = now ?? DateTime.now();
  if (sameDay(day, at)) return today;
  if (sameDay(day, DateTime(at.year, at.month, at.day - 1))) return yesterday;
  final locale = Localizations.localeOf(context).toLanguageTag();
  return toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', locale).format(day));
}

String timeLabel(BuildContext context, DateTime t) =>
    DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(t.toLocal());

Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return Color(v ?? 0xFF3B82F6);
}

const projectPalette = [
  '#3B82F6', '#0EA5E9', '#06B6D4', '#10B981', '#22C55E', '#84CC16', '#EAB308',
  '#F59E0B', '#F97316', '#EF4444', '#EC4899', '#D946EF', '#8B5CF6', '#6366F1',
  '#64748B', '#78716C',
];
