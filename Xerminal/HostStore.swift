import Foundation

@MainActor
final class HostStore {
    static let shared = HostStore()

    private(set) var hosts: [StoredHost] = []
    var onChange: () -> Void = {}

    private let url: URL = {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let dir = appSupport.appendingPathComponent("xerminal", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hosts.json")
    }()

    init() {
        load()
        HostsSpotlight.indexAll(hosts)
    }

    func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        hosts = (try? JSONDecoder().decode([StoredHost].self, from: data)) ?? []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            try? data.write(to: url, options: .atomic)
        }
        onChange()
    }

    @discardableResult
    func add(label: String, params: ConnectParams) -> StoredHost {
        let id = UUID()
        let authRef = storeSecrets(id: id, auth: params.auth)
        let host = StoredHost(id: id, label: label,
                              host: params.host, port: params.port,
                              username: params.username, authRef: authRef)
        hosts.append(host)
        persist()
        HostsSpotlight.index(host)
        return host
    }

    @discardableResult
    func update(_ host: StoredHost, label: String, params: ConnectParams) -> StoredHost {
        wipeSecrets(host)
        let authRef = storeSecrets(id: host.id, auth: params.auth)
        var updated = host
        updated.label = label
        updated.host = params.host
        updated.port = params.port
        updated.username = params.username
        updated.authRef = authRef
        if let idx = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[idx] = updated
        }
        persist()
        HostsSpotlight.index(updated)
        return updated
    }

    func delete(_ host: StoredHost) {
        wipeSecrets(host)
        hosts.removeAll { $0.id == host.id }
        persist()
        HostsSpotlight.remove(id: host.id)
    }

    /// Hydrate stored host into runtime ConnectParams. Returns nil if creds missing.
    func makeParams(for host: StoredHost) -> ConnectParams? {
        switch host.authRef {
        case .password:
            guard let data = Keychain.get(account: host.pwAccount),
                  let pw = String(data: data, encoding: .utf8) else { return nil }
            return ConnectParams(host: host.host, port: host.port,
                                 username: host.username, auth: .password(pw))
        case .privateKey(let hasPP):
            guard let pemData = Keychain.get(account: host.pemAccount),
                  let pem = String(data: pemData, encoding: .utf8) else { return nil }
            var passphrase: String? = nil
            if hasPP {
                guard let ppData = Keychain.get(account: host.ppAccount),
                      let pp = String(data: ppData, encoding: .utf8) else { return nil }
                passphrase = pp
            }
            return ConnectParams(host: host.host, port: host.port,
                                 username: host.username,
                                 auth: .privateKey(pem: pem, passphrase: passphrase))
        }
    }

    private func storeSecrets(id: UUID, auth: SSHAuth) -> AuthRef {
        let pwAccount = "pw-\(id.uuidString)"
        let pemAccount = "pem-\(id.uuidString)"
        let ppAccount = "pp-\(id.uuidString)"
        switch auth {
        case .password(let p):
            Keychain.set(Data(p.utf8), account: pwAccount)
            Keychain.delete(account: pemAccount)
            Keychain.delete(account: ppAccount)
            return .password
        case .privateKey(let pem, let passphrase):
            Keychain.set(Data(pem.utf8), account: pemAccount)
            Keychain.delete(account: pwAccount)
            if let pp = passphrase, !pp.isEmpty {
                Keychain.set(Data(pp.utf8), account: ppAccount)
                return .privateKey(hasPassphrase: true)
            } else {
                Keychain.delete(account: ppAccount)
                return .privateKey(hasPassphrase: false)
            }
        }
    }

    private func wipeSecrets(_ host: StoredHost) {
        Keychain.delete(account: host.pwAccount)
        Keychain.delete(account: host.pemAccount)
        Keychain.delete(account: host.ppAccount)
    }
}
