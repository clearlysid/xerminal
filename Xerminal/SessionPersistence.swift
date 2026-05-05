import Foundation

/// Persists the open-tab list across launches. Only saved-host tabs survive;
/// transient (Quick Connect) tabs are dropped on relaunch since their creds
/// aren't stored anywhere.
struct PersistedTabs: Codable {
    var hostIDs: [UUID]
    var activeHostIndex: Int   // index into hostIDs of the active tab, or -1 if active was transient.
}

@MainActor
enum SessionPersistence {
    private static let key = "xerminal.tabs.v1"

    static func save(_ p: PersistedTabs) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> PersistedTabs? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedTabs.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
