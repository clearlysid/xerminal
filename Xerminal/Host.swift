import Foundation

struct StoredHost: Codable, Identifiable, Hashable {
    let id: UUID
    var label: String
    var host: String
    var port: Int
    var username: String
    var authRef: AuthRef
}

enum AuthRef: Codable, Hashable {
    case password
    case privateKey(hasPassphrase: Bool)
}

extension StoredHost {
    var pwAccount: String  { "pw-\(id.uuidString)" }
    var pemAccount: String { "pem-\(id.uuidString)" }
    var ppAccount: String  { "pp-\(id.uuidString)" }

    var subtitle: String { "\(username)@\(host):\(port)" }
}
