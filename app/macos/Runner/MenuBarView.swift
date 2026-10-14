import Cocoa
import SwiftUI

/// Entrée de temps telle que l'envoie Flutter (chronomètre en cours ou entrée récente).
struct MenuBarEntry: Identifiable, Equatable {
  let id: String
  let description: String
  let projectId: String?
  let project: String?
  let client: String?
  let task: String?
  let color: String?

  init?(_ value: Any?) {
    guard let m = value as? [String: Any], let id = m["id"] as? String else { return nil }
    self.id = id
    description = m["description"] as? String ?? ""
    projectId = m["projectId"] as? String
    project = m["project"] as? String
    client = m["client"] as? String
    task = m["task"] as? String
    color = m["color"] as? String
  }
}

struct MenuBarProject: Identifiable, Equatable {
  let id: String
  let name: String
  let client: String?
  let color: String?

  init?(_ value: Any?) {
    guard let m = value as? [String: Any], let id = m["id"] as? String, let name = m["name"] as? String else { return nil }
    self.id = id
    self.name = name
    client = m["client"] as? String
    color = m["color"] as? String
  }
}

/// État du panneau : ce que Flutter envoie, plus le brouillon saisi dans le panneau.
final class MenuBarModel: ObservableObject {
  @Published var signedIn = false
  @Published var firstSync = false
  @Published var ready = false
  @Published var running: MenuBarEntry?
  @Published var runningStart: Date?
  @Published var recent: [MenuBarEntry] = []
  @Published var projects: [MenuBarProject] = []
  @Published var labels: [String: String] = [:]

  @Published var description = ""
  @Published var draftProjectId: String?
  @Published var error: String?
  /// Commande en cours d'exécution côté Flutter : évite qu'un double-clic démarre deux chronomètres.
  @Published var busy = false

  var perform: (String, [String: Any]) -> Void = { _, _ in }
  var openApp: () -> Void = {}

  /// Libellés traduits par Flutter (ARB) ; repli en français avant le premier envoi.
  func label(_ key: String) -> String {
    labels[key] ?? [
      "openApp": "Ouvrir Clockifai",
      "quit": "Quitter Clockifai",
      "signIn": "Connectez-vous dans la fenêtre Clockifai pour suivre votre temps.",
    ][key] ?? key
  }

  func apply(_ state: [String: Any], popoverShown: Bool) {
    let previous = running?.id
    signedIn = state["signedIn"] as? Bool ?? false
    firstSync = state["firstSync"] as? Bool ?? false
    ready = state["ready"] as? Bool ?? false
    running = MenuBarEntry(state["running"])
    if let ms = (state["running"] as? [String: Any])?["start"] as? NSNumber {
      runningStart = Date(timeIntervalSince1970: ms.doubleValue / 1000)
    } else {
      runningStart = nil
    }
    recent = (state["recent"] as? [Any] ?? []).compactMap(MenuBarEntry.init)
    projects = (state["projects"] as? [Any] ?? []).compactMap(MenuBarProject.init)
    if let l = state["labels"] as? [String: String] { labels = l }
    // Projet archivé ou d'un autre workspace (changement de workspace) : le brouillon l'oublie.
    if let id = draftProjectId, !projects.contains(where: { $0.id == id }) { draftProjectId = nil }

    if running?.id != previous {
      description = running?.description ?? ""
      draftProjectId = nil
    } else if let running, !popoverShown {
      // Description modifiée ailleurs (fenêtre, autre appareil) : on la reprend si le panneau est fermé.
      description = running.description
    }
  }

  func prepareForDisplay() {
    error = nil
    if let running { description = running.description }
  }

  // MARK: - Commandes (exécutées par Flutter)

  func start() {
    guard !busy else { return }
    perform("start", ["description": description, "projectId": draftProjectId ?? NSNull()])
  }

  func stop() {
    guard !busy else { return }
    perform("stop", ["description": description])
  }

  func commitDescription() {
    guard let running, description.trimmingCharacters(in: .whitespacesAndNewlines) != running.description else { return }
    perform("setDescription", ["description": description])
  }

  func selectProject(_ id: String?) {
    if running != nil {
      guard !busy else { return }
      perform("setProject", ["projectId": id ?? NSNull()])
    } else {
      draftProjectId = id
    }
  }

  func continueEntry(_ id: String) {
    guard !busy else { return }
    perform("continue", ["id": id])
  }

  // MARK: - Affichage

  /// Projet affiché sous la description : celui du chronomètre, sinon celui du brouillon.
  var shownProject: (name: String, color: String?)? {
    if let running {
      guard let name = running.project else { return nil }
      return (projectTitle(name, client: running.client, task: running.task), running.color)
    }
    guard let p = projects.first(where: { $0.id == draftProjectId }) else { return nil }
    return (projectTitle(p.name, client: p.client, task: nil), p.color)
  }
}

/// « Projet · Client — Tâche », comme `ProjectLabel` côté Flutter.
func projectTitle(_ name: String, client: String?, task: String?) -> String {
  var title = name
  if let client, !client.isEmpty { title += " · \(client)" }
  if let task, !task.isEmpty { title += " — \(task)" }
  return title
}

/// « Clockifai » ou « Clockifai Dev » selon la configuration de build (Info.plist).
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Clockifai"

/// Couleur de l'app (graine du thème Flutter, `core/theme.dart`).
let clockifaiBlue = Color(red: 0x0E / 255, green: 0xA5 / 255, blue: 0xE9 / 255)

/// Pastille de couleur d'un projet, en image : les menus natifs n'affichent pas les formes SwiftUI.
func colorDot(_ hex: String?, size: CGFloat = 9) -> NSImage {
  let color = nsColor(hex) ?? .tertiaryLabelColor
  let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
    return true
  }
  return image
}

func nsColor(_ hex: String?) -> NSColor? {
  guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
  if s.hasPrefix("#") { s.removeFirst() }
  guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
  return NSColor(
    srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

private func truncated(_ s: String, _ max: Int = 26) -> String {
  s.count > max ? String(s.prefix(max - 1)) + "…" : s
}

// MARK: - Panneau

struct MenuBarView: View {
  @ObservedObject var model: MenuBarModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if model.signedIn && model.ready {
        timer.padding(12)
        if !model.recent.isEmpty {
          Divider()
          recent
        }
      } else {
        Text(model.label(!model.signedIn ? "signIn" : model.firstSync ? "firstSync" : "noWorkspace"))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(16)
      }
      Divider()
      footer
    }
    .frame(width: 340)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "stopwatch").foregroundColor(clockifaiBlue)
      Text(appName).font(.headline)
      Spacer()
      Button(action: model.openApp) {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.borderless)
      .help(model.label("openApp"))
      .accessibilityLabel(Text(model.label("openApp")))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var timer: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(model.label("whatAreYouWorkingOn"), text: $model.description)
        .textFieldStyle(.roundedBorder)
        .onSubmit { model.running == nil ? model.start() : model.commitDescription() }
      HStack(spacing: 8) {
        // Le compteur et le bouton gardent leur taille ; le projet prend le reste et se tronque.
        projectMenu
          .frame(maxWidth: .infinity, alignment: .leading)
        elapsed
          .fixedSize()
          .layoutPriority(1)
        startStopButton
      }
      if let error = model.error {
        Text(error)
          .font(.caption)
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var projectMenu: some View {
    Menu {
      Button(model.label("noProject")) { model.selectProject(nil) }
      if !model.projects.isEmpty { Divider() }
      ForEach(model.projects) { p in
        Button {
          model.selectProject(p.id)
        } label: {
          Label { Text(projectTitle(p.name, client: p.client, task: nil)) } icon: { Image(nsImage: colorDot(p.color)) }
        }
      }
    } label: {
      if let project = model.shownProject {
        Label { Text(truncated(project.name)) } icon: { Image(nsImage: colorDot(project.color)) }
      } else {
        Label(model.label("project"), systemImage: "plus.circle")
      }
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .frame(maxWidth: 190, alignment: .leading)
    .clipped()
  }

  @ViewBuilder private var elapsed: some View {
    if let start = model.runningStart {
      TimelineView(.periodic(from: start, by: 1)) { context in
        Text(formatClock(context.date.timeIntervalSince(start)))
          .font(.system(size: 15, weight: .semibold).monospacedDigit())
      }
    } else {
      Text("0:00:00")
        .font(.system(size: 15).monospacedDigit())
        .foregroundColor(.secondary)
    }
  }

  private var startStopButton: some View {
    let running = model.running != nil
    return Button(action: running ? model.stop : model.start) {
      Image(systemName: running ? "stop.fill" : "play.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 30, height: 30)
        .background(Circle().fill(running ? Color.red : clockifaiBlue))
    }
    .buttonStyle(.plain)
    .disabled(model.busy)
    .help(running ? model.label("stop") : model.label("start"))
    .accessibilityLabel(Text(running ? model.label("stop") : model.label("start")))
  }

  private var recent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(model.label("recent").uppercased())
        .font(.caption2.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
      ForEach(model.recent) { entry in
        RecentRow(entry: entry, model: model)
      }
    }
    .padding(.bottom, 6)
  }

  private var footer: some View {
    HStack {
      Button(model.label("openApp"), action: model.openApp)
      Spacer()
      Button(model.label("quit")) { NSApp.terminate(nil) }
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

/// Entrée récente : un clic la relance (« Continuer »).
private struct RecentRow: View {
  let entry: MenuBarEntry
  @ObservedObject var model: MenuBarModel
  @State private var hovered = false

  var body: some View {
    Button { model.continueEntry(entry.id) } label: {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.description.isEmpty ? model.label("noDescription") : entry.description)
            .foregroundColor(entry.description.isEmpty ? .secondary : .primary)
            .lineLimit(1)
          HStack(spacing: 4) {
            if let project = entry.project {
              Image(nsImage: colorDot(entry.color, size: 7))
              Text(projectTitle(project, client: entry.client, task: entry.task))
            } else {
              Text(model.label("noProject"))
            }
          }
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
        }
        Spacer(minLength: 4)
        Image(systemName: "play.circle")
          .font(.system(size: 17))
          .foregroundColor(hovered ? clockifaiBlue : .secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
      .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.primary.opacity(0.07) : Color.clear))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 4)
    .onHover { hovered = $0 }
    .help(model.label("continue"))
  }
}
