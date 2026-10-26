import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'affichage mémorisées sur l'appareil (ni en base, ni synchronisées).
class DisplayPrefs extends ChangeNotifier {
  DisplayPrefs(this._prefs);

  static const _groupSimilarKey = 'group_similar_entries';
  static const _dismissedKey = 'journal_dismissed';
  final SharedPreferences _prefs;

  /// Suivi du temps : entrées similaires d'une journée réunies sur une ligne dépliable (activé par défaut).
  bool get groupSimilarEntries => _prefs.getBool(_groupSimilarKey) ?? true;

  Future<void> setGroupSimilarEntries(bool value) async {
    await _prefs.setBool(_groupSimilarKey, value);
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
