import 'package:clockifai/core/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Identité visuelle (plans/13-ux-moderne.md, lot 10) : jetons et densité.
void main() {
  test('couleurs d’état réglées pour le clair et le sombre', () {
    expect(buildTheme(Brightness.light).extension<AppColors>(), AppColors.light);
    expect(buildTheme(Brightness.dark).extension<AppColors>(), AppColors.dark);
    expect(AppColors.light.lerp(AppColors.dark, 1).success, AppColors.dark.success);
  });

  test('menu serré à la souris, aéré au doigt', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(buildTheme(Brightness.light).navigationDrawerTheme.tileHeight, 44);
    expect(buildTheme(Brightness.light).visualDensity, VisualDensity.compact);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(buildTheme(Brightness.light).navigationDrawerTheme.tileHeight, isNull);
  });
}
