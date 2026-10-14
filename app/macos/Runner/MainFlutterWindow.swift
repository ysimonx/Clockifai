import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var menuBar: MenuBarController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = appName
    // Taille mémorisée d'un lancement à l'autre ; au premier, assez large pour le menu latéral.
    if !self.setFrameUsingName("Clockifai") {
      self.setContentSize(NSSize(width: 1200, height: 800))
      self.center()
    }
    self.setFrameAutosaveName("Clockifai")
    self.minSize = NSSize(width: 420, height: 560)
    // Fermer la fenêtre la masque seulement : l'app reste disponible dans la barre de menus.
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    menuBar = MenuBarController(messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}
