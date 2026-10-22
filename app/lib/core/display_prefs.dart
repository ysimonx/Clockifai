import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'affichage mémorisées sur l'appareil (ni en base, ni synchronisées).
class DisplayPrefs extends ChangeNotifier {
  DisplayPrefs(this._prefs);

  static const _groupSimilarKey = 'group_similar_entries';
  final SharedPreferences _prefs;

  /// Suivi du temps : entrées similaires d'une journée réunies sur une ligne dépliable (activé par défaut).
  bool get groupSimilarEntries => _prefs.getBool(_groupSimilarKey) ?? true;

  Future<void> setGroupSimilarEntries(bool value) async {
    await _prefs.setBool(_groupSimilarKey, value);
    notifyListeners();
  }
}
