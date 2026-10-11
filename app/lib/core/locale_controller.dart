import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langue de l'interface : système (null), français ou anglais. Mémorisée sur l'appareil.
class LocaleController extends ChangeNotifier {
  LocaleController(this._prefs) : _locale = _read(_prefs);

  static const _key = 'ui_locale';
  final SharedPreferences _prefs;
  Locale? _locale;

  Locale? get locale => _locale;

  static Locale? _read(SharedPreferences p) {
    final v = p.getString(_key);
    return v == null ? null : Locale(v);
  }

  Future<void> set(Locale? locale) async {
    _locale = locale;
    if (locale == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, locale.languageCode);
    }
    notifyListeners();
  }
}
