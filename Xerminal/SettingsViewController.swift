import UIKit

final class SettingsViewController: UITableViewController {

    private let store = SettingsStore.shared

    private enum Section: Int, CaseIterable {
        case theme, font, fontSize, cursorShape, cursorBlink, inputAccessory, haptics, security, knownHosts
    }

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SliderCell.self, forCellReuseIdentifier: "slider")
        tableView.register(SegmentCell.self, forCellReuseIdentifier: "segment")
        tableView.register(ToggleCell.self, forCellReuseIdentifier: "toggle")
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalChange),
            name: SettingsStore.didChangeNotification, object: nil)
    }

    @objc private func externalChange() {
        tableView.reloadSections(
            IndexSet([Section.theme.rawValue, Section.font.rawValue, Section.fontSize.rawValue]),
            with: .none)
    }

    @objc private func close() { dismiss(animated: true) }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .theme: return "Theme"
        case .font: return "Font"
        case .fontSize: return "Font size"
        case .cursorShape: return "Cursor"
        case .cursorBlink: return nil
        case .inputAccessory: return "Input"
        case .haptics: return "Feedback"
        case .security: return "Security"
        case .knownHosts: return "Known Hosts"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .theme: return Theme.bundled.count
        case .font: return AppSettings.availableFonts.count
        case .fontSize, .cursorShape, .cursorBlink, .inputAccessory, .haptics, .security: return 1
        case .knownHosts: return KnownHostsStore.shared.count == 0 ? 1 : 2
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let s = store.current
        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let theme = Theme.bundled[indexPath.row]
            var cfg = cell.defaultContentConfiguration()
            cfg.text = theme.name
            cell.contentConfiguration = cfg
            cell.accessoryType = (theme.name == s.themeName) ? .checkmark : .none
            return cell
        case .font:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let name = AppSettings.availableFonts[indexPath.row]
            var cfg = cell.defaultContentConfiguration()
            cfg.text = AppSettings.displayName(for: name)
            let preview = (name == "System")
                ? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                : UIFont(name: name, size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
            cfg.textProperties.font = preview
            cell.contentConfiguration = cfg
            cell.accessoryType = (name == s.fontName) ? .checkmark : .none
            return cell
        case .fontSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: "slider", for: indexPath) as! SliderCell
            cell.configure(value: Float(s.fontSize), min: 9, max: 22) { [weak self] v in
                self?.store.update { $0.fontSize = CGFloat(round(v)) }
                if let header = self?.tableView.headerView(forSection: Section.fontSize.rawValue) {
                    header.textLabel?.text = "Font size — \(Int(round(v)))pt"
                    header.textLabel?.sizeToFit()
                }
            }
            return cell
        case .cursorShape:
            let cell = tableView.dequeueReusableCell(withIdentifier: "segment", for: indexPath) as! SegmentCell
            cell.configure(items: ["block", "underline", "bar"],
                           selected: CursorShape.allCases.firstIndex(of: s.cursorShape) ?? 0) { [weak self] idx in
                let shape = CursorShape.allCases[idx]
                self?.store.update { $0.cursorShape = shape }
            }
            return cell
        case .cursorBlink:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath) as! ToggleCell
            cell.configure(title: "Blink", isOn: s.cursorBlink) { [weak self] on in
                self?.store.update { $0.cursorBlink = on }
            }
            return cell
        case .inputAccessory:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath) as! ToggleCell
            cell.configure(title: "Show input toolbar", isOn: s.showInputAccessory) { [weak self] on in
                self?.store.update { $0.showInputAccessory = on }
            }
            return cell
        case .haptics:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath) as! ToggleCell
            cell.configure(title: "Haptics", isOn: s.haptics) { [weak self] on in
                self?.store.update { $0.haptics = on }
            }
            return cell
        case .security:
            let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath) as! ToggleCell
            cell.configure(title: "Require Face ID / passcode", isOn: s.requireAuthOnLaunch) { [weak self] on in
                self?.store.update { $0.requireAuthOnLaunch = on }
            }
            return cell
        case .knownHosts:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var cfg = cell.defaultContentConfiguration()
            let n = KnownHostsStore.shared.count
            if indexPath.row == 0 {
                cfg.text = n == 0 ? "No trusted hosts yet" : "\(n) trusted host\(n == 1 ? "" : "s")"
                cfg.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
                cell.accessoryType = .none
            } else {
                cfg.text = "Clear All"
                cfg.textProperties.color = .systemRed
                cell.selectionStyle = .default
                cell.accessoryType = .none
            }
            cell.contentConfiguration = cfg
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let theme = Theme.bundled[indexPath.row]
            store.update { $0.themeName = theme.name }
            tableView.reloadSections([Section.theme.rawValue], with: .none)
        case .font:
            let name = AppSettings.availableFonts[indexPath.row]
            store.update { $0.fontName = name }
            tableView.reloadSections([Section.font.rawValue], with: .none)
        case .knownHosts:
            if indexPath.row == 1 {
                confirmClearKnownHosts()
            }
        default: break
        }
    }

    private func confirmClearKnownHosts() {
        let alert = UIAlertController(
            title: "Clear all known hosts?",
            message: "Every server will prompt for trust on its next connect.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            KnownHostsStore.shared.clear()
            self?.tableView.reloadSections([Section.knownHosts.rawValue], with: .automatic)
        })
        present(alert, animated: true)
    }
}

// MARK: - Reusable cells

private final class SliderCell: UITableViewCell {
    private let slider = UISlider()
    private var onChange: (Float) -> Void = { _ in }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        slider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(slider)
        NSLayoutConstraint.activate([
            slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            slider.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)
        selectionStyle = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(value: Float, min: Float, max: Float, onChange: @escaping (Float) -> Void) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        self.onChange = onChange
    }

    @objc private func changed() { onChange(slider.value) }
}

private final class SegmentCell: UITableViewCell {
    private let seg = UISegmentedControl()
    private var onChange: (Int) -> Void = { _ in }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        seg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(seg)
        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            seg.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            seg.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            seg.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        seg.addTarget(self, action: #selector(changed), for: .valueChanged)
        selectionStyle = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(items: [String], selected: Int, onChange: @escaping (Int) -> Void) {
        seg.removeAllSegments()
        for (i, t) in items.enumerated() {
            seg.insertSegment(withTitle: t, at: i, animated: false)
        }
        seg.selectedSegmentIndex = selected
        self.onChange = onChange
    }

    @objc private func changed() { onChange(seg.selectedSegmentIndex) }
}

private final class ToggleCell: UITableViewCell {
    private let label = UILabel()
    private let toggle = UISwitch()
    private var onChange: (Bool) -> Void = { _ in }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        contentView.addSubview(toggle)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        toggle.addTarget(self, action: #selector(changed), for: .valueChanged)
        selectionStyle = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        label.text = title
        toggle.isOn = isOn
        self.onChange = onChange
    }

    @objc private func changed() { onChange(toggle.isOn) }
}
