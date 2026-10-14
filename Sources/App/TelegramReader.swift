import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// Название открытого чата Telegram. Через Accessibility его не достать: Telegram рисует шапку чата
/// прямо в слой. Поэтому, если опция включена, снимаем полосу шапки и распознаём текст на этом Mac.
/// Снимок — не чаще раза в 2 секунды и только пока Telegram активен. Распознавание — только когда
/// изменилась верхняя половина шапки (название). Статус «печатает…» ниже и OCR не будит.
/// Потоки: chat/busy/strip — только главный, lastHash — только ocrQueue, target — только текущий снимок
/// (пока он идёт, busy не даёт начать следующий).
final class TelegramReader: @unchecked Sendable {
    private(set) var chat: String?
    private var strip: Telegram.HeaderStrip?
    private var target: (window: CGRect, display: SCDisplay, app: SCRunningApplication)?
    private var lastCapture = Date.distantPast
    private var lastHash: Int?
    private var busy = false
    private let ocrQueue = DispatchQueue(label: "timechecker.telegram-ocr", qos: .utility)

    static var screenCaptureAllowed: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenCapture() { _ = CGRequestScreenCaptureAccess() }

    static func openScreenCaptureSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Telegram ушёл с переднего плана — при возврате снимаем сразу, без паузы.
    func deactivate() { lastCapture = .distantPast }

    /// Раз в секунду, пока Telegram активен. Возвращает последнее распознанное название.
    func chat(pid: pid_t) -> String? {
        let now = Date()
        guard !busy, now.timeIntervalSince(lastCapture) >= 2 else { return chat }
        lastCapture = now
        guard let header = headerRect(pid: pid) else { chat = nil; return nil }
        busy = true
        Task { await self.capture(pid: pid, window: header.window, rect: header.rect) }
        return chat
    }

    // MARK: Где шапка

    private func headerRect(pid: pid_t) -> (window: CGRect, rect: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        guard let win = Self.element(app, kAXFocusedWindowAttribute), let wf = Self.frame(win) else { return nil }
        // Поля ввода нет в каналах и на пустом экране — тогда берём последнюю известную разметку.
        if let input = Self.inputField(win: win, app: app), let s = Telegram.HeaderStrip(window: wf, input: input) { strip = s }
        guard let rect = strip?.rect(in: wf) else { return nil }
        return (wf, rect)
    }

    /// Поле ввода — почти единственное, что Telegram отдаёт через Accessibility (раздел «Content» окна).
    private static func inputField(win: AXUIElement, app: AXUIElement) -> CGRect? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, "AXSections" as CFString, &v) == .success, let sections = v as? [[String: Any]] {
            for s in sections {
                guard let obj = s["SectionObject"] as CFTypeRef?, CFGetTypeID(obj) == AXUIElementGetTypeID() else { continue }
                let e = obj as! AXUIElement
                if role(e) == kAXTextAreaRole, let f = frame(e) { return f }
            }
        }
        if let f = element(app, kAXFocusedUIElementAttribute), role(f) == kAXTextAreaRole { return frame(f) }
        return nil
    }

    private static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func role(_ e: AXUIElement) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) == .success ? v as? String : nil
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    // MARK: Снимок и распознавание

    private func capture(pid: pid_t, window: CGRect, rect: CGRect) async {
        do {
            // Список экранов и программ дорогой — перечитываем, только когда окно Telegram сдвинулось.
            if target.map({ !Self.close($0.window, window) }) ?? true {
                target = nil
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let top = CGPoint(x: window.midX, y: window.minY + 1)
                if let display = content.displays.first(where: { $0.frame.contains(top) }),
                   let app = content.applications.first(where: { $0.processID == pid }) {
                    target = (window, display, app)
                }
            }
            guard let t = target else { return fail() }
            // Снимаем экран, но только окна Telegram: в полноэкранном режиме верх окна рисуется
            // отдельным окном, а чужие окна поверх Telegram в снимок не попадают.
            let filter = SCContentFilter(display: t.display, including: [t.app], exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            cfg.sourceRect = rect.offsetBy(dx: window.minX - t.display.frame.minX, dy: window.minY - t.display.frame.minY)
            cfg.width = Int(rect.width * scale)
            cfg.height = Int(rect.height * scale)
            cfg.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            ocrQueue.async { self.recognize(image) }
        } catch {
            target = nil
            fail()
        }
    }

    private func recognize(_ image: CGImage) {
        let hash = Self.titleHash(image)
        if let hash, hash == lastHash {
            DispatchQueue.main.async { self.busy = false }
            return
        }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate // кириллицу распознаёт только точный режим
        req.recognitionLanguages = ["uk-UA", "ru-RU", "en-US"]
        req.usesLanguageCorrection = false // названия чатов — не словарные слова
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let lines = (req.results ?? []).compactMap { o in
            o.topCandidates(1).first.map { Telegram.OCRLine(text: $0.string, box: o.boundingBox) }
        }
        lastHash = hash
        let title = Telegram.chatTitle(from: lines)
        DispatchQueue.main.async {
            // Совсем без текста шапка бывает на миг (анимация смены чата, просмотр фото поверх) —
            // оставляем прежний чат, чтобы не дробить отрезок.
            if !lines.isEmpty { self.chat = title }
            self.busy = false
        }
    }

    /// Снять не вышло (окно пропало, отозвали «Запись экрана») — заголовок пустой, при следующем снимке OCR заново.
    private func fail() {
        ocrQueue.async { self.lastHash = nil }
        DispatchQueue.main.async {
            self.chat = nil
            self.busy = false
        }
    }

    /// Отпечаток верхней половины снимка — там название; статус ниже меняется часто и OCR не будит.
    private static func titleHash(_ image: CGImage) -> Int? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let len = min(CFDataGetLength(data), image.bytesPerRow * image.height / 2)
        var h = Hasher()
        h.combine(bytes: UnsafeRawBufferPointer(start: bytes, count: len))
        return h.finalize()
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}

/// Состояние опции для «Настроек»: есть ли «Запись экрана» и какой чат распознан последним.
/// Отдельный объект, чтобы смена чата не перерисовывала всё приложение.
final class TelegramOCRStatus: ObservableObject {
    @Published private(set) var allowed = false
    @Published private(set) var lastChat: String?
    private var checked = false

    /// Раз в секунду из AppModel. Возвращает, можно ли сейчас распознавать.
    func update(enabled: Bool, tick: Int, chat: String?) -> Bool {
        guard enabled else { checked = false; return false }
        if !checked || tick % 5 == 0 {
            checked = true
            let a = TelegramReader.screenCaptureAllowed
            if a != allowed { allowed = a }
        }
        if allowed, let chat, chat != lastChat { lastChat = chat }
        return allowed
    }
}
