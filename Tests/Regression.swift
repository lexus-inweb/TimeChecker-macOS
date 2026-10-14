import Foundation

// Сценарии из внешнего код-ревью v1.0.0 (5 ошибок) и соседние пограничные случаи.

func runRegressionTests() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }
    func engine() -> TrackerEngine { let e = TrackerEngine(idleThreshold: 180); e.calendar = cal; return e }
    func total(_ list: [Session], _ kind: SessionKind) -> TimeInterval { list.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration } }
    func onlyDay(_ list: [Session], _ day: Int) -> Bool {
        list.allSatisfy { $0.start >= date(day) && $0.end <= date(day + 1) }
    }
    let page = ActivitySnapshot(app: "Google Chrome", bundleId: "com.google.Chrome", title: "Page A", url: "https://ti.ua")

    // 1. Пауза через полночь не смешивает дни
    do {
        let e = engine()
        e.tick(now: date(14, 23, 59, 50), idleSeconds: 0, snapshot: page, away: false)
        e.tick(now: date(14, 23, 59, 55), idleSeconds: 0, snapshot: page, away: false)
        let atPause = e.stop(at: date(14, 23, 59, 55))
        let finished = e.tick(now: date(15, 0, 0, 5), idleSeconds: 0, snapshot: page, away: false)
        check(atPause.isEmpty && finished.count == 1 && finished[0].day == date(14) && total(finished[0].sessions, .active) == 5,
              "ревью 1: пауза через полночь закрывает вчерашний день")
        check(e.day == date(15) && onlyDay(e.sessions, 15) && total(e.sessions, .away) == 0,
              "ревью 1: в сегодняшнем массиве нет вчерашних отрезков, пауза не стала отлучкой")
    }
    do { // пауза на всю ночь, тиков нет — смена дня через rollover
        let e = engine()
        e.tick(now: date(14, 22), idleSeconds: 0, snapshot: page, away: false)
        e.tick(now: date(14, 22, 0, 10), idleSeconds: 0, snapshot: page, away: false)
        e.stop(at: date(14, 22, 0, 10))
        check(e.rollover(at: date(14, 23)).isEmpty, "пауза: до полуночи день не закрывается")
        let finished = e.rollover(at: date(15, 8))
        check(finished.count == 1 && finished[0].day == date(14) && e.sessions.isEmpty && e.day == date(15),
              "пауза: после полуночи вчерашний день уходит в свой файл, сегодня пусто")
    }
    do { // выход из приложения после полуночи во время паузы
        let e = engine()
        e.tick(now: date(14, 23, 0), idleSeconds: 0, snapshot: page, away: false)
        e.tick(now: date(14, 23, 0, 5), idleSeconds: 0, snapshot: page, away: false)
        e.stop(at: date(14, 23, 0, 5))
        let onQuit = e.stop(at: date(15, 0, 10))
        check(onQuit.count == 1 && onQuit[0].day == date(14) && e.dayLogs().count == 1 && e.dayLogs()[0].day == date(15),
              "пауза: выход после полуночи сохраняет вчерашнее под вчерашней датой")
    }

    // 2. Многодневный сон режется по каждой полуночи
    do {
        let e = engine()
        e.tick(now: date(14, 22), idleSeconds: 0, snapshot: page, away: false)
        e.tick(now: date(14, 22, 0, 1), idleSeconds: 0, snapshot: page, away: false)
        let finished = e.tick(now: date(16, 9), idleSeconds: 0, snapshot: page, away: false)
        check(finished.map(\.day) == [date(14), date(15)], "ревью 2: сон 14→16 закрывает два дня")
        check(onlyDay(finished[0].sessions, 14) && onlyDay(finished[1].sessions, 15), "ревью 2: каждый отрезок лежит в своём дне")
        check(total(finished[1].sessions, .away) == 86400, "ревью 2: 15-е целиком — отлучка 24 ч")
        check(e.day == date(16) && onlyDay(e.sessions, 16) && total(e.sessions, .away) == 9 * 3600,
              "ревью 2: 16-е — отлучка до 9:00, дальше работа")
    }
    do { // сон через одну полночь
        let e = engine()
        e.tick(now: date(14, 23, 50), idleSeconds: 0, snapshot: page, away: false)
        e.tick(now: date(14, 23, 50, 1), idleSeconds: 0, snapshot: page, away: false)
        let finished = e.tick(now: date(15, 8), idleSeconds: 0, snapshot: page, away: false)
        check(finished.count == 1 && total(finished[0].sessions, .away) == 599 && total(e.sessions, .away) == 8 * 3600,
              "сон через полночь: отлучка поделена между днями")
    }

    // 3. Простой задним числом покрывает всё после последнего ввода
    do {
        let e = engine()
        let start = date(14, 10)
        for i in 0...300 {
            var snap = page
            if i >= 150 { snap.title = "Page B" }
            e.tick(now: start.addingTimeInterval(Double(i)), idleSeconds: Double(max(0, i - 100)), snapshot: snap, away: false)
        }
        check(total(e.sessions, .active) == 100 && total(e.sessions, .idle) == 200 && e.current?.kind == .idle,
              "ревью 3: смена заголовка без ввода → 100 с работы + 200 с простоя")
    }
    do { // явная отлучка посреди такого простоя сохраняется
        let e = engine()
        let start = date(14, 10)
        for i in 0...300 {
            var snap = page
            if i >= 150 { snap.title = "Page B" }
            e.tick(now: start.addingTimeInterval(Double(i)), idleSeconds: Double(max(0, i - 100)), snapshot: snap, away: (160..<170).contains(i))
        }
        check(total(e.sessions, .active) == 100 && total(e.sessions, .away) == 10 && total(e.sessions, .idle) == 190,
              "простой задним числом не трогает отлучку")
    }
    do { // простой, начавшийся до полуночи, — день не закрывается, пока это не ясно
        let e = engine()
        let t0 = date(14, 23, 58)
        var finished: [DayLog] = []
        for i in 0...240 { // ввод последний раз в 23:59:00, заголовок сменился в 23:59:30, порог 3 мин
            var snap = page
            if i >= 90 { snap.title = "Page B" }
            let out = e.tick(now: t0.addingTimeInterval(Double(i)), idleSeconds: Double(max(0, i - 60)), snapshot: snap, away: false)
            if !out.isEmpty { check(finished.isEmpty && i == 240, "простой через полночь: день закрыт ровно когда простой стал ясен"); finished = out }
        }
        check(finished.count == 1 && total(finished[0].sessions, .active) == 60 && total(finished[0].sessions, .idle) == 60,
              "простой через полночь: вчера 1 мин работы + 1 мин простоя")
        check(onlyDay(e.sessions, 15) && total(e.sessions, .idle) == 120 && total(e.sessions, .active) == 0,
              "простой через полночь: сегодня 2 мин простоя и ни секунды «работы»")
    }
    do { // ввод после полуночи сразу закрывает вчерашний день
        let e = engine()
        e.tick(now: date(14, 23, 59, 50), idleSeconds: 0, snapshot: page, away: false)
        let waiting = e.tick(now: date(15, 0, 0, 5), idleSeconds: 15, snapshot: page, away: false)
        let done = e.tick(now: date(15, 0, 0, 6), idleSeconds: 0, snapshot: page, away: false)
        check(waiting.isEmpty && done.count == 1 && total(done[0].sessions, .active) == 10 && total(e.sessions, .active) == 6,
              "полночь: вчерашний день ждёт ясности и закрывается на первом вводе")
        check(e.dayLogs().count == 1, "полночь: после закрытия в памяти только сегодня")
    }

    // 4. Домен в заголовке — с границами домена
    do {
        let p = Project(name: "TI", domains: ["ti.ua"])
        func cls(_ title: String, _ url: String? = nil) -> UUID? {
            Classifier.projectId(for: Session(start: date(14, 10), end: date(14, 10, 1), app: "Google Chrome",
                                              bundleId: "com.google.Chrome", title: title, url: url), projects: [p])
        }
        check(cls("notti.ua - Google Chrome", "https://notti.ua") == nil, "ревью 4: ti.ua не ловит notti.ua в заголовке")
        check(cls("shop.ti.ua — админка") == p.id && cls("Отчёт www.ti.ua") == p.id && cls("ti.ua — Search Console") == p.id,
              "домен в заголовке: поддомен, www и сам домен ловятся")
        check(cls("ti.uax — что-то") == nil && cls("multi.ua") == nil, "домен в заголовке: чужая зона и чужое имя не ловятся")
        check(Domain.candidates(in: "Отчёт.pdf и shop.ti.ua, notti.ua.") == ["отчёт.pdf", "shop.ti.ua", "notti.ua"],
              "домен в заголовке: выделение доменов из текста")
    }

    // Быстрая обрезка хвоста браузера и кэш разбора заголовков (нагрузка CPU при открытом окне)
    do {
        check(Report.stripBrowserTail("Inbox - Arc") == "Inbox" && Report.stripBrowserTail("Notes - Archive") == "Notes - Archive",
              "хвост: имя браузера в конце строки и не-браузер с тем же началом")
        check(Report.stripBrowserTail("A - B - Google Chrome – Work") == "A - B" && Report.stripBrowserTail("Docs | Safari") == "Docs",
              "хвост: дефисы внутри заголовка остаются, отрезается только браузер")
        check(Report.stripBrowserTail("Очень длинный заголовок без браузера — совсем") == "Очень длинный заголовок без браузера — совсем",
              "хвост: заголовок без браузера не меняется")
        let a = TitleIndex.parse("Аудит ti.ua — ТЕХНОЇЖАК - Google Chrome – Work (example.com)")
        let b = TitleIndex.parse("Аудит ti.ua — ТЕХНОЇЖАК - Google Chrome – Work (example.com)")
        check(a.text == "аудит ti.ua — техноїжак", "кэш: заголовок разобран без хвоста браузера, в нижнем регистре")
        check(a.domains == ["ti.ua"] && a.domains == b.domains && a.lookalike == b.lookalike && !a.text.contains("example.com"),
              "кэш: повторный разбор совпадает, домен профиля не попал")
        check(TitleIndex.keyword("  CEO ").plain == "ceo" && TitleIndex.keyword("СЕО").lookalike == TitleIndex.keyword("CEO").lookalike,
              "кэш: фразы правил нормализуются так же, как раньше")
    }

    // 5. Адрес вкладки: обновление, повтор при ошибке, отброс ответа про другую вкладку
    do {
        var p = URLCachePolicy()
        let t = date(14, 10)
        let key = "com.google.Chrome|Login - Google Chrome – Work"
        let win = "Login - Google Chrome – Work"
        var r = p.lookup(key: key, now: t)
        check(r.url == nil && r.requestId != nil, "адрес: новое окно — сразу запрос")
        p.complete(requestId: r.requestId!, url: "https://client-a.example/login", tabTitle: "Login", windowTitle: win, now: t)
        r = p.lookup(key: key, now: t.addingTimeInterval(1))
        check(r.url == "https://client-a.example/login" && r.requestId == nil, "адрес: свежий кэш без лишних запросов")
        // переключились на вкладку другого сайта с тем же заголовком
        r = p.lookup(key: key, now: t.addingTimeInterval(3))
        check(r.requestId != nil, "ревью 5: при том же заголовке адрес перечитывается по таймеру")
        p.complete(requestId: r.requestId!, url: "https://client-b.example/login", tabTitle: "Login", windowTitle: win, now: t.addingTimeInterval(3))
        check(p.lookup(key: key, now: t.addingTimeInterval(4)).url == "https://client-b.example/login",
              "ревью 5: две вкладки с одинаковым заголовком получают свои адреса")

        // ошибка запроса — повтор через интервал, а не вечный nil
        var q = URLCachePolicy()
        let id1 = q.lookup(key: "k", now: t).requestId!
        q.complete(requestId: id1, url: nil, tabTitle: nil, windowTitle: "", now: t)
        check(q.lookup(key: "k", now: t.addingTimeInterval(1)).requestId == nil && q.lookup(key: "k", now: t.addingTimeInterval(3)).requestId != nil,
              "адрес: неудачный запрос повторяется через интервал")

        // пока запрос висит (диалог «Автоматизация») — второй не запускаем
        var w = URLCachePolicy()
        let first = w.lookup(key: "A", now: t).requestId!
        check(w.lookup(key: "B", now: t.addingTimeInterval(5)).requestId == nil, "адрес: одновременно только один запрос")
        // ответ пришёл, но браузер уже показывал другую вкладку — не кэшируем как адрес окна A
        w.complete(requestId: first, url: "https://b.example", tabTitle: "B page", windowTitle: "A page - Google Chrome", now: t.addingTimeInterval(5))
        check(w.entry?.key == "A" && w.entry?.url == nil, "адрес: ответ про другую вкладку отброшен")
        check(w.lookup(key: "B", now: t.addingTimeInterval(5)).requestId != nil, "адрес: для нового окна сразу новый запрос")
        w.complete(requestId: first, url: "https://late.example", tabTitle: nil, windowTitle: "", now: t.addingTimeInterval(6))
        check(w.pending != nil && w.entry?.url == nil, "адрес: запоздавший ответ на старый запрос игнорируется")
        check(URLCachePolicy.tabMatches(tabTitle: "Хроника / inweb", windowTitle: "Хроника / inweb - Google Chrome – Work (example.com)") &&
              URLCachePolicy.tabMatches(tabTitle: nil, windowTitle: "x") && URLCachePolicy.tabMatches(tabTitle: "a", windowTitle: ""),
              "адрес: сверка вкладки с окном")
    }
}
