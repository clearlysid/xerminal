import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

enum SSHAuthError: Error, LocalizedError {
    case unsupportedKeyType(String)
    case encryptedECDSANotSupported
    case keyParse(Error)
    case malformedECDSA(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedKeyType(let t): return "unsupported key type: \(t)"
        case .encryptedECDSANotSupported: return "encrypted ECDSA keys not yet supported — decrypt first"
        case .keyParse(let e): return "key parse: \(e)"
        case .malformedECDSA(let r): return "malformed ECDSA: \(r)"
        }
    }
}

private func sshAuthMethod(username: String, auth: SSHAuth) throws -> SSHAuthenticationMethod {
    switch auth {
    case .password(let p):
        return .passwordBased(username: username, password: p)
    case .privateKey(let pem, let passphrase):
        let decryption = passphrase?.data(using: .utf8)
        let detected: SSHKeyType
        do {
            detected = try SSHKeyDetection.detectPrivateKeyType(from: pem)
        } catch {
            throw SSHAuthError.keyParse(error)
        }
        do {
            switch detected {
            case .ed25519:
                let key = try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryption)
                return .ed25519(username: username, privateKey: key)
            case .rsa:
                let key = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryption)
                return .rsa(username: username, privateKey: key)
            case .ecdsaP256:
                let scalar = try parseECDSAScalar(pem: pem, expectedCurve: "nistp256", expectedKeyType: "ecdsa-sha2-nistp256")
                let key = try P256.Signing.PrivateKey(rawRepresentation: scalar)
                return .p256(username: username, privateKey: key)
            case .ecdsaP384:
                let scalar = try parseECDSAScalar(pem: pem, expectedCurve: "nistp384", expectedKeyType: "ecdsa-sha2-nistp384")
                let key = try P384.Signing.PrivateKey(rawRepresentation: scalar)
                return .p384(username: username, privateKey: key)
            case .ecdsaP521:
                let scalar = try parseECDSAScalar(pem: pem, expectedCurve: "nistp521", expectedKeyType: "ecdsa-sha2-nistp521")
                let key = try P521.Signing.PrivateKey(rawRepresentation: scalar)
                return .p521(username: username, privateKey: key)
            default:
                throw SSHAuthError.unsupportedKeyType(detected.rawValue)
            }
        } catch let e as SSHAuthError {
            throw e
        } catch {
            throw SSHAuthError.keyParse(error)
        }
    }
}

/// Parses an unencrypted OpenSSH ECDSA private key and returns the scalar `d` zero-padded
/// to the expected size for the curve. Encrypted keys are rejected.
private func parseECDSAScalar(pem: String, expectedCurve: String, expectedKeyType: String) throws -> Data {
    var content = pem.replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\r", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard content.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"),
          content.hasSuffix("-----END OPENSSH PRIVATE KEY-----") else {
        throw SSHAuthError.malformedECDSA("missing OpenSSH boundaries")
    }
    content.removeLast("-----END OPENSSH PRIVATE KEY-----".count)
    content.removeFirst("-----BEGIN OPENSSH PRIVATE KEY-----".count)
    guard let blob = Data(base64Encoded: content) else {
        throw SSHAuthError.malformedECDSA("base64")
    }

    var buf = ByteBuffer(bytes: blob)

    func readSSHString(_ b: inout ByteBuffer) throws -> ByteBuffer {
        guard let len = b.readInteger(as: UInt32.self),
              let s = b.readSlice(length: Int(len)) else {
            throw SSHAuthError.malformedECDSA("ssh-string read")
        }
        return s
    }

    guard buf.readString(length: "openssh-key-v1".utf8.count) == "openssh-key-v1",
          buf.readInteger(as: UInt8.self) == 0 else {
        throw SSHAuthError.malformedECDSA("magic")
    }

    var cipherBuf = try readSSHString(&buf)
    let cipherName = cipherBuf.readString(length: cipherBuf.readableBytes) ?? ""
    var kdfBuf = try readSSHString(&buf)
    let kdfName = kdfBuf.readString(length: kdfBuf.readableBytes) ?? ""
    _ = try readSSHString(&buf) // kdf options

    if cipherName != "none" || kdfName != "none" {
        throw SSHAuthError.encryptedECDSANotSupported
    }

    guard buf.readInteger(as: UInt32.self) == 1 else {
        throw SSHAuthError.malformedECDSA("numKeys")
    }
    _ = try readSSHString(&buf) // public key blob

    var priv = try readSSHString(&buf)
    guard let c0 = priv.readInteger(as: UInt32.self),
          let c1 = priv.readInteger(as: UInt32.self),
          c0 == c1 else {
        throw SSHAuthError.malformedECDSA("checksum")
    }
    var keyTypeBuf = try readSSHString(&priv)
    let keyType = keyTypeBuf.readString(length: keyTypeBuf.readableBytes) ?? ""
    guard keyType == expectedKeyType else {
        throw SSHAuthError.malformedECDSA("keytype \(keyType)")
    }
    var curveBuf = try readSSHString(&priv)
    let curve = curveBuf.readString(length: curveBuf.readableBytes) ?? ""
    guard curve == expectedCurve else {
        throw SSHAuthError.malformedECDSA("curve \(curve)")
    }
    _ = try readSSHString(&priv) // Q (public point), unused

    var dBuf = try readSSHString(&priv) // mpint d
    var dBytes = dBuf.readBytes(length: dBuf.readableBytes) ?? []
    // mpint may have a leading 0x00 sign byte; strip it.
    if let first = dBytes.first, first == 0x00, dBytes.count > 1 {
        dBytes.removeFirst()
    }
    let scalarSize: Int
    switch expectedCurve {
    case "nistp256": scalarSize = 32
    case "nistp384": scalarSize = 48
    case "nistp521": scalarSize = 66
    default: throw SSHAuthError.malformedECDSA("curve size")
    }
    if dBytes.count > scalarSize {
        throw SSHAuthError.malformedECDSA("scalar too large")
    }
    if dBytes.count < scalarSize {
        dBytes = [UInt8](repeating: 0, count: scalarSize - dBytes.count) + dBytes
    }
    return Data(dBytes)
}

@MainActor
final class SSHSession {
    enum State {
        case idle
        case connecting
        case connected
        case disconnected(Error?)
    }

    var onState: (State) -> Void = { _ in }
    var onData: (ArraySlice<UInt8>) -> Void = { _ in }
    /// Completion-style prompter for unknown host keys. Caller invokes the closure with the user's verdict.
    var hostKeyPrompter: HostKeyPrompter = { _, _, _, completion in completion(false) }

    private(set) var state: State = .idle {
        didSet { onState(state) }
    }

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var task: Task<Void, Never>?
    private var lastParams: ConnectParams?
    private var lastSize: (cols: Int, rows: Int) = (80, 24)

    var hasParams: Bool { lastParams != nil }

    var isLive: Bool {
        if case .connected = state { return true }
        if case .connecting = state { return true }
        return false
    }

    func connect(_ params: ConnectParams, cols: Int, rows: Int) {
        lastParams = params
        lastSize = (cols, rows)
        startConnect()
    }

    func reconnect() {
        guard lastParams != nil else { return }
        // Cancel anything in flight, then restart.
        task?.cancel()
        Task { [weak self] in
            try? await self?.client?.close()
            await MainActor.run { self?.startConnect() }
        }
    }

    private func startConnect() {
        guard let params = lastParams else { return }
        let (cols, rows) = lastSize
        state = .connecting

        task = Task {
            do {
                let method = try sshAuthMethod(username: params.username, auth: params.auth)
                let validator = HostKeyValidator(host: params.host, port: params.port, prompter: self.hostKeyPrompter)
                let client = try await SSHClient.connect(
                    host: params.host,
                    port: params.port,
                    authenticationMethod: method,
                    hostKeyValidator: .custom(validator),
                    reconnect: .never
                )
                self.client = client
                self.state = .connected

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: max(cols, 1),
                    terminalRowHeight: max(rows, 1),
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )

                try await client.withPTY(pty) { inbound, outbound in
                    await MainActor.run { self.writer = outbound }
                    for try await chunk in inbound {
                        let buf: ByteBuffer
                        switch chunk {
                        case .stdout(let b), .stderr(let b): buf = b
                        }
                        let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) ?? []
                        await MainActor.run { self.onData(bytes[...]) }
                    }
                }

                try? await client.close()
                self.writer = nil
                self.client = nil
                self.state = .disconnected(nil)
            } catch {
                self.writer = nil
                self.client = nil
                self.state = .disconnected(error)
            }
        }
    }

    func write(_ bytes: ArraySlice<UInt8>) {
        guard let writer else { return }
        let buf = ByteBuffer(bytes: bytes)
        Task { try? await writer.write(buf) }
    }

    func resize(cols: Int, rows: Int) {
        lastSize = (cols, rows)
        guard let writer else { return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func disconnect() {
        lastParams = nil
        guard let client else { return }
        Task { try? await client.close() }
    }
}
