import AppKit
import ServiceManagement
import SwiftUI

final class AppModel: ObservableObject {
    let store = FileStore(dir: FileStore.defaultDir)
    private let sensors = Sensors()
    private let engine: TrackerEngine
    private var timer: Timer?
    private var tickCount = 0
    private var dayCache: [String: [Session]] = [:]

    @Published private(set) var today: [Session] = []
    @Published var projects: [Project] { didSet { store.saveProjects(projects) } }
    @Published var settings: AppSettings {
        didSet { store.saveSettings(settings); engine.idleThreshold = TimeInterval(settings.idleMinutes * 60) }
    }
    @Published private(set) var comments: [String: [String: String]]
    @Published var paused = false
    @Published private(set) var axTrusted = Sensors.accessibilityTrusted
    @Published private(set) var current: Session?

    init() {
        let s = store.loadSettings()
        settings = s
        projects = store.loadProjects()
        comments = store.loadComments()
        engine = TrackerEngine(sessions: store.loadDay(Date()), idleThreshold: TimeInterval(s.idleMinutes * 60))
        today = engine.sessions

        if !axTrusted { Sensors.requestAccessibility() }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.engine.stop(at: Date())
            self.store.saveDay(Date(), self.engine.sessions)
        }
    }

    // MARK: - Трекинг

    private func tick() {
        tickCount += 1
        // @Published шлёт обновление на любое присваивание — пишем только реальные изменения,
        // иначе SwiftUI перерисовывает строку меню каждую секунду.
        if tickCount % 5 == 0 {
            let trusted = Sensors.accessibilityTrusted
            if trusted != axTrusted { axTrusted = trusted }
        }
        guard !paused else { return }
        let now = Date()
        let countBefore = engine.sessions.count
        let snap = sensors.away ? nil : sensors.snapshot()
        if let finished = engine.tick(now: now, idleSeconds: sensors.idleSeconds, snapshot: snap, away: sensors.away) {
            let yesterday = finished.first?.start ?? now.addingTimeInterval(-86400)
            store.saveDay(yesterday, finished)
            dayCache[FileStore.dayKey(yesterday)] = finished
        }
        let cur = engine.current
        if cur?.id != current?.id || cur?.kind != current?.kind { current = cur }
        if engine.sessions.count != countBefore || tickCount % 10 == 0 { today = engine.sessions }
        if tickCount % 15 == 0 { store.saveDay(now, engine.sessions) }
    }

    func togglePause() {
        paused.toggle()
        if paused { engine.stop(at: Date()); current = nil; today = engine.sessions; store.saveDay(Date(), engine.sessions) }
    }

    // MARK: - Данные по дням

    func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }

    func sessions(on day: Date) -> [Session] {
        if isToday(day) { return today }
        let key = FileStore.dayKey(day)
        if let c = dayCache[key] { return c }
        let s = store.loadDay(day)
        dayCache[key] = s
        return s
    }

    func sessions(from: Date, to: Date) -> [Session] {
        var out: [Session] = []
        var d = Calendar.current.startOfDay(for: from)
        while d <= to {
            out += sessions(on: d)
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    /// Перенести отрезки в проект (nil — вернуть на автоматические правила).
    func assign(_ ids: Set<UUID>, to projectId: UUID?, on day: Date) {
        var list = sessions(on: day)
        for i in list.indices where ids.contains(list[i].id) { list[i].projectId = projectId }
        if isToday(day) {
            engine.replaceSessions(list)
            today = engine.sessions
            store.saveDay(day, engine.sessions)
        } else {
            dayCache[FileStore.dayKey(day)] = list
            store.saveDay(day, list)
            objectWillChange.send()
        }
    }

    // MARK: - Отчёт

    func report(on day: Date) -> [ReportLine] {
        Report.build(sessions: sessions(on: day), projects: projects, settings: settings)
    }

    func comment(_ line: ReportLine, on day: Date) -> String {
        comments[FileStore.dayKey(day)]?[line.projectId.uuidString] ?? line.comment
    }

    func setComment(_ text: String, for line: ReportLine, on day: Date) {
        let key = FileStore.dayKey(day)
        var dayMap = comments[key] ?? [:]
        dayMap[line.projectId.uuidString] = text == line.comment ? nil : text
        comments[key] = dayMap.isEmpty ? nil : dayMap
        store.saveComments(comments)
    }

    func reportText(on day: Date) -> String {
        let lines = report(on: day)
        var edited: [UUID: String] = [:]
        for l in lines { edited[l.projectId] = comment(l, on: day) }
        return Report.text(lines, comments: edited)
    }

    func copyReport(on day: Date) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText(on: day), forType: .string)
    }

    // MARK: - Проекты и правила

    func project(_ id: UUID?) -> Project? { id.flatMap { id in projects.first { $0.id == id } } }

    @discardableResult
    func addProject(name: String) -> Project {
        let p = Project(name: name)
        projects.append(p)
        return p
    }

    func addRule(to projectId: UUID, domain: String? = nil, keyword: String? = nil, app: String? = nil) {
        guard let i = projects.firstIndex(where: { $0.id == projectId }) else { return }
        if let d = domain, !projects[i].domains.contains(d) { projects[i].domains.append(d) }
        if let k = keyword, !projects[i].keywords.contains(k) { projects[i].keywords.append(k) }
        if let a = app, !projects[i].apps.contains(a) { projects[i].apps.append(a) }
    }

    // MARK: - Системное

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { NSLog("Launch at login: \(error)") }
            objectWillChange.send()
        }
    }

    func openDataFolder() { NSWorkspace.shared.open(store.dir) }
}
