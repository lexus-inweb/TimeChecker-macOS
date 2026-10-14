import AppKit
import ApplicationServices

/// Всё, что трекер «видит» в системе: активное окно, адрес вкладки, простой, блокировка, сон.
final class Sensors {
    private(set) var screenLocked = false
    private(set) var asleep = false
    private var urlPolicy = URLCachePolicy()
    private let urlQueue = DispatchQueue(label: "timechecker.browser-url")
    let telegram = TelegramReader()
    /// Распознавать название чата Telegram: опция включена и есть «Запись экрана». Ставит AppModel.
    var telegramOCR = false

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
        // У Telegram заголовок окна — «Telegram @ аккаунт» в любом чате, правилам он только мешает.
        // Вместо него — название чата, если включено распознавание шапки, иначе пусто.
        let title: String
        if Telegram.isTelegram(bundle) {
            title = Telegram.windowTitle(chat: telegramOCR ? telegram.chat(pid: app.processIdentifier) : nil)
        } else {
            telegram.deactivate()
            title = Self.windowTitle(pid: app.processIdentifier) ?? ""
        }
        var url: String? = nil
        if Browsers.chromium.contains(bundle) || Browsers.safari.contains(bundle) {
            // AppleScript — в фоне: первый запрос ждёт ответа на диалог «Автоматизация», UI не должен виснуть.
            // Когда перечитывать и какой ответ отбросить, решает URLCachePolicy.
            let (known, requestId) = urlPolicy.lookup(key: bundle + "|" + title, now: Date())
            url = known
            if let id = requestId {
                urlQueue.async {
                    let tab = Self.browserTab(bundleId: bundle)
                    DispatchQueue.main.async {
                        self.urlPolicy.complete(requestId: id, url: tab?.url, tabTitle: tab?.title, windowTitle: title, now: Date())
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

    /// Заголовок и адрес активной вкладки. Заголовок нужен, чтобы отбросить ответ про другую вкладку.
    /// Firefox через AppleScript адрес не отдаёт — для него работаем только по заголовку окна.
    private static func browserTab(bundleId: String) -> (title: String?, url: String?)? {
        let src: String
        if Browsers.chromium.contains(bundleId) {
            src = "tell application id \"\(bundleId)\" to if (count of windows) > 0 then tell active tab of front window to return {title, URL}"
        } else if Browsers.safari.contains(bundleId) {
            src = "tell application id \"\(bundleId)\" to if (count of windows) > 0 then tell current tab of front window to return {name, URL}"
        } else {
            return nil
        }
        var err: NSDictionary?
        guard let result = NSAppleScript(source: src)?.executeAndReturnError(&err), err == nil,
              result.numberOfItems == 2 else { return nil }
        let url = result.atIndex(2)?.stringValue
        return (result.atIndex(1)?.stringValue, url?.isEmpty == false ? url : nil)
    }
}
