import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // L'icône de la barre de menus garde l'app ouverte quand la fenêtre est fermée.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Clic sur l'icône du Dock : rouvre la fenêtre fermée.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, let window = mainFlutterWindow {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
