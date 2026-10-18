import AppKit
import ServiceManagement

let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let usagePageURL = URL(string: "https://claude.ai/settings/usage")!
let refreshInterval: TimeInterval = 300
// Ephemeral: the default session caches requests (including the Authorization header) to disk.
let session = URLSession(configuration: .ephemeral)

struct Limit {
  let key: String
  let utilization: Double
  let resetsAt: Date?

  var label: String {
    switch key {
    case "five_hour": return "Session (5h)"
    case "seven_day": return "Weekly (all models)"
    case "seven_day_opus": return "Weekly (Opus)"
    case "seven_day_sonnet": return "Weekly (Sonnet)"
    default: return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  // Only limits with a short name appear in the menu bar itself.
  var shortName: String? { ["five_hour": "5h", "seven_day": "7d"][key] }
}

enum UsageError: LocalizedError {
  case noCredentials, unauthorized, http(Int)

  var errorDescription: String? {
    switch self {
    case .noCredentials: return "No Claude Code login found in Keychain"
    case .unauthorized: return "Token expired: open Claude Code to refresh it"
    case .http(let code): return "Usage request failed (HTTP \(code))"
    }
  }
}

// Claude Code stores its OAuth credentials as JSON in this Keychain item.
// Reading via the `security` CLI matches how Claude Code writes it, so no Keychain prompt.
func readAccessToken() throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
  let out = Pipe()
  process.standardOutput = out
  process.standardError = Pipe()
  try process.run()
  let data = out.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0,
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let oauth = json["claudeAiOauth"] as? [String: Any],
    let token = oauth["accessToken"] as? String
  else { throw UsageError.noCredentials }
  return token
}

func parseDate(_ string: String) -> Date? {
  // The API returns microsecond precision, which ISO8601DateFormatter can't parse; drop it.
  let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
  return ISO8601DateFormatter().date(from: trimmed)
}

func fetchLimits() async throws -> [Limit] {
  var request = URLRequest(url: usageURL)
  request.setValue("Bearer \(try readAccessToken())", forHTTPHeaderField: "Authorization")
  request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
  let (data, response) = try await session.data(for: request)
  let status = (response as? HTTPURLResponse)?.statusCode ?? 0
  if status == 401 { throw UsageError.unauthorized }
  guard status == 200 else { throw UsageError.http(status) }

  // Every top-level object with a `utilization` field is a limit (five_hour, seven_day, ...).
  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
  let order = ["five_hour", "seven_day"]
  return json.compactMap { key, value -> Limit? in
    guard let dict = value as? [String: Any], let utilization = dict["utilization"] as? Double else { return nil }
    return Limit(key: key, utilization: utilization, resetsAt: (dict["resets_at"] as? String).flatMap(parseDate))
  }.sorted {
    (order.firstIndex(of: $0.key) ?? order.count, $0.key) < (order.firstIndex(of: $1.key) ?? order.count, $1.key)
  }
}

func color(for utilization: Double) -> NSColor {
  utilization >= 90 ? .systemRed : utilization >= 75 ? .systemOrange : .labelColor
}

// Draws `5h [███░░░]  7d [█░░░░░]`, optionally with the percent centered in each bar.
// A drawing handler (rather than a pre-rendered bitmap) re-resolves colors when the menu bar flips light/dark.
func barsImage(_ limits: [Limit], showText: Bool) -> NSImage {
  let labelFont = NSFont.systemFont(ofSize: 11)
  let textFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
  let barWidth: CGFloat = 40, barHeight: CGFloat = showText ? 13 : 8
  let labelGap: CGFloat = 3, spacing: CGFloat = 8, height: CGFloat = 18
  let labels = limits.map { NSAttributedString(string: $0.shortName ?? "", attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor]) }
  let width = labels.reduce(0) { $0 + $1.size().width + labelGap + barWidth } + spacing * CGFloat(limits.count - 1)

  return NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
    let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    var x: CGFloat = 0
    for (label, limit) in zip(labels, limits) {
      let labelSize = label.size()
      label.draw(at: NSPoint(x: x, y: (height - labelSize.height) / 2))
      x += labelSize.width + labelGap

      let bar = NSRect(x: x, y: (height - barHeight) / 2, width: barWidth, height: barHeight)
      let track = NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3)
      let fillColor = color(for: limit.utilization)
      var filled = bar
      filled.size.width = bar.width * min(max(limit.utilization, 0), 100) / 100
      NSColor.labelColor.withAlphaComponent(0.25).setFill()
      track.fill()
      NSGraphicsContext.saveGraphicsState()
      track.addClip()
      fillColor.setFill()
      filled.fill()
      NSGraphicsContext.restoreGraphicsState()

      if showText {
        // Draw the percent twice: normal over the empty track, then clipped to the filled part in a contrasting color.
        let text = "\(Int(limit.utilization.rounded()))%" as NSString
        let textSize = text.size(withAttributes: [.font: textFont])
        let point = NSPoint(x: bar.midX - textSize.width / 2, y: bar.midY - textSize.height / 2)
        text.draw(at: point, withAttributes: [.font: textFont, .foregroundColor: NSColor.labelColor])
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: filled).addClip()
        let contrast: NSColor = fillColor == .labelColor && isDark ? .black : .white
        text.draw(at: point, withAttributes: [.font: textFont, .foregroundColor: contrast])
        NSGraphicsContext.restoreGraphicsState()
      }
      x += barWidth + spacing
    }
    return true
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var limits: [Limit] = []
  var error: Error?
  var updatedAt: Date?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem.button?.title = "Claude …"
    render()
    refresh()
    Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
      Task { @MainActor in self.refresh() }
    }
  }

  @objc func refresh() {
    Task {
      do {
        limits = try await fetchLimits()
        error = nil
        updatedAt = Date()
      } catch {
        self.error = error
      }
      render()
    }
  }

  @objc func toggleLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
      }
    } catch {
      self.error = error
    }
    render()
  }

  @objc func toggleSetting(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    render()
  }

  func settingItem(_ title: String, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(toggleSetting), keyEquivalent: "")
    item.representedObject = key
    item.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
    return item
  }

  @objc func openUsagePage() {
    NSWorkspace.shared.open(usagePageURL)
  }

  func render() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let summary = limits.filter { $0.shortName != nil }
    let showBars = UserDefaults.standard.bool(forKey: "showBars")
    if showBars && !summary.isEmpty {
      statusItem.button?.image = barsImage(summary, showText: UserDefaults.standard.bool(forKey: "showBarText"))
      statusItem.button?.imagePosition = .imageLeading
      statusItem.button?.attributedTitle = NSAttributedString(string: error == nil ? "" : " ⚠︎", attributes: [.font: font])
    } else {
      let title = NSMutableAttributedString()
      for limit in summary {
        if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
        title.append(NSAttributedString(
          string: "\(limit.shortName!) \(Int(limit.utilization.rounded()))%",
          attributes: [.font: font, .foregroundColor: color(for: limit.utilization)]))
      }
      if error != nil { title.append(NSAttributedString(string: " ⚠︎", attributes: [.font: font])) }
      if title.length == 0 { title.append(NSAttributedString(string: error == nil ? "Claude …" : "Claude ⚠︎", attributes: [.font: font])) }
      statusItem.button?.image = nil
      statusItem.button?.attributedTitle = title
    }

    let menu = NSMenu()
    let resetFormat = Date.FormatStyle().weekday(.abbreviated).hour().minute()
    for limit in limits {
      var text = "\(limit.label): \(Int(limit.utilization.rounded()))%"
      if let resetsAt = limit.resetsAt { text += "  ·  resets \(resetsAt.formatted(resetFormat))" }
      menu.addItem(NSMenuItem(title: text, action: nil, keyEquivalent: ""))
    }
    if let error {
      menu.addItem(NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: ""))
    }
    if let updatedAt {
      menu.addItem(.separator())
      menu.addItem(NSMenuItem(title: "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))", action: nil, keyEquivalent: ""))
    }
    menu.addItem(.separator())
    menu.addItem(settingItem("Show as Bars", key: "showBars"))
    if showBars {
      let textItem = settingItem("Show Percent in Bars", key: "showBarText")
      textItem.indentationLevel = 1
      menu.addItem(textItem)
    }
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r"))
    menu.addItem(NSMenuItem(title: "Open Usage Page…", action: #selector(openUsagePage), keyEquivalent: "u"))
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(loginItem)
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
      item.target = self
    }
    statusItem.menu = menu
  }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}
