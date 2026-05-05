import UIKit

final class HostListViewController: UITableViewController {

    /// Called when user picks (or quick-connects to) a host. Sheet auto-dismisses before the call.
    /// `storedHostID` is non-nil when the params come from (or were just saved as) a `StoredHost`.
    var onConnect: ((ConnectParams, UUID?) -> Void)?

    private let store = HostStore.shared

    init() {
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hosts"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close))
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addHost))
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"),
                                       style: .plain, target: self, action: #selector(openSettings))
        navigationItem.rightBarButtonItems = [add, settings]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        store.onChange = { [weak self] in self?.tableView.reloadData() }
    }

    @objc private func openSettings() {
        let s = SettingsViewController()
        navigationController?.pushViewController(s, animated: true)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func addHost() {
        pushConnect(mode: .save)
    }

    private func pushConnect(mode: ConnectMode) {
        let cvc = ConnectViewController(mode: mode)
        cvc.onSubmit = { [weak self] params, intent in
            guard let self else { return }
            self.handleSubmit(params: params, intent: intent)
        }
        navigationController?.pushViewController(cvc, animated: true)
    }

    private func handleSubmit(params: ConnectParams, intent: ConnectIntent) {
        var storedID: UUID?
        switch intent {
        case .transient:
            break
        case .save(let label):
            storedID = store.add(label: label, params: params).id
        case .update(let host, let label):
            storedID = store.update(host, label: label, params: params).id
        }
        let outID = storedID
        dismiss(animated: true) { [weak self] in
            self?.onConnect?(params, outID)
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : store.hosts.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? nil : "Saved"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var cfg = UIListContentConfiguration.subtitleCell()
        if indexPath.section == 0 {
            cfg.text = "Quick Connect"
            cfg.image = UIImage(systemName: "bolt.fill")
            cell.accessoryType = .disclosureIndicator
        } else {
            let host = store.hosts[indexPath.row]
            cfg.text = host.label
            cfg.secondaryText = host.subtitle
            cell.accessoryType = .detailDisclosureButton
        }
        cell.contentConfiguration = cfg
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            pushConnect(mode: .transient)
            return
        }
        let host = store.hosts[indexPath.row]
        guard let params = store.makeParams(for: host) else {
            credsMissing(for: host)
            return
        }
        dismiss(animated: true) { [weak self] in
            self?.onConnect?(params, host.id)
        }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        let host = store.hosts[indexPath.row]
        pushConnect(mode: .edit(host))
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let host = store.hosts[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.store.delete(host)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func credsMissing(for host: StoredHost) {
        let alert = UIAlertController(
            title: "Credentials missing",
            message: "Stored secrets for \(host.label) couldn't be loaded. Re-enter to fix.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
            self?.pushConnect(mode: .edit(host))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
