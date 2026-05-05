import UIKit
import SwiftTerm

@MainActor
final class Tab: Identifiable {
    let id = UUID()
    let session = SSHSession()
    let terminalView: TerminalView
    var title: String = "—"
    var storedHostID: UUID?   // Set when this tab is connected to a saved host.

    var onTitleChange: () -> Void = {}

    init() {
        terminalView = TerminalView(frame: .zero)
        terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminalView.translatesAutoresizingMaskIntoConstraints = true
        SettingsStore.shared.apply(to: terminalView)

        session.onData = { [weak self] bytes in
            self?.terminalView.feed(byteArray: bytes)
        }
    }

    func setTitle(_ s: String) {
        guard title != s else { return }
        title = s
        onTitleChange()
    }
}
