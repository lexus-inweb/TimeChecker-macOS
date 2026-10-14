import Foundation

/// Отрезки одного календарного дня — то, что ложится в days/<дата>.json.
struct DayLog: Equatable {
    var day: Date
    var sessions: [Session]
}

/// Чистая логика трекера: получает «что сейчас на экране» раз в секунду и режет время на отрезки.
/// Ничего не знает про AppKit — поэтому покрыта тестами.
///
/// Граница дня: массив `sessions` начинается в дне `day` и может временно залезать за полночь —
/// пока не ясно, не окажется ли время после последнего ввода простоем (максимум `idleThreshold`).
/// Как только ясно, массив режется по каждой пройденной полуночи и готовые дни отдаются наружу.
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
    private var dayStart: Date?

    init(sessions: [Session] = [], day: Date? = nil, idleThreshold: TimeInterval = 180) {
        self.sessions = sessions
        self.idleThreshold = idleThreshold
        if let d = day ?? sessions.first?.start { dayStart = Calendar.current.startOfDay(for: d) }
    }

    /// Начало дня, к которому относится массив `sessions`.
    var day: Date { dayStart ?? calendar.startOfDay(for: sessions.first?.start ?? Date()) }

    var current: Session? { currentIndex.map { sessions[$0] } }

    /// Один тик. Возвращает дни, которые этим тиком закрылись (после многодневного сна — несколько).
    @discardableResult
    func tick(now: Date, idleSeconds: TimeInterval, snapshot: ActivitySnapshot?, away: Bool) -> [DayLog] {
        var finished: [DayLog] = []
        if sessions.isEmpty && currentIndex == nil { dayStart = calendar.startOfDay(for: now) }

        if lastTick == nil {
            // Запуск или продолжение после паузы: пропущенные полуночи закрываем без отлучек — пауза не считается.
            finished += settle(now: now, idleSeconds: 0, force: true)
            trackingSince = now
        } else if let last = lastTick, now.timeIntervalSince(last) > gapThreshold, current?.kind != .away {
            closeCurrent(at: last)
            append(Session(start: last, end: now, kind: .away)) // по дням его разрежет settle
        }
        lastTick = now

        if away {
            continueOrStart(kind: .away, snapshot: nil, from: now, now: now)
        } else if idleSeconds >= idleThreshold {
            let idleStart = max(now.addingTimeInterval(-idleSeconds), trackingSince ?? .distantPast)
            // Заголовок мог меняться и без ввода (обновилась страница, пришло сообщение) —
            // всё активное после последнего ввода задним числом становится простоем.
            reclassifyAsIdle(after: idleStart)
            continueOrStart(kind: .idle, snapshot: nil, from: max(idleStart, sessions.last?.end ?? idleStart), now: now)
        } else if let snap = snapshot {
            continueOrStart(kind: .active, snapshot: snap, from: now, now: now)
        } else {
            continueOrStart(kind: .away, snapshot: nil, from: now, now: now)
        }

        finished += settle(now: now, idleSeconds: idleSeconds, force: false)
        return finished
    }

    /// Пауза/выход: закрыть текущий отрезок и все дни, которые уже кончились.
    @discardableResult
    func stop(at now: Date) -> [DayLog] {
        closeCurrent(at: now)
        lastTick = nil
        return settle(now: now, idleSeconds: 0, force: true)
    }

    /// Смена дня, пока трекер стоит на паузе (тики не идут, а «сегодня» должно стать новым днём).
    @discardableResult
    func rollover(at now: Date) -> [DayLog] {
        guard lastTick == nil else { return [] }
        let out = settle(now: now, idleSeconds: 0, force: true)
        if sessions.isEmpty { dayStart = calendar.startOfDay(for: now) }
        return out
    }

    /// Текущий массив, разрезанный по дням, без изменения состояния — для сохранения и интерфейса.
    func dayLogs() -> [DayLog] {
        var rest = sessions, d = day, out: [DayLog] = []
        while let boundary = calendar.date(byAdding: .day, value: 1, to: d), rest.contains(where: { $0.end > boundary }) {
            let (left, right) = Self.split(rest, at: boundary)
            out.append(DayLog(day: d, sessions: left))
            rest = right; d = boundary
        }
        out.append(DayLog(day: d, sessions: rest))
        return out
    }

    /// Ручное отнесение к проекту (nil — вернуть на автоматические правила). Текущий отрезок не рвётся.
    func assign(_ ids: Set<UUID>, to projectId: UUID?) {
        for i in sessions.indices where ids.contains(sessions[i].id) { sessions[i].projectId = projectId }
    }

    /// Режет отрезки по границе. Отрезок, пересекающий её, делится на два с тем же id —
    /// это одно занятие, просто записанное в два дня.
    static func split(_ list: [Session], at boundary: Date) -> (left: [Session], right: [Session]) {
        var left: [Session] = [], right: [Session] = []
        for s in list {
            if s.end <= boundary { left.append(s) }
            else if s.start >= boundary { right.append(s) }
            else {
                var a = s; a.end = boundary; left.append(a)
                var b = s; b.start = boundary; right.append(b)
            }
        }
        return (left, right)
    }

    // MARK: - private

    /// Отрезает от массива все дни, которые уже кончились.
    /// Без force ждёт, пока не станет ясно, не съест ли простой задним числом время до полуночи.
    private func settle(now: Date, idleSeconds: TimeInterval, force: Bool) -> [DayLog] {
        var out: [DayLog] = []
        while let boundary = calendar.date(byAdding: .day, value: 1, to: day), now >= boundary {
            if !force {
                let lastInput = now.addingTimeInterval(-idleSeconds)
                let undecided = idleSeconds < idleThreshold && lastInput < boundary &&
                    sessions.contains { $0.kind == .active && $0.end > lastInput }
                if undecided { break }
            }
            let currentId = current?.id
            let (left, right) = Self.split(sessions, at: boundary)
            out.append(DayLog(day: day, sessions: left))
            sessions = right
            currentIndex = currentId.flatMap { id in sessions.lastIndex { $0.id == id } }
            dayStart = boundary
        }
        return out
    }

    private func reclassifyAsIdle(after t: Date) {
        guard sessions.contains(where: { $0.kind == .active && $0.end > t }) else { return }
        let currentId = current?.id
        var out: [Session] = []
        var newCurrent: Int?
        for s in sessions {
            guard s.kind == .active, s.end > t else {
                out.append(s)
                if s.id == currentId { newCurrent = out.count - 1 }
                continue
            }
            if s.start < t { var a = s; a.end = t; out.append(a) }
            let idleStart = max(s.start, t)
            if let last = out.last, last.kind == .idle, last.projectId == nil, idleStart.timeIntervalSince(last.end) <= 1 {
                out[out.count - 1].end = max(last.end, s.end)
            } else {
                out.append(Session(start: idleStart, end: s.end, kind: .idle))
            }
            if s.id == currentId { newCurrent = out.count - 1 }
        }
        sessions = out
        currentIndex = newCurrent
    }

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
