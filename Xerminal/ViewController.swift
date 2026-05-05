import UIKit
import SwiftTerm

class ViewController: UIViewController, TerminalViewDelegate {

    private let tabs = TabManager()
    private let network = NetworkMonitor()
    private var lastSatisfied = true

    private let tabBar = TerminalTabBarView()
    private let container = UIView()

    private var hasShownInitialList = false

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .black
        view.addSubview(tabBar)
        view.addSubview(container)
        let pad: CGFloat = 8
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: pad),
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: pad),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -pad),
            tabBar.topAnchor.constraint(equalTo: container.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: pad),
            tabBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -pad),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        tabs.onChange = { [weak self] in
            self?.applyTabs()
            self?.persistTabs()
        }
        tabBar.onSelect = { [weak self] id in
            self?.tabs.switchTo(id: id)
            Haptics.tap()
        }
        tabBar.onClose = { [weak self] id in
            self?.closeTab(id: id)
            Haptics.clack()
        }
        tabBar.onCloseOthers = { [weak self] id in
            self?.closeOtherTabs(keep: id)
            Haptics.clack()
        }
        tabBar.onNew = { [weak self] in
            self?.newTabAndPickHost()
            Haptics.tap()
        }

        network.onChange = { [weak self] satisfied in
            self?.handleNetwork(satisfied: satisfied)
        }
        network.start()

        SettingsStore.shared.onChange = { [weak self] _ in
            self?.applySettingsToAllTabs()
        }
        applyThemeChrome()
    }

    private func applySettingsToAllTabs() {
        for tab in tabs.tabs {
            SettingsStore.shared.apply(to: tab.terminalView)
        }
        if let active = tabs.activeTab {
            tabBar.font = active.terminalView.font
        }
        applyThemeChrome()
    }

    /// Push theme bg/fg into the surrounding chrome (root view, container, tab bar).
    private func applyThemeChrome() {
        let theme = SettingsStore.shared.current.theme
        let bg = theme.bg.uiColor
        let fg = theme.fg.uiColor
        view.backgroundColor = bg
        container.backgroundColor = bg
        tabBar.bgColor = bg
        tabBar.fgColor = fg
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasShownInitialList {
            hasShownInitialList = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.bootstrapInitialTabs()
            }
        }
    }

    /// First-scene bootstrap: restore persisted tabs, or fall back to a fresh empty tab + Hosts sheet.
    private func bootstrapInitialTabs() {
        if Self.didRestoreOnce {
            // Subsequent windows on top of existing scene → fresh empty tab.
            newTabAndPickHost()
            return
        }
        Self.didRestoreOnce = true

        guard let saved = SessionPersistence.load(), !saved.hostIDs.isEmpty else {
            newTabAndPickHost()
            return
        }

        let store = HostStore.shared
        var restored = 0
        for hostID in saved.hostIDs {
            guard let host = store.hosts.first(where: { $0.id == hostID }),
                  let params = store.makeParams(for: host) else {
                continue
            }
            let tab = tabs.newTab()
            wire(tab)
            tab.storedHostID = host.id
            tab.setTitle("\(host.username)@\(host.host)")
            if tabBar.font != tab.terminalView.font {
                tabBar.font = tab.terminalView.font
            }
            feedBanner(tab, "xerminal — restoring \(host.username)@\(host.host)\r\n")
            let term = tab.terminalView.getTerminal()
            tab.session.connect(params, cols: term.cols, rows: term.rows)
            restored += 1
        }

        if restored == 0 {
            newTabAndPickHost()
            return
        }

        let activeIdx = max(0, min(saved.activeHostIndex, tabs.tabs.count - 1))
        tabs.switchTo(index: activeIdx)
    }

    /// Process-wide flag — only the first scene to fire restores the persisted tab list.
    nonisolated(unsafe) private static var didRestoreOnce = false

    private func persistTabs() {
        let hostIDs = tabs.tabs.compactMap { $0.storedHostID }
        let activeHostID = tabs.activeTab?.storedHostID
        let activeIndex = activeHostID.flatMap { hostIDs.firstIndex(of: $0) } ?? -1
        SessionPersistence.save(PersistedTabs(hostIDs: hostIDs, activeHostIndex: activeIndex))
    }

    // MARK: - Tab orchestration

    private func newTabAndPickHost() {
        let tab = tabs.newTab()
        wire(tab)
        // Match bar font to terminal font (only needs setting once, but cheap to repeat).
        if tabBar.font != tab.terminalView.font {
            tabBar.font = tab.terminalView.font
        }
        feedBanner(tab, "xerminal\r\n")
        presentHostListSheet()
    }

    private func wire(_ tab: Tab) {
        tab.terminalView.terminalDelegate = self
        tab.session.onState = { [weak self, weak tab] state in
            self?.handle(state, tab: tab)
        }
        tab.session.hostKeyPrompter = { [weak self] host, port, fp, completion in
            DispatchQueue.main.async {
                self?.askTrust(host: host, port: port, fingerprint: fp, completion: completion)
                    ?? completion(false)
            }
        }
    }

    @MainActor
    private func askTrust(host: String, port: Int, fingerprint: String,
                          completion: @escaping @Sendable (Bool) -> Void) {
        let alert = UIAlertController(
            title: "First connection",
            message: "\(host):\(port)\n\nServer fingerprint:\n\(fingerprint)\n\nTrust this host?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Trust", style: .default) { _ in completion(true) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        let presenter = topMostPresenter()
        presenter.present(alert, animated: true)
    }

    private func topMostPresenter() -> UIViewController {
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        return top
    }

    private func closeTab(id: UUID) {
        tabs.close(id: id)
        if tabs.tabs.isEmpty {
            // Always keep at least one tab.
            newTabAndPickHost()
        }
    }

    private func closeOtherTabs(keep id: UUID) {
        let others = tabs.tabs.filter { $0.id != id }.map(\.id)
        for otherID in others {
            tabs.close(id: otherID)
        }
    }

    private func applyTabs() {
        // Update bar items.
        tabBar.items = tabs.tabs.map { TabBarItem(id: $0.id, title: $0.title) }
        tabBar.activeID = tabs.activeTab?.id

        // Swap visible terminal view.
        for sub in container.subviews {
            sub.removeFromSuperview()
        }
        guard let active = tabs.activeTab else { return }
        active.terminalView.frame = container.bounds
        active.terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(active.terminalView)
        _ = active.terminalView.becomeFirstResponder()
    }

    // MARK: - Host list / connect

    private func presentHostListSheet() {
        if presentedViewController != nil { return }
        let list = HostListViewController()
        list.onConnect = { [weak self] params, storedHostID in
            self?.connectActiveTab(params, storedHostID: storedHostID)
        }
        let nav = UINavigationController(rootViewController: list)
        nav.modalPresentationStyle = .formSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func connectActiveTab(_ params: ConnectParams, storedHostID: UUID?) {
        guard let tab = tabs.activeTab else { return }
        let term = tab.terminalView.getTerminal()
        feedBanner(tab, "connecting to \(params.username)@\(params.host):\(params.port)...\r\n")
        tab.setTitle("\(params.username)@\(params.host)")
        tab.storedHostID = storedHostID
        tab.session.connect(params, cols: term.cols, rows: term.rows)
        persistTabs()
    }

    /// Spotlight / external deep-link entry point.
    func connectToHost(id: UUID) {
        let store = HostStore.shared
        guard let host = store.hosts.first(where: { $0.id == id }) else { return }
        guard let params = store.makeParams(for: host) else { return }
        // If the active tab is empty (no session), reuse it. Otherwise spawn a new tab.
        if let active = tabs.activeTab, !active.session.hasParams && !active.session.isLive {
            // active tab already wired (created by bootstrap or newTab); just connect.
        } else {
            let tab = tabs.newTab()
            wire(tab)
            if tabBar.font != tab.terminalView.font {
                tabBar.font = tab.terminalView.font
            }
        }
        // Dismiss any presented sheet (Hosts) before connecting so banner is visible.
        if let presented = presentedViewController {
            presented.dismiss(animated: false)
        }
        connectActiveTab(params, storedHostID: host.id)
        Haptics.tap()
    }

    private func handle(_ state: SSHSession.State, tab: Tab?) {
        guard let tab else { return }
        switch state {
        case .idle, .connecting: break
        case .connected:
            Haptics.tap()
        case .disconnected(let err):
            if let err {
                feedBanner(tab, "\r\n[disconnected: \(err)]\r\n")
            } else {
                feedBanner(tab, "\r\n[disconnected]\r\n")
            }
            Haptics.clack()
        }
    }

    private func handleNetwork(satisfied: Bool) {
        if !satisfied {
            lastSatisfied = false
            for tab in tabs.tabs where tab.session.isLive {
                feedBanner(tab, "\r\n[network lost]\r\n")
            }
            return
        }
        let wasOffline = !lastSatisfied
        lastSatisfied = true
        guard wasOffline else { return }
        for tab in tabs.tabs where tab.session.hasParams {
            feedBanner(tab, "\r\n[network back, reconnecting...]\r\n")
            tab.session.reconnect()
        }
    }

    private func feedBanner(_ tab: Tab, _ s: String) {
        tab.terminalView.feed(text: s)
    }

    // MARK: - Keyboard shortcuts

    override var keyCommands: [UIKeyCommand]? {
        var cmds: [UIKeyCommand] = [
            UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(cmdNewTab)),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(cmdCloseTab)),
            UIKeyCommand(input: "[", modifierFlags: [.command, .shift], action: #selector(cmdPrevTab)),
            UIKeyCommand(input: "]", modifierFlags: [.command, .shift], action: #selector(cmdNextTab)),
            UIKeyCommand(input: ",", modifierFlags: .command, action: #selector(cmdSettings)),
            UIKeyCommand(input: "T", modifierFlags: [.command, .shift], action: #selector(cmdNextTheme)),
            UIKeyCommand(input: "+", modifierFlags: .command, action: #selector(cmdFontUp)),
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(cmdFontUp)),
            UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(cmdFontDown)),
        ]
        for i in 1...9 {
            cmds.append(UIKeyCommand(input: "\(i)", modifierFlags: .command, action: #selector(cmdSwitchTab(_:))))
        }
        return cmds
    }

    @objc private func cmdNewTab() { newTabAndPickHost() }
    @objc private func cmdCloseTab() {
        guard let id = tabs.activeTab?.id else { return }
        closeTab(id: id)
    }
    @objc private func cmdPrevTab() { tabs.prevTab() }
    @objc private func cmdNextTab() { tabs.nextTab() }
    @objc private func cmdSwitchTab(_ sender: UIKeyCommand) {
        guard let s = sender.input, let n = Int(s) else { return }
        tabs.switchTo(index: n - 1)
    }
    @objc private func cmdSettings() { presentSettingsSheet() }
    @objc private func cmdNextTheme() {
        SettingsStore.shared.cycleTheme()
        Haptics.tap()
    }
    @objc private func cmdFontUp()   { SettingsStore.shared.bumpFontSize(by: +1) }
    @objc private func cmdFontDown() { SettingsStore.shared.bumpFontSize(by: -1) }

    func presentSettingsSheet() {
        if let presented = presentedViewController {
            presented.dismiss(animated: false)
        }
        let s = SettingsViewController()
        let nav = UINavigationController(rootViewController: s)
        nav.modalPresentationStyle = .formSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - TerminalViewDelegate
    // Routed by which TerminalView is the source.

    private func tab(for source: TerminalView) -> Tab? {
        tabs.tabs.first { $0.terminalView === source }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        tab(for: source)?.session.write(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        tab(for: source)?.session.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
