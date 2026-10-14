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
                Button("Сегодня") { day = Date() }
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
                Text("Нет доступа к заголовкам окон").font(.callout.weight(.semibold))
                Text("Разреши Time Checker в «Универсальном доступе», иначе видно только приложение, без названия вкладки.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Открыть настройки") { Sensors.openAccessibilitySettings() }.controlSize(.small)
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
                Text("Сегодня").font(.headline)
                Spacer()
                Text("на проекты \(hm(st.projectsTotal))").foregroundStyle(.secondary).monospacedDigit()
            }
            if !model.axTrusted { AccessWarning() }
            if let c = model.current {
                Label(nowText(c), systemImage: model.project(Classifier.projectId(for: c, projects: model.projects)) == nil ? "circle.dashed" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if model.paused {
                Label("Пауза — время не считается", systemImage: "pause.circle").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            if lines.isEmpty {
                Text(model.projects.isEmpty ? "Добавь проекты и правила — тогда здесь появится отчёт." : "Пока ничего не попало в проекты.")
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
                Text("Другое \(hm(st.otherSeconds))")
                Text("·").foregroundStyle(.tertiary)
                Text("Простой \(hm(st.idleSeconds))")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(copied ? "Скопировано ✓" : "Копировать отчёт") {
                    model.copyReport(on: day); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(lines.isEmpty)
                Button("Открыть…") { open() }
                Spacer()
                Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill") }
                    .help(model.paused ? "Продолжить" : "Пауза")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Выйти")
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func nowText(_ s: Session) -> String {
        switch s.kind {
        case .idle: return "Сейчас: простой"
        case .away: return "Сейчас: нет за компьютером"
        case .active:
            let what = s.domain ?? (s.title.isEmpty ? s.app : s.title)
            return "Сейчас: \(s.app) — \(what)"
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
            ReportView(day: $day, tab: $tab).tabItem { Label("Отчёт", systemImage: "doc.text") }.tag(MainTab.report)
            OtherView(day: $day).tabItem { Label("Другое", systemImage: "tray") }.tag(MainTab.other)
            DashboardView(day: $day).tabItem { Label("Дашборд", systemImage: "chart.bar") }.tag(MainTab.dashboard)
            ProjectsView().tabItem { Label("Проекты", systemImage: "folder") }.tag(MainTab.projects)
            SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }.tag(MainTab.settings)
            HelpView().tabItem { Label("Справка", systemImage: "questionmark.circle") }.tag(MainTab.help)
        }
        .padding(.top, 4)
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
                Button(copied ? "Скопировано ✓" : "Копировать отчёт") {
                    model.copyReport(on: day); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                .disabled(lines.isEmpty)
            }
            if !model.axTrusted { AccessWarning() }
            HStack(spacing: 10) {
                StatTile(title: "На проекты", seconds: st.projectsTotal)
                StatTile(title: "Другое", seconds: st.otherSeconds, tint: .orange)
                StatTile(title: "Простой", seconds: st.idleSeconds, tint: .secondary)
                StatTile(title: "Отлучки / сон", seconds: st.awaySeconds, tint: .secondary)
            }
            if lines.isEmpty {
                EmptyHint(title: "Отчёт пуст",
                          text: model.projects.isEmpty
                            ? "Создай проекты во вкладке «Проекты» и добавь правила: домены, фразы из заголовков, приложения."
                            : "За этот день ничего не попало в проекты. Загляни в «Другое» — оттуда время переносится в проект.",
                          icon: "doc.text.magnifyingglass")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(lines) { l in ReportCard(line: l, day: day) }
                    }
                }
            }
            if st.otherSeconds >= 60 {
                Button("Нераспределено \(hm(st.otherSeconds)) — разобрать в «Другом» →") { tab = .other }
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
            TextField("Комментарий", text: Binding(
                get: { model.comment(line, on: day) },
                set: { model.setComment($0, for: line, on: day) }
            ), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            DisclosureGroup("Откуда время", isExpanded: $showSources) {
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
                                .help("Снять ручное отнесение (если правило ловит — останется в проекте)")
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
    case chrono = "По сессиям", byApp = "По программам"
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
                Toggle("Простой и отлучки", isOn: $includeIdle)
            }
            HStack {
                Text("\(groups.count) записей · \(hm(src.reduce(0) { $0 + $1.duration }))").foregroundStyle(.secondary)
                Spacer()
                if !selection.isEmpty { Text("Выбрано: \(hm(src.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.duration }))").foregroundStyle(.secondary) }
                assignMenu(ids: selectedIds, title: "Отнести выбранное к проекту")
                    .disabled(selectedIds.isEmpty)
                    .fixedSize()
            }
            if groups.isEmpty {
                EmptyHint(title: "Всё разобрано", text: "Нераспределённого времени за этот день нет.", icon: "checkmark.seal")
            } else {
                List(groups, selection: $selection) { g in
                    OtherRow(group: g, showTime: mode == .chrono)
                        .contextMenu {
                            assignMenu(ids: Set(g.sessionIds), title: "Отнести к проекту")
                            ruleMenu(g)
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                Text("⌘-клик / Shift-клик — выбрать несколько. Правый клик — отнести или создать правило на будущее.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onChange(of: day) { selection = [] }
        .onChange(of: mode) { selection = [] }
        .alert("Новый проект", isPresented: $askNewProject) {
            TextField("Название", text: $newProjectName)
            Button("Создать и отнести") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let p = model.addProject(name: name)
                model.assign(pendingIds, to: p.id, on: day)
                selection = []
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func assignMenu(ids: Set<UUID>, title: String) -> some View {
        Menu(title) {
            ForEach(model.projects.filter { !$0.archived }) { p in
                Button(p.name) { model.assign(ids, to: p.id, on: day); selection = [] }
            }
            Divider()
            Button("Новый проект…") { pendingIds = ids; newProjectName = ""; askNewProject = true }
        }
    }

    @ViewBuilder
    private func ruleMenu(_ g: SessionGroup) -> some View {
        if g.kind == .active {
            if let d = g.domain {
                Menu("Всегда относить сайт \(d) к…") {
                    ForEach(model.projects.filter { !$0.archived }) { p in Button(p.name) { model.addRule(to: p.id, domain: d) } }
                }
            } else if !g.app.isEmpty {
                Menu("Всегда относить приложение \(g.app) к…") {
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
    case day = "День", week = "Неделя", month = "Месяц"
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
                    StatTile(title: "На проекты", seconds: st.projectsTotal)
                    StatTile(title: "Вне проектов", seconds: st.otherSeconds, tint: .orange)
                    StatTile(title: "Простой", seconds: st.idleSeconds, tint: .secondary)
                }
                if period != .day { dailyChart(from: from, to: to) }
                section("Проекты", items: st.projectSeconds.compactMap { k, v in model.project(k).map { ($0.name, v) } }, tint: .accentColor)
                section("Программы", items: st.byApp.map { ($0.key, $0.value) }, tint: .purple)
                section("Сайты в браузере", items: st.byDomain.map { ($0.key, $0.value) }, tint: .teal)
            }
            .padding()
        }
    }

    private func dailyChart(from: Date, to: Date) -> some View {
        var bars: [DayBar] = []
        var d = Calendar.current.startOfDay(for: from)
        while d <= to {
            let s = Stats.build(model.sessions(on: d), projects: model.projects)
            bars.append(DayBar(date: d, kind: "Проекты", hours: s.projectsTotal / 3600))
            bars.append(DayBar(date: d, kind: "Вне проектов", hours: s.otherSeconds / 3600))
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
        return VStack(alignment: .leading) {
            Text("По дням, часы").font(.headline)
            Chart(bars) { b in
                BarMark(x: .value("День", b.date, unit: .day), y: .value("Часы", b.hours))
                    .foregroundStyle(by: .value("Тип", b.kind))
            }
            .chartForegroundStyleScale(["Проекты": Color.accentColor, "Вне проектов": Color.orange])
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
                    Button { selected = model.addProject(name: "Новый проект").id } label: { Image(systemName: "plus") }
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
                    EmptyHint(title: "Выбери проект", text: "Или нажми «+», чтобы создать. Правила определяют, какое время попадёт в проект автоматически.", icon: "folder")
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
            TextField("Название", text: $name)
            Toggle("В архиве (не ловит время)", isOn: $archived)
            Section {
                ruleEditor($domains)
            } header: { Text("Домены") } footer: { Text("По одному в строке: ti.ua — поймает и shop.ti.ua. Работает по адресу вкладки (Chrome, Safari, Arc, Brave, Edge) и по заголовку.").font(.caption) }
            Section {
                ruleEditor($keywords)
            } header: { Text("Фразы") } footer: { Text("Если фраза есть в заголовке окна или адресе — время идёт в проект. Например: техноїжак, название клиента, имя чата в Telegram.").font(.caption) }
            Section {
                ruleEditor($apps)
            } header: { Text("Приложения") } footer: { Text("Всё время в приложении целиком: Figma, Xcode. Можно имя или bundle id.").font(.caption) }
            HStack {
                Spacer()
                Button("Сохранить") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
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
            Section("Учёт") {
                Stepper("Простой после \(model.settings.idleMinutes) мин без действий", value: $model.settings.idleMinutes, in: 1...30)
                Stepper("Округлять до \(model.settings.roundingMinutes) мин", value: $model.settings.roundingMinutes, in: 1...30)
                Stepper("Пунктов в комментарии: \(model.settings.commentMaxItems)", value: $model.settings.commentMaxItems, in: 1...15)
            }
            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                HStack {
                    Label(model.axTrusted ? "Доступ к заголовкам окон есть" : "Нет доступа к заголовкам окон",
                          systemImage: model.axTrusted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(model.axTrusted ? .green : .red)
                    Spacer()
                    Button("Универсальный доступ…") { Sensors.openAccessibilitySettings() }
                }
                HStack {
                    Text("Адреса вкладок браузеров").foregroundStyle(.secondary)
                    Spacer()
                    Button("Автоматизация…") { Sensors.openAutomationSettings() }
                }
            }
            Section("Данные") {
                LabeledContent("Папка", value: model.store.dir.path)
                Button("Открыть в Finder") { model.openDataFolder() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Справка

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                help("Как это работает",
                     "Раз в секунду Time Checker смотрит, какое окно активно: приложение, заголовок окна и — для Chrome, Safari, Arc, Brave, Edge — адрес вкладки. Время режется на отрезки и по правилам раскладывается по проектам. Всё хранится локально, в сеть ничего не уходит.")
                help("Правила", "Во вкладке «Проекты» у каждого проекта три типа правил:\n• Домены — ti.ua ловит ti.ua и все поддомены.\n• Фразы — ищутся в заголовке окна и адресе, без учёта регистра.\n• Приложения — всё время в приложении целиком.\nПорядок: ручное отнесение → домен → домен в заголовке → фраза → приложение.")
                help("Другое", "Всё, что не попало ни в один проект, — во вкладке «Другое». Две группировки: по сессиям (хронология) и по программам. Выдели строки (⌘/Shift-клик) и отнеси к проекту. Правый клик → «Всегда относить сайт…» создаст правило на будущее.")
                help("Простой и отлучки", "Если 3 минуты (настраивается) не трогать клавиатуру и мышь — время уходит в «Простой» задним числом с последнего действия. Блокировка экрана и сон — «Отлучки». И то и другое видно в «Другом», его можно отнести к проекту: например, читал документ или был на созвоне.")
                help("Отчёт", "Время по проекту округляется до 5 минут (настраивается). Комментарий собирается из самых «долгих» заголовков окон; его можно поправить — правка сохраняется. «Копировать отчёт» (⇧⌘C) кладёт всё одним текстом в буфер.")
                help("Разрешения", "• Универсальный доступ — чтобы читать заголовки окон. Без него видно только приложение.\n• Автоматизация — macOS спросит один раз для каждого браузера, чтобы читать адрес вкладки.\nПосле пересборки приложения доступ иногда приходится выдать заново.")
                help("Ограничения", "Считается только активное окно в фокусе. Firefox не отдаёт адрес вкладки — для него работают только заголовки. Сервисы, в заголовке которых нет проекта (Serpstat, планировщики и т. п.), уходят в «Другое» — разбирай вручную или добавь фразы.")
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
