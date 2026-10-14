import Cocoa
import FlutterMacOS
import SwiftUI

/// Icône Clockifai de la barre de menus (en haut à droite de l'écran), comme celle de Clockify.
///
/// Clic : panneau pour démarrer / arrêter le chronomètre, reprendre une entrée récente ou ouvrir
/// la fenêtre de l'application. Clic droit : ouvrir / quitter. Le temps écoulé s'affiche à côté
/// de l'icône tant qu'un chronomètre tourne.
///
/// Aucune donnée n'est lue ici : l'app Flutter (`lib/features/timer/menu_bar.dart`) envoie l'état
/// par le canal `clockifai/menu_bar` (`update`) et exécute les commandes du panneau sur la base locale.
final class MenuBarController: NSObject, NSPopoverDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private let channel: FlutterMethodChannel
  private let model = MenuBarModel()
  private weak var window: MainFlutterWindow?
  private var ticker: Timer?

  init(messenger: FlutterBinaryMessenger, window: MainFlutterWindow) {
    channel = FlutterMethodChannel(name: "clockifai/menu_bar", binaryMessenger: messenger)
    self.window = window
    super.init()

    model.perform = { [weak self] method, arguments in self?.perform(method, arguments) }
    model.openApp = { [weak self] in self?.showMainWindow() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else { return result(FlutterMethodNotImplemented) }
      self?.apply(call.arguments)
      result(nil)
    }

    if let button = statusItem.button {
      button.image = Self.icon(running: false)
      button.imagePosition = .imageLeading
      button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      button.toolTip = appName
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    let hosting = NSHostingController(rootView: MenuBarView(model: model))
    if #available(macOS 13.0, *) { hosting.sizingOptions = .preferredContentSize }
    popover.contentViewController = hosting
    popover.behavior = .transient
    popover.delegate = self
  }

  // MARK: - Icône

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else if popover.isShown {
      popover.performClose(sender)
    } else {
      showPopover()
    }
  }

  private func showPopover() {
    guard let button = statusItem.button else { return }
    model.prepareForDisplay()
    if #unavailable(macOS 13.0), let view = popover.contentViewController?.view {
      popover.contentSize = view.fittingSize
    }
    // Le panneau doit être actif pour recevoir la saisie de la description.
    Self.activateApp()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  private func showContextMenu() {
    let menu = NSMenu()
    let open = NSMenuItem(title: model.label("openApp"), action: #selector(openFromMenu), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    if LaunchAtLogin.isAvailable {
      let login = NSMenuItem(title: model.label("launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
      login.target = self
      login.state = LaunchAtLogin.status == "enabled" ? .on : .off
      menu.addItem(login)
    }
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: model.label("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    // Menu attaché le temps d'un clic : le clic gauche garde le panneau.
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func openFromMenu() {
    showMainWindow()
  }

  @objc private func toggleLaunchAtLogin() {
    LaunchAtLogin.setEnabled(LaunchAtLogin.status != "enabled")
    // Le système peut exiger une autorisation : on ouvre directement le bon panneau des Réglages.
    if LaunchAtLogin.status == "requiresApproval" { LaunchAtLogin.openSystemSettings() }
  }

  func popoverDidClose(_ notification: Notification) {
    // Une description modifiée sans valider (Entrée) est enregistrée à la fermeture.
    model.commitDescription()
    model.error = nil
  }

  /// Fenêtre principale au premier plan (rouverte si elle a été fermée).
  func showMainWindow() {
    popover.performClose(nil)
    window?.present()
  }

  private static func activateApp() {
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private static func icon(running: Bool) -> NSImage? {
    let image = NSImage(systemSymbolName: running ? "stopwatch.fill" : "stopwatch", accessibilityDescription: appName)
    let sized = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
    sized?.isTemplate = true
    return sized
  }

  // MARK: - Échanges avec Flutter

  private func apply(_ arguments: Any?) {
    guard let state = arguments as? [String: Any] else { return }
    model.apply(state, popoverShown: popover.isShown)
    statusItem.button?.image = Self.icon(running: model.running != nil)
    restartTicker()
  }

  private func perform(_ method: String, _ arguments: [String: Any]) {
    model.error = nil
    model.busy = true
    channel.invokeMethod(method, arguments: arguments) { [weak self] result in
      let message = (result as? String) ?? (result as? FlutterError)?.message
      DispatchQueue.main.async {
        self?.model.busy = false
        self?.model.error = message
      }
    }
  }

  // MARK: - Temps écoulé à côté de l'icône

  private func restartTicker() {
    ticker?.invalidate()
    ticker = nil
    guard model.runningStart != nil else {
      statusItem.button?.title = ""
      return
    }
    refreshTitle()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshTitle() }
    // Mode commun : le compteur continue pendant qu'un menu est ouvert.
    RunLoop.main.add(timer, forMode: .common)
    ticker = timer
  }

  private func refreshTitle() {
    guard let start = model.runningStart else { return }
    statusItem.button?.title = " " + formatClock(Date().timeIntervalSince(start))
  }
}

/// « 1:02:03 », comme `formatClock` côté Dart.
func formatClock(_ interval: TimeInterval) -> String {
  let s = max(0, Int(interval))
  return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}
