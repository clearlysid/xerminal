import Foundation
import Crypto
import NIOCore
@preconcurrency import NIOSSH

enum HostKeyError: Error, LocalizedError {
    case changed(host: String, expected: String, got: String)
    case rejected

    var errorDescription: String? {
        switch self {
        case .changed(let host, let expected, let got):
            return """
            host key for \(host) CHANGED!
            stored: \(expected)
            seen:   \(got)
            remove from Known Hosts in Settings to reconnect.
            """
        case .rejected:
            return "host key rejected"
        }
    }
}

/// `prompter(host, port, fingerprint, completion)` — caller invokes `completion(true|false)` once user decides.
typealias HostKeyPrompter = @Sendable (String, Int, String, @escaping @Sendable (Bool) -> Void) -> Void

/// Strict host-key validator. Reads/writes `KnownHostsStore` directly (thread-safe).
/// Promise resolution happens on whichever thread fulfills it; NIO handles cross-thread completion.
final class HostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: String
    let port: Int
    let prompter: HostKeyPrompter

    init(host: String, port: Int, prompter: @escaping HostKeyPrompter) {
        self.host = host
        self.port = port
        self.prompter = prompter
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = Self.fingerprint(of: hostKey)
        let store = KnownHostsStore.shared

        // Fast path: known fingerprint, decide on the calling thread.
        if let known = store.fingerprint(host: host, port: port) {
            if known == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(
                    HostKeyError.changed(host: "\(host):\(port)",
                                         expected: known,
                                         got: fingerprint))
            }
            return
        }

        // Unknown: ask the user.
        let host = self.host
        let port = self.port
        prompter(host, port, fingerprint) { accepted in
            if accepted {
                KnownHostsStore.shared.add(host: host, port: port, fingerprint: fingerprint)
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyError.rejected)
            }
        }
    }

    /// OpenSSH-compatible SHA256 fingerprint, e.g. "SHA256:abc...".
    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        var buf = ByteBuffer()
        _ = key.write(to: &buf)
        let bytes = buf.readBytes(length: buf.readableBytes) ?? []
        let hash = SHA256.hash(data: Data(bytes))
        let b64 = Data(hash).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }
}
