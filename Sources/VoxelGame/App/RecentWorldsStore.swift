import Foundation

/// Tracks recently opened/saved world files for the File ▸ Open Recent menu.
///
/// Most-recently-used order, deduplicated, capped at `limit`. Backed by
/// `UserDefaults` so the list survives relaunches. The defaults instance is
/// injected so tests can use an isolated suite.
struct RecentWorldsStore {
    static let defaultsKey = "recentWorldPaths"

    let defaults: UserDefaults
    let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 8) {
        self.defaults = defaults
        self.limit = limit
    }

    /// Current list, most recent first.
    func paths() -> [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    /// Records a use of `path`: moves it to the front, dropping duplicates and
    /// anything beyond the cap.
    func note(_ path: String) {
        var list = paths()
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > limit {
            list.removeLast(list.count - limit)
        }
        defaults.set(list, forKey: Self.defaultsKey)
    }

    /// Removes a stale entry (e.g. the file was deleted on disk).
    func remove(_ path: String) {
        var list = paths()
        list.removeAll { $0 == path }
        defaults.set(list, forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
