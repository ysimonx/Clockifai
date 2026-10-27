import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Identité visuelle (plans/13-ux-moderne.md, lot 10) : le bleu de Clockifai, des jetons partagés (rayons, couleurs
/// d'état) et une densité qui suit l'appareil : plus serrée à la souris (Mac, navigateur sur ordinateur), aérée au
/// doigt.
const _seed = Color(0xFF0EA5E9);

/// Rayons : cartes et dialogues, champs et boutons, pastilles.
abstract final class Radii {
  static const card = 12.0;
  static const control = 8.0;
  static const dialog = 16.0;
}

/// Couleurs d'état, lisibles en clair comme en sombre : réussi (approuvé, synchronisé, payé), à surveiller.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.success, required this.successContainer, required this.warning});
  final Color success;
  final Color successContainer;
  final Color warning;

  static const light = AppColors(success: Color(0xFF15803D), successContainer: Color(0xFFDCFCE7), warning: Color(0xFFB45309));
  static const dark = AppColors(success: Color(0xFF4ADE80), successContainer: Color(0xFF14532D), warning: Color(0xFFFBBF24));

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({Color? success, Color? successContainer, Color? warning}) => AppColors(
      success: success ?? this.success, successContainer: successContainer ?? this.successContainer, warning: warning ?? this.warning);

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          success: Color.lerp(success, other.success, t)!,
          successContainer: Color.lerp(successContainer, other.successContainer, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final light = brightness == Brightness.light;
  const control = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));
  // À la souris (Mac, Windows, Linux, navigateur sur ordinateur) : lignes plus serrées, le menu tient sans défiler.
  final compact = VisualDensity.defaultDensityForPlatform(defaultTargetPlatform) == VisualDensity.compact;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [light ? AppColors.light : AppColors.dark],
    visualDensity: VisualDensity.adaptivePlatformDensity,
    // Fond légèrement teinté, cartes au premier plan : la page se lit par blocs.
    scaffoldBackgroundColor: light ? scheme.surfaceContainerLow : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? scheme.surfaceContainerLow : scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control))),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? scheme.surfaceContainerLowest : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.dialog))),
    ),
    filledButtonTheme: const FilledButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(control))),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(control))),
    textButtonTheme: const TextButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(control))),
    segmentedButtonTheme: const SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(control))),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control))),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    navigationDrawerTheme: NavigationDrawerThemeData(tileHeight: compact ? 44 : null),
  );
}
