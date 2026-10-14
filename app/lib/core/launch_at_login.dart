import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// État du démarrage à l'ouverture de session (macOS 13+).
enum LaunchAtLoginStatus {
  /// Autre plateforme, ou macOS 12.
  unavailable,
  disabled,
  enabled,

  /// Demandé, mais à autoriser dans Réglages Système > Général > Ouverture.
  requiresApproval,
}

/// Démarrage de l'app à l'ouverture de session, dans la barre de menus et sans fenêtre (macOS).
/// L'état vit dans le système : il est relu à chaque fois (`macos/Runner/LaunchAtLogin.swift`).
class LaunchAtLogin {
  static const _channel = MethodChannel('clockifai/launch_at_login');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<LaunchAtLoginStatus> status() => _call('status');

  static Future<LaunchAtLoginStatus> setEnabled(bool enabled) => _call('set', enabled);

  static Future<void> openSystemSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  static Future<LaunchAtLoginStatus> _call(String method, [Object? arguments]) async {
    if (!supported) return LaunchAtLoginStatus.unavailable;
    try {
      final value = await _channel.invokeMethod<String>(method, arguments);
      return LaunchAtLoginStatus.values.asNameMap()[value] ?? LaunchAtLoginStatus.unavailable;
    } on MissingPluginException {
      return LaunchAtLoginStatus.unavailable;
    }
  }
}
