import Cocoa
import FlutterMacOS
import ServiceManagement

/// Démarrage à l'ouverture de session (SMAppService, macOS 13+). Lancée ainsi, l'app n'ouvre pas de fenêtre :
/// seule l'icône de la barre de menus apparaît (voir MainFlutterWindow). L'état est celui du système
/// (Réglages Système > Général > Ouverture) : il est relu à chaque fois, jamais mémorisé.
/// Canal `clockifai/launch_at_login` : `status`, `set` (bool), `openSettings` ; statut renvoyé :
/// `unavailable` (macOS 12), `disabled`, `enabled`, `requiresApproval` (à autoriser dans les Réglages).
enum LaunchAtLogin {
  static var isAvailable: Bool {
    if #available(macOS 13.0, *) { return true }
    return false
  }

  static var status: String {
    guard #available(macOS 13.0, *) else { return "unavailable" }
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    default: return "disabled"
    }
  }

  static func setEnabled(_ enabled: Bool) {
    guard #available(macOS 13.0, *) else { return }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      NSLog("Ouverture de session : %@", error.localizedDescription)
    }
  }

  static func openSystemSettings() {
    guard #available(macOS 13.0, *) else { return }
    SMAppService.openSystemSettingsLoginItems()
  }

  /// Vrai si le système a lancé l'app à l'ouverture de session. Lisible seulement pendant la fin du lancement
  /// (NSApplication.didFinishLaunchingNotification), tant que l'événement d'ouverture est en cours.
  static var wasLaunchedAtLogin: Bool {
    let event = NSAppleEventManager.shared().currentAppleEvent
    return event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
  }

  static func channel(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "clockifai/launch_at_login", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "status":
        result(status)
      case "set":
        setEnabled(call.arguments as? Bool ?? false)
        result(status)
      case "openSettings":
        openSystemSettings()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return channel
  }
}
