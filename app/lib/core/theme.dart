import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Identité des maquettes (plans/14-coller-aux-maquettes.md, lot 2) : encre presque noire pour les actions, fond
/// gris froid, cartes blanches bordées, Geist pour le texte et Geist Mono pour les heures et les durées. La densité
/// suit l'appareil : plus serrée à la souris (Mac, navigateur sur ordinateur), aérée au doigt.

/// Police des heures, durées et raccourcis (chiffres de même largeur).
const monoFont = 'GeistMono';

/// Rayons : cartes, champs et boutons, dialogues et feuilles.
abstract final class Radii {
  static const card = 16.0;
  static const control = 10.0;
  static const button = 12.0;
  static const dialog = 20.0;
}

/// Couleurs propres à Clockifai, lisibles en clair comme en sombre : réussi (approuvé, synchronisé, payé), à
/// surveiller, et les fonds (page, menu latéral).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.ground,
    required this.sidebar,
    required this.link,
  });
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  /// Fond de page, sous les cartes.
  final Color ground;
  /// Menu latéral.
  final Color sidebar;
  /// Liens et focus.
  final Color link;

  static const light = AppColors(
    success: Color(0xFF157347),
    successContainer: Color(0xFFDDF3E8),
    warning: Color(0xFF8A4B00),
    warningContainer: Color(0xFFFFF2D6),
    ground: Color(0xFFF4F5F7),
    sidebar: Color(0xFFFBFBFC),
    link: Color(0xFF2747B8),
  );
  static const dark = AppColors(
    success: Color(0xFF4ADE80),
    successContainer: Color(0xFF123524),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF3A2A0C),
    ground: Color(0xFF0E1116),
    sidebar: Color(0xFF12151B),
    link: Color(0xFF8FA8FF),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? ground,
    Color? sidebar,
    Color? link,
  }) =>
      AppColors(
        success: success ?? this.success,
        successContainer: successContainer ?? this.successContainer,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
        ground: ground ?? this.ground,
        sidebar: sidebar ?? this.sidebar,
        link: link ?? this.link,
      );

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          success: Color.lerp(success, other.success, t)!,
          successContainer: Color.lerp(successContainer, other.successContainer, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
          ground: Color.lerp(ground, other.ground, t)!,
          sidebar: Color.lerp(sidebar, other.sidebar, t)!,
          link: Color.lerp(link, other.link, t)!,
        );
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0F1217),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE7EAF0),
  onPrimaryContainer: Color(0xFF0F1217),
  secondary: Color(0xFF3D4450),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE7EAF0),
  onSecondaryContainer: Color(0xFF0F1217),
  tertiary: Color(0xFF2747B8),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFEEF1FC),
  onTertiaryContainer: Color(0xFF1F3A9A),
  error: Color(0xFFB42318),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFDECEA),
  onErrorContainer: Color(0xFF7A1A12),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF0F1217),
  onSurfaceVariant: Color(0xFF3D4450),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFBFBFC),
  surfaceContainer: Color(0xFFF4F5F7),
  surfaceContainerHigh: Color(0xFFF1F3F6),
  surfaceContainerHighest: Color(0xFFEEF0F3),
  outline: Color(0xFF5F6775),
  outlineVariant: Color(0xFFE2E5EA),
  inverseSurface: Color(0xFF0F1217),
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Color(0xFFC9D3F5),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Colors.transparent,
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF2F4F7),
  onPrimary: Color(0xFF0F1217),
  primaryContainer: Color(0xFF262C36),
  onPrimaryContainer: Color(0xFFF2F4F7),
  secondary: Color(0xFFB4BCC8),
  onSecondary: Color(0xFF0F1217),
  secondaryContainer: Color(0xFF262C36),
  onSecondaryContainer: Color(0xFFF2F4F7),
  tertiary: Color(0xFF8FA8FF),
  onTertiary: Color(0xFF0F1217),
  tertiaryContainer: Color(0xFF1F2A4D),
  onTertiaryContainer: Color(0xFFC9D3FF),
  error: Color(0xFFF97066),
  onError: Color(0xFF0F1217),
  errorContainer: Color(0xFF3A1512),
  onErrorContainer: Color(0xFFFFD5D0),
  surface: Color(0xFF161A21),
  onSurface: Color(0xFFF2F4F7),
  onSurfaceVariant: Color(0xFFB4BCC8),
  surfaceContainerLowest: Color(0xFF161A21),
  surfaceContainerLow: Color(0xFF12151B),
  surfaceContainer: Color(0xFF0E1116),
  surfaceContainerHigh: Color(0xFF1D222B),
  surfaceContainerHighest: Color(0xFF232933),
  outline: Color(0xFF8A93A1),
  outlineVariant: Color(0xFF262C36),
  inverseSurface: Color(0xFFF2F4F7),
  onInverseSurface: Color(0xFF0F1217),
  inversePrimary: Color(0xFF2747B8),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Colors.transparent,
);

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = light ? _lightScheme : _darkScheme;
  final colors = light ? AppColors.light : AppColors.dark;
  final strongBorder = light ? const Color(0xFFD5DAE1) : const Color(0xFF343B47);
  const control = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));
  const button = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.button)));
  // À la souris (Mac, Windows, Linux, navigateur sur ordinateur) : lignes plus serrées, le menu tient sans défiler.
  final compact = VisualDensity.defaultDensityForPlatform(defaultTargetPlatform) == VisualDensity.compact;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Geist');
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.6),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
  );
  return base.copyWith(
    textTheme: text,
    extensions: [colors],
    visualDensity: VisualDensity.adaptivePlatformDensity,
    // Fond gris froid, cartes blanches au premier plan : la page se lit par blocs.
    scaffoldBackgroundColor: colors.ground,
    canvasColor: colors.ground,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ground,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(Radii.control)), borderSide: BorderSide(color: strongBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(Radii.control)), borderSide: BorderSide(color: strongBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(Radii.control)), borderSide: BorderSide(color: colors.link, width: 2)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.dialog))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalBackgroundColor: scheme.surface,
      dragHandleColor: strongBorder,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button), side: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: button, textStyle: text.labelLarge, padding: const EdgeInsets.symmetric(horizontal: 18)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: button,
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surface,
        side: BorderSide(color: strongBorder),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: control, foregroundColor: scheme.onSurface)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: control,
        side: BorderSide(color: strongBorder),
        backgroundColor: scheme.surface,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onSurface,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: strongBorder)),
      side: BorderSide(color: strongBorder),
      backgroundColor: scheme.surface,
      labelStyle: text.bodyMedium,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.button))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.primaryContainer,
      shape: control,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0)),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(tileHeight: compact ? 40 : null, backgroundColor: colors.sidebar),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.surfaceContainerHighest),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
  );
}
