import Foundation

/// Чистая логика трекера: получает «что сейчас на экране» раз в секунду и режет время на отрезки.
/// Ничего не знает про AppKit — поэтому покрыта тестами.
final class TrackerEngine {
    private(set) var sessions: [Session]
    private(set) var currentIndex: Int?
    private(set) var lastTick: Date?
    /// Когда трекинг (пере)запустился — раньше этого момента простой не считаем.
    private(set) var trackingSince: Date?
    var idleThreshold: TimeInterval
    /// Если между тиками прошло больше — мак спал или процесс был приостановлен.
    var gapThreshold: TimeInterval = 30
    var calendar = Calendar.current

    init(sessions: [Session] = [], idleThreshold: TimeInterval = 180) {
        self.sessions = sessions
        self.idleThreshold = idleThreshold
    }

    var current: Session? { currentIndex.map { sessions[$0] } }

    /// Один тик. Возвращает сессии завершившегося дня, если перешли через полночь.
    @discardableResult
    func tick(now: Date, idleSeconds: TimeInterval, snapshot: ActivitySnapshot?, away: Bool) -> [Session]? {
        var finishedDay: [Session]? = nil

        if let last = lastTick, !calendar.isDate(last, inSameDayAs: now) {
            let midnight = calendar.startOfDay(for: now)
            let wasGap = now.timeIntervalSince(last) > gapThreshold
            let carry = current
            closeCurrent(at: wasGap ? last : midnight)
            if wasGap && midnight > last { append(Session(start: last, end: midnight, kind: .away)) }
            finishedDay = sessions
            sessions = []
            currentIndex = nil
            if wasGap {
                if now > midnight { append(Session(start: midnight, end: now, kind: .away)) }
            } else if var c = carry {
                c.id = UUID(); c.start = midnight; c.end = midnight; c.projectId = nil
                sessions.append(c); currentIndex = sessions.count - 1
            }
            lastTick = now
        } else if let last = lastTick, now.timeIntervalSince(last) > gapThreshold, current?.kind != .away {
            closeCurrent(at: last)
            append(Session(start: last, end: now, kind: .away))
        }
        if lastTick == nil { trackingSince = now }
        lastTick = now

        if away {
            continueOrStart(kind: .away, snapshot: nil, from: now, now: now)
            return finishedDay
        }

        if idleSeconds >= idleThreshold {
            let idleStart = now.addingTimeInterval(-idleSeconds)
            if let c = current, c.kind == .active {
                closeCurrent(at: max(c.start, idleStart))
            }
            continueOrStart(kind: .idle, snapshot: nil, from: max(idleStart, sessions.last?.end ?? idleStart, trackingSince ?? idleStart), now: now)
            return finishedDay
        }

        guard let snap = snapshot else {
            continueOrStart(kind: .away, snapshot: nil, from: now, now: now)
            return finishedDay
        }
        continueOrStart(kind: .active, snapshot: snap, from: now, now: now)
        return finishedDay
    }

    /// Пауза/выход: закрыть текущий отрезок.
    func stop(at now: Date) {
        closeCurrent(at: now)
        lastTick = nil
    }

    /// Заменить сессии (после ручного переноса в проект). Текущий отрезок сохраняет свою позицию по id.
    func replaceSessions(_ new: [Session]) {
        let currentId = current?.id
        sessions = new
        currentIndex = currentId.flatMap { id in sessions.firstIndex { $0.id == id } }
    }

    // MARK: - private

    private func same(_ s: Session, kind: SessionKind, snapshot: ActivitySnapshot?) -> Bool {
        guard s.kind == kind else { return false }
        guard kind == .active, let snap = snapshot else { return true }
        return s.bundleId == snap.bundleId && s.title == snap.title && s.url == snap.url
    }

    private func continueOrStart(kind: SessionKind, snapshot: ActivitySnapshot?, from: Date, now: Date) {
        if let i = currentIndex, same(sessions[i], kind: kind, snapshot: snapshot) {
            sessions[i].end = now
            return
        }
        // Адрес вкладки приходит из фона с опозданием на тик — дописываем его, а не режем отрезок.
        if let i = currentIndex, let snap = snapshot, kind == .active, sessions[i].kind == .active,
           sessions[i].bundleId == snap.bundleId, sessions[i].title == snap.title,
           sessions[i].url == nil, snap.url != nil {
            sessions[i].url = snap.url
            sessions[i].end = now
            return
        }
        closeCurrent(at: now)
        var s = Session(start: min(from, now), end: now, kind: kind)
        if let snap = snapshot {
            s.app = snap.app; s.bundleId = snap.bundleId; s.title = snap.title; s.url = snap.url
        }
        sessions.append(s)
        currentIndex = sessions.count - 1
    }

    private func closeCurrent(at date: Date) {
        guard let i = currentIndex else { return }
        sessions[i].end = max(sessions[i].start, date)
        currentIndex = nil
        if sessions[i].duration < 1 { sessions.remove(at: i) }
    }

    private func append(_ s: Session) {
        guard s.duration >= 1 else { return }
        sessions.append(s)
    }
}

// MARK: - Хранилище

/// Всё лежит локально: ~/Library/Application Support/TimeChecker/
/// days/2026-10-14.json — отрезки за день, projects.json, settings.json, comments.json
final class FileStore {
    let dir: URL
    private let enc: JSONEncoder
    private let dec: JSONDecoder

    init(dir: URL) {
        self.dir = dir
        enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("days"), withIntermediateDirectories: true)
    }

    static var defaultDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeChecker")
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func loadDay(_ date: Date) -> [Session] {
        load([Session].self, "days/\(Self.dayKey(date)).json") ?? []
    }

    func saveDay(_ date: Date, _ sessions: [Session]) {
        save(sessions, "days/\(Self.dayKey(date)).json")
    }

    func loadProjects() -> [Project] { load([Project].self, "projects.json") ?? [] }
    func saveProjects(_ p: [Project]) { save(p, "projects.json") }
    func loadSettings() -> AppSettings { load(AppSettings.self, "settings.json") ?? AppSettings() }
    func saveSettings(_ s: AppSettings) { save(s, "settings.json") }
    /// Отредактированные вручную комментарии: [день: [projectId: текст]]
    func loadComments() -> [String: [String: String]] { load([String: [String: String]].self, "comments.json") ?? [:] }
    func saveComments(_ c: [String: [String: String]]) { save(c, "comments.json") }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? dec.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}
