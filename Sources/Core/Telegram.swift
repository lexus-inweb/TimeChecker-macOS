import CoreGraphics
import Foundation

/// Telegram: заголовок окна всегда «Telegram @ аккаунт» и не зависит от открытого чата.
/// По нему правила не могут разнести время, а слова из имени аккаунта ловят весь Telegram целиком.
/// Поэтому вместо него в отрезок пишется «Telegram — <чат>» или пустая строка, если чат неизвестен.
enum Telegram {
    static let bundleIds: Set<String> = ["ru.keepcoder.Telegram", "org.telegram.desktop"]

    static func isTelegram(_ bundleId: String) -> Bool { bundleIds.contains(bundleId) }

    /// «Inweb / SEO» → «Telegram — Inweb / SEO»; nil или мусор → "".
    static func windowTitle(chat: String?) -> String {
        guard let c = chat.flatMap(normalizeChat) else { return "" }
        return "Telegram — " + c
    }

    /// Чистит название чата: первая строка, без невидимых символов, лишних пробелов и счётчика «(3)».
    /// Заголовок самого окна («Telegram @ …», «Telegram (5)») чатом не считается.
    static func normalizeChat(_ raw: String) -> String? {
        let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{2060}\u{FEFF}")
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var s = String(String.UnicodeScalarView(firstLine.unicodeScalars.filter { !invisible.contains($0) }))
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        if let r = s.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) { s.removeSubrange(r) }
        let l = s.lowercased()
        if s.isEmpty || l == "telegram" || l.hasPrefix("telegram @") { return nil }
        if s.count > 80 { s = String(s.prefix(77)) + "…" }
        return s
    }

    // MARK: Распознавание шапки чата

    /// Полоса шапки чата: отступы слева и справа от краёв окна, по высоте — от top до top + height.
    /// Через Accessibility Telegram отдаёт только поле ввода. Колонка чата начинается
    /// чуть левее поля (там кнопка вложений). Шапка в Telegram 13 — «капсула» с названием и статусом
    /// в 12–52 pt от верха окна; выше и ниже неё просвечивают сообщения, их в полосу не берём.
    struct HeaderStrip: Equatable {
        static let top: CGFloat = 12
        static let height: CGFloat = 36
        static let attachInset: CGFloat = 60
        static let sendInset: CGFloat = 60

        var left: CGFloat
        var right: CGFloat

        /// window и input — в экранных координатах Accessibility (начало в левом верхнем углу).
        init?(window: CGRect, input: CGRect) {
            guard window.width > 0, input.width > 0,
                  input.minX >= window.minX, input.maxX <= window.maxX + 1 else { return nil }
            left = max(0, input.minX - Self.attachInset - window.minX)
            right = max(0, window.maxX - input.maxX - Self.sendInset)
        }

        /// Прямоугольник в координатах окна. nil, если окно стало слишком узким.
        func rect(in window: CGRect) -> CGRect? {
            let w = window.width - left - right
            guard w >= 120, window.height >= Self.top + Self.height else { return nil }
            return CGRect(x: left, y: Self.top, width: w, height: Self.height)
        }
    }

    /// Строка, найденная OCR. box — нормализованный, начало координат внизу слева (как в Vision).
    struct OCRLine: Equatable {
        var text: String
        var box: CGRect
    }

    /// Название чата — верхняя строка шапки. Под ней статус («в мережі», «5 участников»), он меньше и ниже.
    /// Куски одной строки (Vision режет по эмодзи) склеиваются слева направо. Мимо — одиночные числа
    /// (счётчики) и буквы аватара у левого края («C» в кружке у чата без фото).
    static func chatTitle(from lines: [OCRLine]) -> String? {
        let words = lines.filter { l in
            let t = l.text.trimmingCharacters(in: .whitespaces)
            if t.count <= 2 && l.box.maxX < 0.06 { return false }
            return t.contains { $0.isLetter } || t.count > 3
        }
        guard let top = words.max(by: { $0.box.midY < $1.box.midY }), top.box.midY >= 0.4 else { return nil }
        let row = words
            .filter { abs($0.box.midY - top.box.midY) < top.box.height / 2 }
            .sorted { $0.box.minX < $1.box.minX }
        return normalizeChat(row.map(\.text).joined(separator: " "))
    }
}

/// Кириллические буквы, которые выглядят как латинские (в любом регистре): OCR их путает,
/// и «CEO» приходит как «СEО». key() приводит строку к нижнему регистру и заменяет их на латиницу,
/// чтобы фраза из правила совпала с распознанным текстом, как бы его ни записал OCR.
enum Lookalikes {
    private static let map: [Character: Character] = [
        "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o", "р": "p",
        "с": "c", "т": "t", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
    ]

    static func key(_ s: String) -> String {
        String(s.lowercased().map { map[$0] ?? $0 })
    }
}
