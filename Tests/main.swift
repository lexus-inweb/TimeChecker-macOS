import Foundation

// Простой раннер без XCTest (работает с Command Line Tools, без Xcode).
var passed = 0, failed = 0
func check(_ cond: @autoclosure () -> Bool, _ name: String, file: String = #file, line: Int = #line) {
    if cond() { passed += 1 } else { failed += 1; print("FAIL [\(line)] \(name)") }
}

let t0 = ISO8601DateFormatter().date(from: "2026-10-14T10:00:00Z")!
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
func sess(_ start: TimeInterval, _ end: TimeInterval, app: String = "Google Chrome", bundle: String = "com.google.Chrome",
          title: String = "", url: String? = nil, kind: SessionKind = .active, pid: UUID? = nil) -> Session {
    Session(start: at(start), end: at(end), kind: kind, app: app, bundleId: bundle, title: title, url: url, projectId: pid)
}

// MARK: Domain
check(Domain.from(url: "https://www.Shop.Ti.ua/path?q=1") == "shop.ti.ua", "domain: www и регистр")
check(Domain.from(url: "chrome://newtab") == nil, "domain: служебные схемы")
check(Domain.from(url: "file:///Users/x.pdf") == nil, "domain: file")
check(Domain.normalizeRule(" https://www.ti.ua/catalog ") == "ti.ua", "rule: нормализация")
check(Domain.matches("shop.ti.ua", rule: "ti.ua"), "rule: поддомен")
check(!Domain.matches("notti.ua", rule: "ti.ua"), "rule: не ловит чужой домен с тем же хвостом")
check(!Domain.matches("ti.ua", rule: ""), "rule: пустое правило")

// MARK: Classifier
let ti = Project(name: "Техноїжак", domains: ["ti.ua"], keywords: ["техноїжак"])
let figma = Project(name: "Дизайн", apps: ["Figma"])
let pf = Project(name: "Планфикс", keywords: ["planfix"])
let archived = Project(name: "Старый", domains: ["old.com"], archived: true)
let projects = [ti, figma, pf, archived]

check(Classifier.projectId(for: sess(0, 60, url: "https://ti.ua/x"), projects: projects) == ti.id, "cls: по домену")
check(Classifier.projectId(for: sess(0, 60, title: "Аудит ТЕХНОЇЖАК — Google Docs"), projects: projects) == ti.id, "cls: по фразе без учёта регистра")
check(Classifier.projectId(for: sess(0, 60, title: "ti.ua — Search Console"), projects: projects) == ti.id, "cls: домен в заголовке")
check(Classifier.projectId(for: sess(0, 60, app: "Figma", bundle: "com.figma.Desktop", title: "Макет"), projects: projects) == figma.id, "cls: по приложению")
check(Classifier.projectId(for: sess(0, 60, url: "https://inweb.planfix.ua/task/1"), projects: projects) == pf.id, "cls: фраза в адресе")
check(Classifier.projectId(for: sess(0, 60, url: "https://old.com"), projects: projects) == nil, "cls: архивный проект не ловит")
check(Classifier.projectId(for: sess(0, 60, url: "https://youtube.com"), projects: projects) == nil, "cls: неизвестное → Другое")
check(Classifier.projectId(for: sess(0, 60, url: "https://youtube.com", pid: figma.id), projects: projects) == figma.id, "cls: ручное отнесение важнее")
check(Classifier.projectId(for: sess(0, 60, kind: .idle), projects: projects) == nil, "cls: простой не классифицируется")
check(Classifier.projectId(for: sess(0, 60, kind: .idle, pid: ti.id), projects: projects) == ti.id, "cls: простой можно отнести вручную")
check(Classifier.projectId(for: sess(0, 60, pid: UUID()), projects: projects) == nil, "cls: удалённый проект")

check(Report.stripBrowserTail("Хроника / inweb - Google Chrome – Work (example.com)") == "Хроника / inweb", "tail: хвост Chrome с профилем")
check(Report.stripBrowserTail("Notes - Archive") == "Notes - Archive", "tail: Arc только целым словом")
check(Report.stripBrowserTail("Inbox — Safari") == "Inbox", "tail: Safari")
do {
    let work = Project(name: "Work", domains: ["example.com"], keywords: ["work"])
    let chromeTitle = sess(0, 60, title: "Хроника / inweb - Google Chrome – Work (example.com)", url: "https://inweb.planfix.com/x")
    check(Classifier.projectId(for: chromeTitle, projects: [work]) == nil, "cls: профиль Chrome в заголовке не ловится правилами")
}

// MARK: Report
check(Report.roundMinutes(30, step: 5) == 0, "round: < минуты = 0")
check(Report.roundMinutes(61, step: 5) == 5, "round: минимум один шаг")
check(Report.roundMinutes(7 * 60 + 40, step: 5) == 10, "round: 7.7 → 10")
check(Report.roundMinutes(7 * 60, step: 5) == 5, "round: 7 → 5")
check(Report.roundMinutes(83 * 60, step: 1) == 83, "round: шаг 1")
check(Report.format(minutes: 85) == "1 ч 25 мин", "format: ч+мин")
check(Report.format(minutes: 120) == "2 ч", "format: ровно часы")
check(Report.format(minutes: 5) == "5 мин", "format: минуты")
check(Report.cleanTitle("(3) Аудит сайта - Google Chrome", app: "Google Chrome") == "Аудит сайта", "clean: счётчик и браузер")
check(Report.cleanTitle("Задача 12 — Планфикс - user@example.com - Google Chrome", app: "Google Chrome") == "Задача 12 — Планфикс", "clean: почта")
check(Report.cleanTitle("Хроника / inweb - Google Chrome – Work (example.com)", app: "Google Chrome") == "Хроника / inweb", "clean: профиль Chrome")
check(Report.cleanTitle("Telegram", app: "Telegram") == "", "clean: только имя приложения")

let daySessions = [
    sess(0, 1800, title: "Аудит сайта - Google Chrome", url: "https://ti.ua/a"),
    sess(1800, 2400, title: "Техноїжак: план — Google Docs", url: "https://docs.google.com/x"),
    sess(2400, 2430, title: "Короткое", url: "https://ti.ua/b"),
    sess(2430, 3000, app: "Figma", bundle: "com.figma.Desktop", title: "Макет главной"),
    sess(3000, 4000, title: "YouTube", url: "https://youtube.com"),
    sess(4000, 4500, kind: .idle),
]
let settings = AppSettings()
let lines = Report.build(sessions: daySessions, projects: projects, settings: settings)
check(lines.count == 2, "report: два проекта")
check(lines.first?.projectId == ti.id && lines.first?.minutes == 40, "report: Техноїжак 40.5 мин → 40")
check(lines.first?.comment == "Аудит сайта; Техноїжак: план — Google Docs", "report: комментарий по весу, без коротких")
check(lines.last?.minutes == 10, "report: Figma 9.5 мин → 10")
let txt = Report.text(lines, comments: [figma.id: "Правки макета"])
check(txt.contains("Техноїжак — 40 мин\nАудит сайта") && txt.hasSuffix("Дизайн — 10 мин\nПравки макета"), "report: текст и ручной комментарий")

// MARK: Grouping & Stats
let other = Grouping.unclassified(daySessions, projects: projects, includeIdle: true)
check(other.count == 2, "other: youtube + простой")
check(Grouping.unclassified(daySessions, projects: projects, includeIdle: false).count == 1, "other: без простоя")
let chrono = Grouping.chronological([
    sess(0, 60, title: "A", url: "https://youtube.com/1"), sess(60, 120, title: "B", url: "https://youtube.com/2"),
    sess(120, 180, app: "Telegram", bundle: "tg", title: "Чат"), sess(500, 560, title: "C", url: "https://youtube.com/3"),
])
check(chrono.count == 3 && chrono[0].sessionIds.count == 2 && chrono[0].detail == "A · B", "chrono: склейка подряд идущих")
let byApp = Grouping.byApp([sess(0, 60, url: "https://youtube.com/1"), sess(100, 400, url: "https://youtube.com/2"), sess(60, 100, app: "Telegram", bundle: "tg")])
check(byApp.count == 2 && byApp[0].label == "youtube.com" && byApp[0].seconds == 360, "byApp: группировка по сайту")
let st = Stats.build(daySessions, projects: projects)
check(st.projectSeconds[ti.id] == 2430 && st.otherSeconds == 1000 && st.idleSeconds == 500, "stats: итоги")
check(st.byDomain["youtube.com"] == 1000 && st.byApp["Figma"] == 570, "stats: по сайтам и приложениям")

// MARK: Engine
let chrome = ActivitySnapshot(app: "Google Chrome", bundleId: "com.google.Chrome", title: "ti.ua", url: "https://ti.ua")
let tg = ActivitySnapshot(app: "Telegram", bundleId: "ru.keepcoder.Telegram", title: "Чат", url: nil)
do {
    let e = TrackerEngine(idleThreshold: 180)
    for i in 0...10 { e.tick(now: at(Double(i)), idleSeconds: 0, snapshot: chrome, away: false) }
    for i in 11...20 { e.tick(now: at(Double(i)), idleSeconds: 0, snapshot: tg, away: false) }
    check(e.sessions.count == 2 && e.sessions[0].duration == 11 && e.sessions[1].app == "Telegram", "engine: смена окна режет отрезок")
}
do {
    let e = TrackerEngine(idleThreshold: 180)
    for i in 0...300 { e.tick(now: at(Double(i)), idleSeconds: Double(max(0, i - 100)), snapshot: chrome, away: false) }
    // последний ввод был на 100-й секунде, порог 180 → простой с 100 до 300
    check(e.sessions.count == 2, "engine: активность + простой")
    check(e.sessions[0].end == at(100) && e.sessions[1].kind == .idle && e.sessions[1].start == at(100) && e.sessions[1].end == at(300), "engine: простой задним числом с последнего ввода")
    e.tick(now: at(301), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(302), idleSeconds: 0, snapshot: chrome, away: false)
    check(e.sessions.count == 3 && e.sessions[2].kind == .active, "engine: возврат из простоя")
}
do {
    let e = TrackerEngine(idleThreshold: 180)
    e.tick(now: at(0), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(10), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(3610), idleSeconds: 0, snapshot: chrome, away: false)
    check(e.sessions.count == 3 && e.sessions[1].kind == .away && e.sessions[1].duration == 3600, "engine: сон по разрыву тиков")
}
do {
    let e = TrackerEngine(idleThreshold: 180)
    e.tick(now: at(0), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(5), idleSeconds: 0, snapshot: chrome, away: true)
    e.tick(now: at(65), idleSeconds: 0, snapshot: chrome, away: true)
    check(e.sessions.count == 2 && e.sessions[1].kind == .away && e.sessions[1].duration == 60, "engine: блокировка экрана")
}
do {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let e = TrackerEngine(idleThreshold: 180); e.calendar = cal
    let beforeMidnight = ISO8601DateFormatter().date(from: "2026-10-14T23:59:58Z")!
    e.tick(now: beforeMidnight, idleSeconds: 0, snapshot: chrome, away: false)
    let r1 = e.tick(now: beforeMidnight.addingTimeInterval(1), idleSeconds: 0, snapshot: chrome, away: false)
    let finished = e.tick(now: beforeMidnight.addingTimeInterval(4), idleSeconds: 0, snapshot: chrome, away: false)
    check(r1 == nil && finished?.count == 1 && finished?[0].duration == 2, "engine: полночь закрывает вчерашний день")
    check(e.sessions.count == 1 && e.sessions[0].duration == 2 && e.sessions[0].app == "Google Chrome", "engine: отрезок продолжается после полуночи")
}
do {
    let e = TrackerEngine(idleThreshold: 180)
    e.tick(now: at(0), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(0.4), idleSeconds: 0, snapshot: tg, away: false)
    e.tick(now: at(10), idleSeconds: 0, snapshot: tg, away: false)
    check(e.sessions.count == 1 && e.sessions[0].app == "Telegram", "engine: отрезки < 1 сек отбрасываются")
    var copy = e.sessions; copy[0].projectId = ti.id
    e.replaceSessions(copy)
    e.tick(now: at(12), idleSeconds: 0, snapshot: tg, away: false)
    check(e.sessions.count == 1 && e.sessions[0].projectId == ti.id && e.sessions[0].end == at(12), "engine: ручной перенос не рвёт текущий отрезок")
}

do {
    let e = TrackerEngine(idleThreshold: 180)
    var noUrl = chrome; noUrl.url = nil
    e.tick(now: at(0), idleSeconds: 0, snapshot: noUrl, away: false)
    e.tick(now: at(1), idleSeconds: 0, snapshot: chrome, away: false)
    e.tick(now: at(2), idleSeconds: 0, snapshot: chrome, away: false)
    check(e.sessions.count == 1 && e.sessions[0].url == "https://ti.ua" && e.sessions[0].duration == 2, "engine: запоздавший адрес дописывается в отрезок")
}

do {
    let e = TrackerEngine(idleThreshold: 180)
    e.tick(now: at(1000), idleSeconds: 600, snapshot: chrome, away: false)
    e.tick(now: at(1001), idleSeconds: 601, snapshot: chrome, away: false)
    check(e.sessions.count == 1 && e.sessions[0].start == at(1000), "engine: простой не уходит раньше запуска трекера")
}

// MARK: Store
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tc-test-\(UUID())")
    let store = FileStore(dir: dir)
    store.saveDay(t0, daySessions); store.saveProjects(projects)
    check(store.loadDay(t0) == daySessions, "store: день туда-обратно")
    check(store.loadProjects() == projects, "store: проекты туда-обратно")
    try? #"{"idleMinutes": 7}"#.data(using: .utf8)!.write(to: dir.appendingPathComponent("settings.json"))
    check(store.loadSettings().idleMinutes == 7 && store.loadSettings().roundingMinutes == 5, "store: старые настройки без новых полей")
    try? FileManager.default.removeItem(at: dir)
}

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
