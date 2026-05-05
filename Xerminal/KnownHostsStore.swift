import Foundation

/// Thread-safe known-hosts store. Read/write from any queue.
final class KnownHostsStore: @unchecked Sendable {
    static let shared = KnownHostsStore()

    private let lock = NSLock()
    private var map: [String: String] = [:]   // "host:port" → "SHA256:base64"

    private let url: URL = {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let dir = appSupport.appendingPathComponent("xerminal", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("known_hosts.json")
    }()

    init() { load() }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return map.count
    }

    var entries: [(host: String, port: Int, fingerprint: String)] {
        lock.lock(); defer { lock.unlock() }
        return map.compactMap { key, fp in
            guard let colon = key.lastIndex(of: ":"),
                  let port = Int(key[key.index(after: colon)...]) else { return nil }
            return (String(key[..<colon]), port, fp)
        }
    }

    func fingerprint(host: String, port: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return map[key(host: host, port: port)]
    }

    func add(host: String, port: Int, fingerprint: String) {
        lock.lock()
        map[key(host: host, port: port)] = fingerprint
        lock.unlock()
        persist()
    }

    func remove(host: String, port: Int) {
        lock.lock()
        map.removeValue(forKey: key(host: host, port: port))
        lock.unlock()
        persist()
    }

    func clear() {
        lock.lock()
        map.removeAll()
        lock.unlock()
        persist()
    }

    private func key(host: String, port: Int) -> String { "\(host):\(port)" }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoded = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        lock.lock()
        map = decoded
        lock.unlock()
    }

    private func persist() {
        lock.lock()
        let snapshot = map
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
