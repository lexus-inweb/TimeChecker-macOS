import Foundation

/// Тип отрезка времени.
/// - active: пользователь работал в каком-то окне
/// - idle: не трогал клавиатуру/мышь дольше порога
/// - away: экран заблокирован, мак спал или трекер был на паузе
enum SessionKind: String, Codable {
    case active, idle, away
}

struct Session: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var kind: SessionKind = .active
    var app: String = ""
    var bundleId: String = ""
    var title: String = ""
    var url: String? = nil
    /// Ручное отнесение к проекту (перекрывает правила).
    var projectId: UUID? = nil

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var domain: String? { url.flatMap(Domain.from(url:)) }
}

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Домены сайтов: "ti.ua" ловит и "ti.ua", и "shop.ti.ua".
    var domains: [String] = []
    /// Фразы в заголовке окна или адресе: "техноїжак", "Планфикс #123".
    var keywords: [String] = []
    /// Приложения по имени или bundle id: "Figma", "com.tinyspeck.slackmacgap".
    var apps: [String] = []
    var archived = false
}

struct AppSettings: Codable, Equatable {
    var idleMinutes = 3
    var roundingMinutes = 5
    var commentMaxItems = 5
    /// Распознавать название чата в шапке Telegram (нужна «Запись экрана»). По умолчанию выключено.
    var telegramOCR = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? d.idleMinutes
        roundingMinutes = try c.decodeIfPresent(Int.self, forKey: .roundingMinutes) ?? d.roundingMinutes
        commentMaxItems = try c.decodeIfPresent(Int.self, forKey: .commentMaxItems) ?? d.commentMaxItems
        telegramOCR = try c.decodeIfPresent(Bool.self, forKey: .telegramOCR) ?? d.telegramOCR
    }
}

/// То, что трекер видит в моменте: активное приложение, заголовок окна, адрес вкладки.
struct ActivitySnapshot: Equatable {
    var app: String
    var bundleId: String
    var title: String
    var url: String?
}

enum Domain {
    /// "https://www.Shop.ti.ua/path" -> "shop.ti.ua"
    static func from(url: String) -> String? {
        guard let comps = URLComponents(string: url),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Нормализует то, что пользователь ввёл в правило: убирает схему, www, путь.
    static func normalizeRule(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }

    static func matches(_ domain: String, rule: String) -> Bool {
        let r = normalizeRule(rule)
        guard !r.isEmpty else { return false }
        return domain == r || domain.hasSuffix("." + r)
    }
}

/// Браузеры, у которых трекер умеет читать адрес активной вкладки.
enum Browsers {
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "com.yandex.desktop.yandex-browser",
    ]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static func isBrowser(_ bundleId: String) -> Bool {
        chromium.contains(bundleId) || safari.contains(bundleId) || bundleId == "org.mozilla.firefox"
    }
}
