import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var menuBar: MenuBarController?
  private var launchAtLogin: FlutterMethodChannel?

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
    // Pas de réouverture automatique par le système : c'est le lancement qui décide (voir plus bas).
    self.isRestorable = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    menuBar = MenuBarController(messenger: messenger, window: self)
    launchAtLogin = LaunchAtLogin.channel(messenger: messenger)

    // L'app démarre sans icône dans le Dock (LSUIElement) ni fenêtre (visibleAtLaunch = NO dans MainMenu.xib).
    // Lancée par l'utilisateur : la fenêtre s'ouvre. Lancée à l'ouverture de session : seulement la barre de menus.
    // (queue nil : exécuté pendant l'envoi de la notification, quand l'événement de lancement est encore lisible.)
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { [weak self] _ in
      if !LaunchAtLogin.wasLaunchedAtLogin { self?.present() }
    }
    // L'icône du Dock suit la fenêtre : fenêtre fermée, l'app ne vit plus que dans la barre de menus.
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: self, queue: .main) { _ in
      NSApp.setActivationPolicy(.accessory)
    }

    super.awakeFromNib()
  }

  /// Fenêtre au premier plan, avec l'icône du Dock (rouverte si elle a été fermée).
  func present() {
    NSApp.setActivationPolicy(.regular)
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
  }
}
