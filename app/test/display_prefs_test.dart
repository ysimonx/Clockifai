import 'package:clockifai/core/display_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('apparence : celle du système par défaut, claire ou sombre si on la force', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = DisplayPrefs(await SharedPreferences.getInstance());
    var notified = 0;
    prefs.addListener(() => notified++);
    expect(prefs.themeMode, ThemeMode.system);
    await prefs.setThemeMode(ThemeMode.dark);
    expect(prefs.themeMode, ThemeMode.dark);
    expect(DisplayPrefs(await SharedPreferences.getInstance()).themeMode, ThemeMode.dark, reason: 'mémorisé sur l’appareil');
    await prefs.setThemeMode(ThemeMode.light);
    expect(prefs.themeMode, ThemeMode.light);
    await prefs.setThemeMode(ThemeMode.system);
    expect(prefs.themeMode, ThemeMode.system);
    expect(notified, 3);
  });
}
