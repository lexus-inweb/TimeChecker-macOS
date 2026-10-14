import Foundation

// MARK: - Определение проекта

enum Classifier {
    /// Порядок: ручное отнесение → домен вкладки → домен в заголовке → ключевая фраза → приложение.
    static func projectId(for s: Session, projects: [Project]) -> UUID? {
        let live = projects.filter { !$0.archived }
        if let manual = s.projectId {
            return projects.contains { $0.id == manual } ? manual : nil
        }
        guard s.kind == .active else { return nil }

        // Хвост браузера («- Google Chrome – Alexey (inweb.ua)») есть в каждом окне — по нему не матчим.
        let title = Report.stripBrowserTail(s.title).lowercased()
        let url = (s.url ?? "").lowercased()

        if let domain = s.domain {
            for p in live where p.domains.contains(where: { Domain.matches(domain, rule: $0) }) {
                return p.id
            }
        }
        for p in live {
            let hit = p.domains.contains { rule in
                let r = Domain.normalizeRule(rule)
                return r.contains(".") && title.contains(r)
            }
            if hit { return p.id }
        }
        for p in live {
            let hit = p.keywords.contains { raw in
                let k = raw.trimmingCharacters(in: .whitespaces).lowercased()
                return !k.isEmpty && (title.contains(k) || url.contains(k))
            }
            if hit { return p.id }
        }
        let app = s.app.lowercased(), bundle = s.bundleId.lowercased()
        for p in live {
            let hit = p.apps.contains { raw in
                let a = raw.trimmingCharacters(in: .whitespaces).lowercased()
                return !a.isEmpty && (a == app || a == bundle)
            }
            if hit { return p.id }
        }
        return nil
    }
}

// MARK: - Отчёт

struct ReportLine: Identifiable, Equatable {
    var id: UUID { projectId }
    var projectId: UUID
    var name: String
    var seconds: TimeInterval
    var minutes: Int
    var comment: String
}

enum Report {
    /// Округление до шага. Меньше минуты — 0; иначе минимум один шаг.
    static func roundMinutes(_ seconds: TimeInterval, step: Int) -> Int {
        let mins = seconds / 60
        guard mins >= 1 else { return 0 }
        guard step > 1 else { return Int(mins.rounded()) }
        let r = Int((mins / Double(step)).rounded()) * step
        return max(r, step)
    }

    static func format(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) мин" }
        if m == 0 { return "\(h) ч" }
        return "\(h) ч \(m) мин"
    }

    static func format(seconds: TimeInterval) -> String {
        format(minutes: Int((seconds / 60).rounded()))
    }

    private static let browserNames = [
        "google chrome", "safari", "brave", "microsoft edge", "arc", "firefox", "mozilla firefox",
        "vivaldi", "opera", "yandex", "chromium",
    ]

    /// "Задача — Планфикс - Google Chrome – Alexey (inweb.ua)" → "Задача — Планфикс"
    static func stripBrowserTail(_ title: String) -> String {
        var cut = title.endIndex
        for sep in [" — ", " – ", " - ", " | ", " · "] {
            for name in browserNames {
                var from = title.startIndex
                while let r = title.range(of: sep + name, options: .caseInsensitive, range: from..<title.endIndex) {
                    // Имя браузера должно быть целым словом: " - Arc" да, " - Archive" нет.
                    if r.upperBound == title.endIndex || title[r.upperBound] == " " {
                        if r.lowerBound < cut { cut = r.lowerBound }
                        break
                    }
                    from = r.upperBound
                }
            }
        }
        return String(title[..<cut])
    }

    /// Чистит заголовок для комментария: убирает имя браузера/приложения, счётчики "(3)", почты.
    static func cleanTitle(_ title: String, app: String, domain: String? = nil) -> String {
        var t = title
        if let r = t.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { t.removeSubrange(r) }
        let separators = [" — ", " – ", " - ", " | ", " · "]
        var parts = [t]
        for sep in separators { parts = parts.flatMap { $0.components(separatedBy: sep) } }
        let appL = app.lowercased()
        // Всё после имени браузера — профиль Chrome ("Google Chrome – Work (example.com)"), отрезаем.
        if let cut = parts.firstIndex(where: { p in
            let l = p.trimmingCharacters(in: .whitespaces).lowercased()
            return browserNames.contains(where: { l == $0 || l.hasPrefix($0 + " ") })
        }) { parts = Array(parts[..<cut]) }
        let kept = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { p in
            let l = p.lowercased()
            if l.isEmpty || l == appL { return false }
            if browserNames.contains(where: { l == $0 || l.hasPrefix($0 + " ") }) { return false }
            if l.contains("@") && !l.contains(" ") { return false }
            if let d = domain, l == d || l == "www." + d { return false }
            return true
        }
        var out = kept.joined(separator: " — ")
        if out.count > 80 { out = String(out.prefix(77)) + "…" }
        return out
    }

    /// Черновик комментария: самые «тяжёлые» по времени заголовки.
    static func comment(for sessions: [Session], maxItems: Int) -> String {
        var weights: [String: TimeInterval] = [:]
        var order: [String] = []
        for s in sessions {
            let c = cleanTitle(s.title, app: s.app, domain: s.domain)
            guard !c.isEmpty else { continue }
            if weights[c] == nil { order.append(c) }
            weights[c, default: 0] += s.duration
        }
        let ranked = order
            .filter { weights[$0]! >= 60 }
            .sorted { weights[$0]! > weights[$1]! }
            .prefix(maxItems)
        return ranked.joined(separator: "; ")
    }

    static func build(sessions: [Session], projects: [Project], settings: AppSettings) -> [ReportLine] {
        var grouped: [UUID: [Session]] = [:]
        for s in sessions {
            if let pid = Classifier.projectId(for: s, projects: projects) { grouped[pid, default: []].append(s) }
        }
        return projects.compactMap { p -> ReportLine? in
            guard let list = grouped[p.id] else { return nil }
            let secs = list.reduce(0) { $0 + $1.duration }
            let mins = roundMinutes(secs, step: settings.roundingMinutes)
            guard mins > 0 else { return nil }
            return ReportLine(projectId: p.id, name: p.name, seconds: secs, minutes: mins,
                              comment: comment(for: list, maxItems: settings.commentMaxItems))
        }
        .sorted { $0.seconds > $1.seconds }
    }

    static func text(_ lines: [ReportLine], comments: [UUID: String] = [:]) -> String {
        lines.map { l in
            let c = (comments[l.projectId] ?? l.comment).trimmingCharacters(in: .whitespacesAndNewlines)
            let head = "\(l.name) — \(format(minutes: l.minutes))"
            return c.isEmpty ? head : head + "\n" + c
        }
        .joined(separator: "\n\n")
    }
}

// MARK: - Вкладка «Другое»

struct SessionGroup: Identifiable, Equatable {
    var id: String
    var label: String
    var detail: String
    var kind: SessionKind
    var start: Date
    var end: Date
    var seconds: TimeInterval
    var sessionIds: [UUID]
    var domain: String?
    var app: String
}

enum Grouping {
    static func unclassified(_ sessions: [Session], projects: [Project], includeIdle: Bool) -> [Session] {
        sessions.filter { s in
            guard Classifier.projectId(for: s, projects: projects) == nil else { return false }
            return s.kind == .active || includeIdle
        }
    }

    static func label(for s: Session) -> String {
        switch s.kind {
        case .idle: return "Простой"
        case .away: return "Отошёл / блокировка / сон"
        case .active: return s.domain ?? s.app
        }
    }

    /// По хронологии: подряд идущие отрезки одного приложения/сайта склеиваются в одну сессию.
    static func chronological(_ sessions: [Session], maxGap: TimeInterval = 120) -> [SessionGroup] {
        var out: [SessionGroup] = []
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            let label = label(for: s)
            let title = s.kind == .active ? s.title : ""
            if var last = out.last, last.label == label, last.kind == s.kind,
               s.start.timeIntervalSince(last.end) <= maxGap {
                last.end = max(last.end, s.end)
                last.seconds += s.duration
                last.sessionIds.append(s.id)
                if !title.isEmpty && !last.detail.contains(title) && last.detail.count < 300 {
                    last.detail += last.detail.isEmpty ? title : " · " + title
                }
                out[out.count - 1] = last
            } else {
                out.append(SessionGroup(id: s.id.uuidString, label: label, detail: title, kind: s.kind,
                                        start: s.start, end: s.end, seconds: s.duration,
                                        sessionIds: [s.id], domain: s.domain, app: s.app))
            }
        }
        return out
    }

    /// По типу программы: всё время одного приложения (или сайта для браузеров) в одной строке.
    static func byApp(_ sessions: [Session]) -> [SessionGroup] {
        var map: [String: SessionGroup] = [:]
        for s in sessions {
            let key = "\(s.kind.rawValue)|\(label(for: s))"
            if var g = map[key] {
                g.start = min(g.start, s.start); g.end = max(g.end, s.end)
                g.seconds += s.duration; g.sessionIds.append(s.id)
                if s.kind == .active, !s.title.isEmpty, !g.detail.contains(s.title), g.detail.count < 300 {
                    g.detail += g.detail.isEmpty ? s.title : " · " + s.title
                }
                map[key] = g
            } else {
                map[key] = SessionGroup(id: key, label: label(for: s), detail: s.kind == .active ? s.title : "",
                                        kind: s.kind, start: s.start, end: s.end, seconds: s.duration,
                                        sessionIds: [s.id], domain: s.domain, app: s.app)
            }
        }
        return map.values.sorted { $0.seconds > $1.seconds }
    }
}

// MARK: - Дашборд

struct Stats: Equatable {
    var projectSeconds: [UUID: TimeInterval] = [:]
    var otherSeconds: TimeInterval = 0
    var idleSeconds: TimeInterval = 0
    var awaySeconds: TimeInterval = 0
    var byApp: [String: TimeInterval] = [:]
    var byDomain: [String: TimeInterval] = [:]

    var projectsTotal: TimeInterval { projectSeconds.values.reduce(0, +) }

    static func build(_ sessions: [Session], projects: [Project]) -> Stats {
        var st = Stats()
        for s in sessions {
            let d = s.duration
            if let pid = Classifier.projectId(for: s, projects: projects) {
                st.projectSeconds[pid, default: 0] += d
            } else {
                switch s.kind {
                case .active: st.otherSeconds += d
                case .idle: st.idleSeconds += d
                case .away: st.awaySeconds += d
                }
            }
            if s.kind == .active {
                st.byApp[s.app.isEmpty ? "Неизвестно" : s.app, default: 0] += d
                if let dom = s.domain { st.byDomain[dom, default: 0] += d }
            }
        }
        return st
    }
}
