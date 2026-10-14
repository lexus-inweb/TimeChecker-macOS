import AppKit
import ApplicationServices

/// Всё, что трекер «видит» в системе: активное окно, адрес вкладки, простой, блокировка, сон.
final class Sensors {
    private(set) var screenLocked = false
    private(set) var asleep = false
    private var urlCache: (key: String, url: String?)?
    private var fetchingKey: String?
    private let urlQueue = DispatchQueue(label: "timechecker.browser-url")

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = true }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = false }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = true }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = false }
        }
    }

    var away: Bool { screenLocked || asleep }

    /// Секунды с последнего нажатия/движения мыши.
    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func snapshot() -> ActivitySnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundle = app.bundleIdentifier ?? ""
        if bundle == "com.apple.loginwindow" || bundle == "com.apple.ScreenSaver.Engine" { return nil }
        let name = app.localizedName ?? bundle
        let title = Self.windowTitle(pid: app.processIdentifier) ?? ""
        var url: String? = nil
        if Browsers.isBrowser(bundle) {
            // AppleScript дергаем только когда сменилось окно/вкладка, и в фоне: первый запрос
            // ждёт, пока пользователь ответит на диалог «Автоматизация», — UI при этом не должен виснуть.
            let key = bundle + "|" + title
            if let c = urlCache, c.key == key {
                url = c.url
            } else if fetchingKey == nil {
                fetchingKey = key
                urlQueue.async {
                    let fetched = Self.browserURL(bundleId: bundle)
                    DispatchQueue.main.async {
                        self.urlCache = (key, fetched)
                        self.fetchingKey = nil
                    }
                }
            }
        }
        return ActivitySnapshot(app: name, bundleId: bundle, title: title, url: url)
    }

    private static func windowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let w = win, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    private static func browserURL(bundleId: String) -> String? {
        let src: String
        if Browsers.chromium.contains(bundleId) {
            src = "tell application id \"\(bundleId)\" to if (count of windows) > 0 then return URL of active tab of front window"
        } else if Browsers.safari.contains(bundleId) {
            src = "tell application id \"\(bundleId)\" to if (count of documents) > 0 then return URL of front document"
        } else {
            return nil // Firefox не отдаёт адрес через AppleScript — работаем по заголовку
        }
        var err: NSDictionary?
        let result = NSAppleScript(source: src)?.executeAndReturnError(&err)
        guard err == nil, let s = result?.stringValue, !s.isEmpty else { return nil }
        return s
    }
}
