import 'package:clockifai/core/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Identité des maquettes (plans/14-coller-aux-maquettes.md, lot 2) : jetons et densité.
void main() {
  test('couleurs d’état réglées pour le clair et le sombre', () {
    expect(buildTheme(Brightness.light).extension<AppColors>(), AppColors.light);
    expect(buildTheme(Brightness.dark).extension<AppColors>(), AppColors.dark);
    expect(AppColors.light.lerp(AppColors.dark, 1).success, AppColors.dark.success);
  });

  test('menu serré à la souris, aéré au doigt', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(buildTheme(Brightness.light).navigationDrawerTheme.tileHeight, 40);
    expect(buildTheme(Brightness.light).visualDensity, VisualDensity.compact);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(buildTheme(Brightness.light).navigationDrawerTheme.tileHeight, isNull);
  });

  test('encre pour les actions, fond gris froid, Geist', () {
    final light = buildTheme(Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF0F1217));
    expect(light.scaffoldBackgroundColor, AppColors.light.ground);
    expect(light.textTheme.bodyMedium?.fontFamily, 'Geist');
    final dark = buildTheme(Brightness.dark);
    expect(dark.colorScheme.onPrimary, const Color(0xFF0F1217));
    expect(dark.scaffoldBackgroundColor, AppColors.dark.ground);
  });
}
