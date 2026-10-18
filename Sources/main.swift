import AppKit

let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let usagePageURL = URL(string: "https://claude.ai/settings/usage")!
let refreshInterval: TimeInterval = 300

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
  let (data, response) = try await URLSession.shared.data(for: request)
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

  @objc func openUsagePage() {
    NSWorkspace.shared.open(usagePageURL)
  }

  func render() {
    let title = NSMutableAttributedString()
    let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let shortNames = ["five_hour": "5h", "seven_day": "7d"]
    for limit in limits where shortNames[limit.key] != nil {
      if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
      title.append(NSAttributedString(
        string: "\(shortNames[limit.key]!) \(Int(limit.utilization.rounded()))%",
        attributes: [.font: font, .foregroundColor: color(for: limit.utilization)]))
    }
    if error != nil { title.append(NSAttributedString(string: " ⚠︎", attributes: [.font: font])) }
    if title.length == 0 { title.append(NSAttributedString(string: error == nil ? "Claude …" : "Claude ⚠︎", attributes: [.font: font])) }
    statusItem.button?.attributedTitle = title

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
    menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r"))
    menu.addItem(NSMenuItem(title: "Open Usage Page…", action: #selector(openUsagePage), keyEquivalent: "u"))
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
