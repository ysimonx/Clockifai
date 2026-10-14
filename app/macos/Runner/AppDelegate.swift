import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // L'icône de la barre de menus garde l'app ouverte quand la fenêtre est fermée.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // App relancée (Finder, Spotlight, Dock) alors qu'elle tourne déjà : rouvre la fenêtre fermée.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { (mainFlutterWindow as? MainFlutterWindow)?.present() }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
