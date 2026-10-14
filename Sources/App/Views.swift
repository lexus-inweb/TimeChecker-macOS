import AppKit
import Charts
import SwiftUI

// MARK: - Общие кусочки

func hm(_ seconds: TimeInterval) -> String { Report.format(seconds: seconds) }

struct DayPicker: View {
    @Binding var day: Date
    var body: some View {
        HStack(spacing: 4) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            DatePicker("", selection: $day, displayedComponents: .date).labelsHidden().fixedSize()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(day))
            if !Calendar.current.isDateInToday(day) {
                Button("Сьогодні") { day = Date() }
            }
        }
    }
    private func shift(_ n: Int) { day = Calendar.current.date(byAdding: .day, value: n, to: day)! }
}

struct StatTile: View {
    var title: String
    var seconds: TimeInterval
    var tint: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(hm(seconds)).font(.title2.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}

struct BarRow: View {
    var label: String
    var seconds: TimeInterval
    var maxSeconds: TimeInterval
    var tint: Color = .accentColor
    var body: some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1).truncationMode(.middle).frame(width: 190, alignment: .leading)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 3).fill(tint.gradient)
                    .frame(width: max(2, g.size.width * CGFloat(maxSeconds > 0 ? seconds / maxSeconds : 0)))
            }
            .frame(height: 12)
            Text(hm(seconds)).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
        }
    }
}

struct EmptyHint: View {
    var title: String
    var text: String
    var icon: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccessWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Немає доступу до заголовків вікон").font(.callout.weight(.semibold))
                Text("Дозволь Time Checker у «Доступності», інакше видно лише програму, без назви вкладки.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Відкрити налаштування") { Sensors.openAccessibilitySettings() }.controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))
    }
}

// MARK: - Строка меню

struct MenuLabel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let secs = Stats.build(model.today, projects: model.projects).projectsTotal
        HStack(spacing: 3) {
            Image(systemName: model.paused ? "pause.circle" : "clock")
            Text(String(format: "%d:%02d", Int(secs) / 3600, Int(secs) / 60 % 60)).monospacedDigit()
        }
    }
}

struct MenuPopover: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Local private var copied = false

    var body: some View {
        let day = Date()
        let lines = model.report(on: day)
        let st = Stats.build(model.today, projects: model.projects)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Сьогодні").font(.headline)
                Spacer()
                Text("на проєкти \(hm(st.projectsTotal))").foregroundStyle(.secondary).monospacedDigit()
            }
            if !model.axTrusted { AccessWarning() }
            if let c = model.current {
                Label(nowText(c), systemImage: model.project(Classifier.projectId(for: c, projects: model.projects)) == nil ? "circle.dashed" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if model.paused {
                Label("Пауза — час не рахується", systemImage: "pause.circle").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            if lines.isEmpty {
                Text(model.projects.isEmpty ? "Додай проєкти й правила — тоді тут з'явиться звіт." : "Поки нічого не потрапило в проєкти.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(lines) { l in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(l.name).fontWeight(.medium).lineLimit(1)
                                    Spacer()
                                    Text(Report.format(minutes: l.minutes)).monospacedDigit()
                                }
                                let c = model.comment(l, on: day)
                                if !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            Divider()
            HStack {
                Text("Інше \(hm(st.otherSeconds))")
                Text("·").foregroundStyle(.tertiary)
                Text("Простій \(hm(st.idleSeconds))")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(copied ? "Скопійовано ✓" : "Копіювати звіт") {
                    model.copyReport(on: day); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(lines.isEmpty)
                Button("Відкрити…") { open() }
                Spacer()
                Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill") }
                    .help(model.paused ? "Продовжити" : "Пауза")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Вийти")
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func nowText(_ s: Session) -> String {
        switch s.kind {
        case .idle: return "Зараз: простій"
        case .away: return "Зараз: не за комп'ютером"
        case .active:
            let what = s.domain ?? (s.title.isEmpty ? s.app : s.title)
            return "Зараз: \(s.app) — \(what)"
        }
    }

    private func open() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Главное окно

enum MainTab: Hashable { case report, other, dashboard, projects, settings, help }

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @Local private var tab: MainTab = .report
    @Local private var day = Date()

    var body: some View {
        TabView(selection: $tab) {
            page(.report) { ReportView(day: $day, tab: $tab) }.tabItem { Label("Звіт", systemImage: "doc.text") }.tag(MainTab.report)
            page(.other) { OtherView(day: $day) }.tabItem { Label("Інше", systemImage: "tray") }.tag(MainTab.other)
            page(.dashboard) { DashboardView(day: $day) }.tabItem { Label("Дашборд", systemImage: "chart.bar") }.tag(MainTab.dashboard)
            page(.projects) { ProjectsView() }.tabItem { Label("Проєкти", systemImage: "folder") }.tag(MainTab.projects)
            page(.settings) { SettingsView() }.tabItem { Label("Налаштування", systemImage: "gearshape") }.tag(MainTab.settings)
            page(.help) { HelpView() }.tabItem { Label("Довідка", systemImage: "questionmark.circle") }.tag(MainTab.help)
        }
        .padding(.top, 4)
    }

    /// TabView на Mac пересчитывает все вкладки при каждом обновлении модели — и «Другое», и дашборд
    /// за месяц, даже когда открыты «Настройки». Считаем только открытую.
    @ViewBuilder
    private func page<Content: View>(_ t: MainTab, @ViewBuilder _ content: () -> Content) -> some View {
        if tab == t { content() } else { Color.clear }
    }
}

// MARK: Отчёт

struct ReportView: View {
    @EnvironmentObject var model: AppModel
    @Binding var day: Date
    @Binding var tab: MainTab
    @Local private var copied = false

    var body: some View {
        let lines = model.report(on: day)
        let st = Stats.build(model.sessions(on: day), projects: model.projects)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DayPicker(day: $day)
                Spacer()
                Button(copied ? "Скопійовано ✓" : "Копіювати звіт") {
                    model.copyReport(on: day); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                .disabled(lines.isEmpty)
            }
            if !model.axTrusted { AccessWarning() }
            HStack(spacing: 10) {
                StatTile(title: "На проєкти", seconds: st.projectsTotal)
                StatTile(title: "Інше", seconds: st.otherSeconds, tint: .orange)
                StatTile(title: "Простій", seconds: st.idleSeconds, tint: .secondary)
                StatTile(title: "Відлучки / сон", seconds: st.awaySeconds, tint: .secondary)
            }
            if lines.isEmpty {
                EmptyHint(title: "Звіт порожній",
                          text: model.projects.isEmpty
                            ? "Створи проєкти на вкладці «Проєкти» й додай правила: домени, фрази із заголовків, програми."
                            : "За цей день нічого не потрапило в проєкти. Зазирни в «Інше» — звідти час переноситься в проєкт.",
                          icon: "doc.text.magnifyingglass")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(lines) { l in ReportCard(line: l, day: day) }
                    }
                }
            }
            if st.otherSeconds >= 60 {
                Button("Нерозподілено \(hm(st.otherSeconds)) — розібрати в «Іншому» →") { tab = .other }
                    .buttonStyle(.link)
            }
        }
        .padding()
    }
}

struct ReportCard: View {
    @EnvironmentObject var model: AppModel
    var line: ReportLine
    var day: Date
    @Local private var showSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(line.name).font(.headline)
                Spacer()
                Text(Report.format(minutes: line.minutes)).font(.headline).monospacedDigit()
                Text("(\(hm(line.seconds)) факт)").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Коментар", text: Binding(
                get: { model.comment(line, on: day) },
                set: { model.setComment($0, for: line, on: day) }
            ), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            DisclosureGroup("Звідки час", isExpanded: $showSources) {
                let mine = model.sessions(on: day).filter { Classifier.projectId(for: $0, projects: model.projects) == line.projectId }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Grouping.byApp(mine)) { g in
                        HStack {
                            Text(g.label).lineLimit(1)
                            Text(g.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Text(hm(g.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            Button { model.assign(Set(g.sessionIds), to: nil, on: day) } label: { Image(systemName: "arrow.uturn.backward") }
                                .buttonStyle(.borderless)
                                .help("Зняти ручне віднесення (якщо правило ловить — залишиться в проєкті)")
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(color: .black.opacity(0.08), radius: 2, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

// MARK: Другое

enum OtherMode: String, CaseIterable, Identifiable {
    case chrono = "За сесіями", byApp = "За програмами"
    var id: String { rawValue }
}

struct OtherView: View {
    @EnvironmentObject var model: AppModel
    @Binding var day: Date
    @Local private var mode: OtherMode = .chrono
    @Local private var includeIdle = true
    @Local private var selection = Set<String>()
    @Local private var newProjectName = ""
    @Local private var askNewProject = false
    @Local private var pendingIds = Set<UUID>()

    var body: some View {
        let src = Grouping.unclassified(model.sessions(on: day), projects: model.projects, includeIdle: includeIdle)
        let groups = mode == .chrono ? Grouping.chronological(src) : Grouping.byApp(src)
        let selectedIds = Set(groups.filter { selection.contains($0.id) }.flatMap(\.sessionIds))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DayPicker(day: $day)
                Spacer()
                Picker("", selection: $mode) { ForEach(OtherMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Toggle("Простій і відлучки", isOn: $includeIdle)
            }
            HStack {
                Text("\(groups.count) записів · \(hm(src.reduce(0) { $0 + $1.duration }))").foregroundStyle(.secondary)
                Spacer()
                if !selection.isEmpty { Text("Вибрано: \(hm(src.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.duration }))").foregroundStyle(.secondary) }
                assignMenu(ids: selectedIds, title: "Віднести вибране до проєкту")
                    .disabled(selectedIds.isEmpty)
                    .fixedSize()
            }
            if groups.isEmpty {
                EmptyHint(title: "Усе розібрано", text: "Нерозподіленого часу за цей день немає.", icon: "checkmark.seal")
            } else {
                List(groups, selection: $selection) { g in
                    OtherRow(group: g, showTime: mode == .chrono)
                        .contextMenu {
                            assignMenu(ids: Set(g.sessionIds), title: "Віднести до проєкту")
                            ruleMenu(g)
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                Text("⌘-клік / Shift-клік — вибрати кілька. Правий клік — віднести або створити правило на майбутнє.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onChange(of: day) { selection = [] }
        .onChange(of: mode) { selection = [] }
        .alert("Новий проєкт", isPresented: $askNewProject) {
            TextField("Назва", text: $newProjectName)
            Button("Створити й віднести") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let p = model.addProject(name: name)
                model.assign(pendingIds, to: p.id, on: day)
                selection = []
            }
            Button("Скасувати", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func assignMenu(ids: Set<UUID>, title: String) -> some View {
        Menu(title) {
            ForEach(model.projects.filter { !$0.archived }) { p in
                Button(p.name) { model.assign(ids, to: p.id, on: day); selection = [] }
            }
            Divider()
            Button("Новий проєкт…") { pendingIds = ids; newProjectName = ""; askNewProject = true }
        }
    }

    @ViewBuilder
    private func ruleMenu(_ g: SessionGroup) -> some View {
        if g.kind == .active {
            if let d = g.domain {
                Menu("Завжди відносити сайт \(d) до…") {
                    ForEach(model.projects.filter { !$0.archived }) { p in Button(p.name) { model.addRule(to: p.id, domain: d) } }
                }
            } else if !g.app.isEmpty {
                Menu("Завжди відносити програму \(g.app) до…") {
                    ForEach(model.projects.filter { !$0.archived }) { p in Button(p.name) { model.addRule(to: p.id, app: g.app) } }
                }
            }
        }
    }
}

struct OtherRow: View {
    var group: SessionGroup
    var showTime: Bool
    private static let tf: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showTime {
                Text("\(Self.tf.string(from: group.start))–\(Self.tf.string(from: group.end))")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            }
            Image(systemName: icon).foregroundStyle(group.kind == .active ? Color.accentColor : .secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.label).fontWeight(.medium)
                if !group.detail.isEmpty {
                    Text(group.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Text(hm(group.seconds)).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch group.kind {
        case .idle: return "moon.zzz"
        case .away: return "lock"
        case .active: return group.domain != nil ? "globe" : "app"
        }
    }
}

// MARK: Дашборд

enum Period: String, CaseIterable, Identifiable {
    case day = "День", week = "Тиждень", month = "Місяць"
    var id: String { rawValue }
}

struct DayBar: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    var date: Date
    var kind: String
    var hours: Double
}

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Binding var day: Date
    @Local private var period: Period = .week

    private var range: (Date, Date) {
        let cal = Calendar.current
        switch period {
        case .day: return (day, day)
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: day)!.start
            return (start, cal.date(byAdding: .day, value: 6, to: start)!)
        case .month:
            let i = cal.dateInterval(of: .month, for: day)!
            return (i.start, cal.date(byAdding: .day, value: -1, to: i.end)!)
        }
    }

    var body: some View {
        let (from, to) = range
        let all = model.sessions(from: from, to: min(to, Date()))
        let st = Stats.build(all, projects: model.projects)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    DayPicker(day: $day)
                    Spacer()
                    Picker("", selection: $period) { ForEach(Period.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                HStack(spacing: 10) {
                    StatTile(title: "На проєкти", seconds: st.projectsTotal)
                    StatTile(title: "Поза проєктами", seconds: st.otherSeconds, tint: .orange)
                    StatTile(title: "Простій", seconds: st.idleSeconds, tint: .secondary)
                }
                if period != .day { dailyChart(from: from, to: to) }
                section("Проєкти", items: st.projectSeconds.compactMap { k, v in model.project(k).map { ($0.name, v) } }, tint: .accentColor)
                section("Програми", items: st.byApp.map { ($0.key, $0.value) }, tint: .purple)
                section("Сайти в браузері", items: st.byDomain.map { ($0.key, $0.value) }, tint: .teal)
            }
            .padding()
        }
    }

    private func dailyChart(from: Date, to: Date) -> some View {
        var bars: [DayBar] = []
        var d = Calendar.current.startOfDay(for: from)
        while d <= to {
            let s = Stats.build(model.sessions(on: d), projects: model.projects)
            bars.append(DayBar(date: d, kind: "Проєкти", hours: s.projectsTotal / 3600))
            bars.append(DayBar(date: d, kind: "Поза проєктами", hours: s.otherSeconds / 3600))
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
        return VStack(alignment: .leading) {
            Text("По днях, години").font(.headline)
            Chart(bars) { b in
                BarMark(x: .value("День", b.date, unit: .day), y: .value("Години", b.hours))
                    .foregroundStyle(by: .value("Тип", b.kind))
            }
            .chartForegroundStyleScale(["Проєкти": Color.accentColor, "Поза проєктами": Color.orange])
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [(String, TimeInterval)], tint: Color) -> some View {
        let top = items.filter { $0.1 >= 60 }.sorted { $0.1 > $1.1 }.prefix(12)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                ForEach(Array(top), id: \.0) { item in
                    BarRow(label: item.0, seconds: item.1, maxSeconds: top.first!.1, tint: tint)
                }
            }
        }
    }
}

// MARK: Проекты

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @Local private var selected: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(model.projects) { p in
                        Text(p.name).foregroundStyle(p.archived ? .secondary : .primary).tag(p.id)
                    }
                }
                HStack {
                    Button { selected = model.addProject(name: "Новий проєкт").id } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selected { model.projects.removeAll { $0.id == id }; selected = nil }
                    } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 260)

            Group {
                if let id = selected, let p = model.project(id) {
                    ProjectEditor(project: p).id(id)
                } else {
                    EmptyHint(title: "Обери проєкт", text: "Або натисни «+», щоб створити. Правила визначають, який час потрапить у проєкт автоматично.", icon: "folder")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ProjectEditor: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @Local private var name: String
    @Local private var domains: String
    @Local private var keywords: String
    @Local private var apps: String
    @Local private var archived: Bool

    init(project: Project) {
        self.project = project
        _name = Local(wrappedValue: project.name)
        _domains = Local(wrappedValue: project.domains.joined(separator: "\n"))
        _keywords = Local(wrappedValue: project.keywords.joined(separator: "\n"))
        _apps = Local(wrappedValue: project.apps.joined(separator: "\n"))
        _archived = Local(wrappedValue: project.archived)
    }

    var body: some View {
        Form {
            TextField("Назва", text: $name)
            Toggle("В архіві (не ловить час)", isOn: $archived)
            Section {
                ruleEditor($domains)
            } header: { Text("Домени") } footer: { Text("По одному в рядку: ti.ua — спіймає і shop.ti.ua. Працює за адресою вкладки (Chrome, Safari, Arc, Brave, Edge) і за заголовком.").font(.caption) }
            Section {
                ruleEditor($keywords)
            } header: { Text("Фрази") } footer: { Text("Якщо фраза є в заголовку вікна чи адресі — час іде в проєкт. Наприклад: техноїжак, назва клієнта, назва чату в Telegram (якщо в «Налаштуваннях» увімкнено розпізнавання чату).").font(.caption) }
            Section {
                ruleEditor($apps)
            } header: { Text("Програми") } footer: { Text("Весь час у програмі цілком: Figma, Xcode. Можна назву або bundle id.").font(.caption) }
            HStack {
                Spacer()
                Button("Зберегти") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onDisappear { save() }
    }

    private func ruleEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text).font(.body.monospaced()).frame(minHeight: 60, maxHeight: 110)
    }

    private func split(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        guard let i = model.projects.firstIndex(where: { $0.id == project.id }) else { return }
        var p = model.projects[i]
        p.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? p.name : name.trimmingCharacters(in: .whitespaces)
        p.domains = split(domains).map(Domain.normalizeRule)
        p.keywords = split(keywords)
        p.apps = split(apps)
        p.archived = archived
        if p != model.projects[i] { model.projects[i] = p }
    }
}

// MARK: Настройки

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Облік") {
                Stepper("Простій після \(model.settings.idleMinutes) хв без дій", value: $model.settings.idleMinutes, in: 1...30)
                Stepper("Округлювати до \(model.settings.roundingMinutes) хв", value: $model.settings.roundingMinutes, in: 1...30)
                Stepper("Пунктів у коментарі: \(model.settings.commentMaxItems)", value: $model.settings.commentMaxItems, in: 1...15)
            }
            Section("Система") {
                Toggle("Запускати під час входу в систему", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                HStack {
                    Label(model.axTrusted ? "Доступ до заголовків вікон є" : "Немає доступу до заголовків вікон",
                          systemImage: model.axTrusted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(model.axTrusted ? .green : .red)
                    Spacer()
                    Button("Доступність…") { Sensors.openAccessibilitySettings() }
                }
                HStack {
                    Text("Адреси вкладок браузерів").foregroundStyle(.secondary)
                    Spacer()
                    Button("Автоматизація…") { Sensors.openAutomationSettings() }
                }
            }
            Section {
                Toggle("Розпізнавати назву чату в Telegram", isOn: Binding(get: { model.settings.telegramOCR }, set: { on in
                    model.settings.telegramOCR = on
                    if on && !TelegramReader.screenCaptureAllowed { TelegramReader.requestScreenCapture() }
                }))
                if model.settings.telegramOCR { TelegramOCRRow(status: model.telegramOCR) }
            } header: { Text("Telegram") } footer: {
                Text("Telegram не показує назву чату іншим програмам. Без цієї опції весь Telegram записується без заголовка, і правила-фрази його чати не розрізняють. З опцією Time Checker, поки Telegram активний, знімає лише смугу з назвою чату й розпізнає текст на цьому Mac. Знімки не зберігаються і нікуди не надсилаються. Потрібен дозвіл «Запис екрана»; після надання macOS попросить перезапустити Time Checker.")
                    .font(.caption)
            }
            Section("Дані") {
                LabeledContent("Тека", value: model.store.dir.path)
                Button("Відкрити у Finder") { model.openDataFolder() }
            }
        }
        .formStyle(.grouped)
    }
}

struct TelegramOCRRow: View {
    @ObservedObject var status: TelegramOCRStatus

    var body: some View {
        HStack {
            if status.allowed {
                Label(status.lastChat.map { "Працює, останній чат: \($0)" } ?? "Працює: відкрийте чат у Telegram",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Немає дозволу «Запис екрана»", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            Spacer()
            Button("Запис екрана…") { TelegramReader.openScreenCaptureSettings() }
        }
    }
}

// MARK: Справка

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                help("Як це працює",
                     "Щосекунди Time Checker дивиться, яке вікно активне: програма, заголовок вікна і — для Chrome, Safari, Arc, Brave, Edge — адреса вкладки. Час ділиться на відрізки й за правилами розкладається по проєктах. Усе зберігається локально, у мережу нічого не йде.")
                help("Правила", "На вкладці «Проєкти» кожен проєкт має три типи правил:\n• Домени — ti.ua ловить ti.ua і всі піддомени.\n• Фрази — шукаються в заголовку вікна й адресі, без урахування регістру; однакові на вигляд кирилиця й латиниця («СЕО» і «CEO») вважаються одним і тим самим.\n• Програми — весь час у програмі цілком.\nПорядок: ручне віднесення → домен → домен у заголовку → фраза → програма.")
                help("Інше", "Усе, що не потрапило в жоден проєкт, — на вкладці «Інше». Два групування: за сесіями (хронологія) і за програмами. Виділи рядки (⌘/Shift-клік) і віднеси до проєкту. Правий клік → «Завжди відносити сайт…» створить правило на майбутнє.")
                help("Простій і відлучки", "Якщо 3 хвилини (налаштовується) не торкатися клавіатури й миші — час іде в «Простій» заднім числом від останньої дії. Блокування екрана й сон — «Відлучки». І те, і те видно в «Іншому», його можна віднести до проєкту: наприклад, читав документ або був на дзвінку.")
                help("Звіт", "Час по проєкту округлюється до 5 хвилин (налаштовується). Коментар збирається з найтриваліших заголовків вікон; його можна виправити — правка зберігається. «Копіювати звіт» (⇧⌘C) кладе все одним текстом у буфер.")
                help("Telegram", "Telegram не показує назву відкритого чату іншим програмам: у заголовку вікна завжди «Telegram @ акаунт». Тому за замовчуванням час у Telegram записується без заголовка — правила-фрази його чати не розрізняють, а слова з імені акаунта більше не ловлять весь Telegram. Такі відрізки розбирай на вкладці «Інше» або правилом «програма».\nУ «Налаштуваннях» можна ввімкнути розпізнавання назви чату. Поки Telegram активний, Time Checker раз на кілька секунд знімає лише смугу шапки чату й розпізнає текст на цьому Mac — заголовок стає «Telegram — назва чату», і фрази знову працюють. Знімки не зберігаються і нікуди не надсилаються. Потрібен дозвіл «Запис екрана».")
                help("Дозволи", "• Доступність — щоб читати заголовки вікон. Без неї видно лише програму.\n• Автоматизація — macOS запитає один раз для кожного браузера, щоб читати адресу вкладки.\n• Запис екрана — лише якщо ввімкнено розпізнавання чату в Telegram. macOS час від часу перепитує цей дозвіл.\nПісля перезбирання програми доступ іноді доводиться надати заново.")
                help("Обмеження", "Враховується лише активне вікно у фокусі. Firefox не віддає адресу вкладки — для нього працюють лише заголовки. Сервіси, у заголовку яких немає проєкту (Serpstat, планувальники тощо), потрапляють в «Інше» — розбирай вручну або додай фрази. Telegram без розпізнавання чату — один рядок без заголовка; з розпізнаванням назва іноді читається з помилками (емодзі зникають), а заголовок оновлюється через 1–3 секунди після зміни чату.")
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Local

/// Замена @State: в новом SDK @Local — макрос, а его плагин есть только в Xcode.
/// Обёртка хранит обычный State внутри, поэтому собирается одними Command Line Tools.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private var state: State<Value>
    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}
