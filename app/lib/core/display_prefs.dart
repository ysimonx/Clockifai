import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'affichage mémorisées sur l'appareil (ni en base, ni synchronisées).
class DisplayPrefs extends ChangeNotifier {
  DisplayPrefs(this._prefs);

  static const _groupSimilarKey = 'group_similar_entries';
  static const _dismissedKey = 'journal_dismissed';
  static const _themeKey = 'theme_mode';
  static const _recapKey = 'day_recap';
  static const _recapTimeKey = 'day_recap_time';
  static const _recapShownKey = 'day_recap_shown';
  final SharedPreferences _prefs;

  /// Suivi du temps : entrées similaires d'une journée réunies sur une ligne dépliable (activé par défaut).
  bool get groupSimilarEntries => _prefs.getBool(_groupSimilarKey) ?? true;

  Future<void> setGroupSimilarEntries(bool value) async {
    await _prefs.setBool(_groupSimilarKey, value);
    notifyListeners();
  }

  /// Apparence : celle du système (par défaut), ou claire ou sombre quoi qu'en dise le système.
  ThemeMode get themeMode => switch (_prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// Récapitulatif de fin de journée (plans/13-ux-moderne.md, lot 6) : activé par défaut, sur chaque appareil.
  bool get dayRecap => _prefs.getBool(_recapKey) ?? true;

  /// Heure du récapitulatif, « 17:30 » par défaut.
  String get dayRecapTime => _prefs.getString(_recapTimeKey) ?? '17:30';

  /// Dernier jour (« 2026-10-27 ») où le récapitulatif a été présenté : une fois par jour.
  String? get dayRecapShown => _prefs.getString(_recapShownKey);

  Future<void> setDayRecap(bool enabled, {String? time}) async {
    await _prefs.setBool(_recapKey, enabled);
    if (time != null) await _prefs.setString(_recapTimeKey, time);
    notifyListeners();
  }

  Future<void> markDayRecapShown(String day) => _prefs.setString(_recapShownKey, day);

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      await _prefs.remove(_themeKey);
    } else {
      await _prefs.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    }
    notifyListeners();
  }

  /// Journal automatique : propositions ignorées sur cet appareil (clés stables, les 300 dernières).
  Set<String> get dismissedSuggestions => (_prefs.getStringList(_dismissedKey) ?? const <String>[]).toSet();

  Future<void> dismissSuggestion(String key) async {
    final list = [...?_prefs.getStringList(_dismissedKey)]..remove(key)..add(key);
    await _prefs.setStringList(_dismissedKey, list.length > 300 ? list.sublist(list.length - 300) : list);
    notifyListeners();
  }

  Future<void> restoreSuggestion(String key) async {
    await _prefs.setStringList(_dismissedKey, [...?_prefs.getStringList(_dismissedKey)]..remove(key));
    notifyListeners();
  }
}
