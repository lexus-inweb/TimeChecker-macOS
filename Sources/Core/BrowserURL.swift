import Foundation

/// Когда перечитывать адрес активной вкладки. Сам запрос (AppleScript) идёт в фоне в Sensors,
/// а здесь — чистые решения, покрытые тестами.
/// - адрес перечитывается не реже раза в `refreshInterval`: у двух вкладок может быть одинаковый
///   заголовок («Login»), а без доступа к заголовкам ключ окна вообще не меняется;
/// - неудачный запрос (nil) тоже повторяется через `refreshInterval`;
/// - одновременно идёт только один запрос: первый может ждать ответа на диалог «Автоматизация»;
/// - ответ, который пришёл про другую вкладку (пользователь успел переключиться), отбрасывается.
struct URLCachePolicy {
    var refreshInterval: TimeInterval = 3
    private(set) var entry: (key: String, url: String?, fetchedAt: Date)?
    private(set) var pending: (key: String, id: Int)?
    private var lastId = 0

    /// Адрес для окна `key` (если он уже известен) и id нового запроса, если пора сходить в браузер.
    mutating func lookup(key: String, now: Date) -> (url: String?, requestId: Int?) {
        var url: String?
        var due = true
        if let e = entry, e.key == key {
            url = e.url
            due = now.timeIntervalSince(e.fetchedAt) >= refreshInterval
        }
        guard due, pending == nil else { return (url, nil) }
        lastId += 1
        pending = (key, lastId)
        return (url, lastId)
    }

    /// Результат запроса `requestId`. `windowTitle` — заголовок окна, для которого запрашивали,
    /// `tabTitle` — заголовок вкладки, который вернул браузер вместе с адресом.
    mutating func complete(requestId: Int, url: String?, tabTitle: String?, windowTitle: String, now: Date) {
        guard let p = pending, p.id == requestId else { return }
        pending = nil
        if Self.tabMatches(tabTitle: tabTitle, windowTitle: windowTitle) {
            entry = (p.key, url, now)
        } else {
            // Ответ про другую вкладку: адрес не берём, но и не долбим браузер каждую секунду —
            // следующая попытка через refreshInterval.
            let previous = entry?.key == p.key ? entry?.url : nil
            entry = (p.key, previous, now)
        }
    }

    /// Окно браузера называется по активной вкладке («<вкладка> - Google Chrome – Профиль»).
    /// Если заголовка вкладки нет в заголовке окна — ответ про другую вкладку.
    static func tabMatches(tabTitle: String?, windowTitle: String) -> Bool {
        guard let tab = tabTitle?.trimmingCharacters(in: .whitespaces), !tab.isEmpty,
              !windowTitle.isEmpty else { return true } // сверить не с чем — верим ответу
        return windowTitle.contains(tab)
    }
}
