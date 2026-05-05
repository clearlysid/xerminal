import UIKit

enum SSHAuth {
    case password(String)
    case privateKey(pem: String, passphrase: String?)
}

struct ConnectParams {
    var host: String
    var port: Int
    var username: String
    var auth: SSHAuth
}

enum ConnectMode {
    case transient
    case save
    case edit(StoredHost)
}

enum ConnectIntent {
    case transient
    case save(label: String)
    case update(StoredHost, label: String)
}

final class ConnectViewController: UIViewController {

    var onSubmit: ((ConnectParams, ConnectIntent) -> Void)?
    var onCancel: (() -> Void)?

    private let mode: ConnectMode

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let labelField = makeField(placeholder: "label (e.g. prod-db)")
    private let hostField = makeField(placeholder: "host")
    private let portField = makeField(placeholder: "22", keyboard: .numberPad)
    private let userField = makeField(placeholder: "user")
    private let authSegment = UISegmentedControl(items: ["password", "key"])

    private let saveToggle = UISwitch()
    private let saveToggleLabel: UILabel = {
        let l = UILabel()
        l.text = "Save host"
        l.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        return l
    }()

    private let passField: UITextField = {
        let f = makeField(placeholder: "password")
        f.isSecureTextEntry = true
        return f
    }()

    private let keyView: UITextView = {
        let tv = UITextView()
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.layer.borderWidth = 1
        tv.layer.cornerRadius = 6
        tv.heightAnchor.constraint(equalToConstant: 180).isActive = true
        return tv
    }()

    private let keyPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "-----BEGIN OPENSSH PRIVATE KEY-----"
        l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .tertiaryLabel
        return l
    }()

    private let passphraseField: UITextField = {
        let f = makeField(placeholder: "passphrase (optional)")
        f.isSecureTextEntry = true
        return f
    }()

    private var labelRow: UIView!
    private var saveRow: UIView!
    private var passwordRow: UIView!
    private var keyBlock: UIStackView!

    init(mode: ConnectMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        switch mode {
        case .transient: title = "Quick Connect"
        case .save:      title = "Add Host"
        case .edit:      title = "Edit Host"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Connect", style: .done, target: self, action: #selector(connect))

        authSegment.selectedSegmentIndex = 1
        authSegment.addTarget(self, action: #selector(authChanged), for: .valueChanged)

        labelRow = row("label", labelField)
        saveRow = makeSaveRow()
        passwordRow = row("pass", passField)

        let keyContainer = UIView()
        keyContainer.addSubview(keyView)
        keyContainer.addSubview(keyPlaceholder)
        keyView.translatesAutoresizingMaskIntoConstraints = false
        keyPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keyView.topAnchor.constraint(equalTo: keyContainer.topAnchor),
            keyView.bottomAnchor.constraint(equalTo: keyContainer.bottomAnchor),
            keyView.leadingAnchor.constraint(equalTo: keyContainer.leadingAnchor),
            keyView.trailingAnchor.constraint(equalTo: keyContainer.trailingAnchor),
            keyPlaceholder.topAnchor.constraint(equalTo: keyView.topAnchor, constant: 8),
            keyPlaceholder.leadingAnchor.constraint(equalTo: keyView.leadingAnchor, constant: 6),
        ])
        keyView.delegate = self

        keyBlock = UIStackView(arrangedSubviews: [keyContainer, passphraseField])
        keyBlock.axis = .vertical
        keyBlock.spacing = 8

        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(labelRow)
        stack.addArrangedSubview(row("host", hostField))
        stack.addArrangedSubview(row("port", portField))
        stack.addArrangedSubview(row("user", userField))
        stack.addArrangedSubview(authSegment)
        stack.addArrangedSubview(passwordRow)
        stack.addArrangedSubview(keyBlock)
        stack.addArrangedSubview(saveRow)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        applyAuthMode()
        applyMode()
    }

    private func makeSaveRow() -> UIView {
        saveToggle.addTarget(self, action: #selector(saveToggleChanged), for: .valueChanged)
        let h = UIStackView(arrangedSubviews: [saveToggleLabel, UIView(), saveToggle])
        h.axis = .horizontal
        h.alignment = .center
        h.spacing = 12
        return h
    }

    @objc private func saveToggleChanged() {
        applyMode()
    }

    private func applyMode() {
        switch mode {
        case .transient:
            labelRow.isHidden = !saveToggle.isOn
            saveRow.isHidden = false
        case .save:
            labelRow.isHidden = false
            saveRow.isHidden = true
        case .edit(let host):
            labelRow.isHidden = false
            saveRow.isHidden = true
            // Prefill from host (creds hydrated separately, see below)
            labelField.text = host.label
            hostField.text = host.host
            portField.text = String(host.port)
            userField.text = host.username
            switch host.authRef {
            case .password:
                authSegment.selectedSegmentIndex = 0
                if let data = Keychain.get(account: host.pwAccount),
                   let pw = String(data: data, encoding: .utf8) {
                    passField.text = pw
                }
            case .privateKey(let hasPP):
                authSegment.selectedSegmentIndex = 1
                if let data = Keychain.get(account: host.pemAccount),
                   let pem = String(data: data, encoding: .utf8) {
                    keyView.text = pem
                    keyPlaceholder.isHidden = !pem.isEmpty
                }
                if hasPP, let data = Keychain.get(account: host.ppAccount),
                   let pp = String(data: data, encoding: .utf8) {
                    passphraseField.text = pp
                }
            }
            applyAuthMode()
        }
    }

    private func row(_ label: String, _ field: UIView) -> UIView {
        let l = UILabel()
        l.text = label
        l.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        l.textColor = .secondaryLabel
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let h = UIStackView(arrangedSubviews: [l, field])
        h.axis = .horizontal
        h.spacing = 12
        h.alignment = .center
        return h
    }

    @objc private func authChanged() { applyAuthMode() }

    private func applyAuthMode() {
        let usePassword = authSegment.selectedSegmentIndex == 0
        passwordRow.isHidden = !usePassword
        keyBlock.isHidden = usePassword
    }

    @objc private func cancel() {
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func connect() {
        let host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let user = userField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let port = Int(portField.text ?? "") ?? 22
        guard !host.isEmpty, !user.isEmpty else { return }

        let auth: SSHAuth
        if authSegment.selectedSegmentIndex == 0 {
            auth = .password(passField.text ?? "")
        } else {
            let pem = keyView.text ?? ""
            guard !pem.isEmpty else { return }
            let pp = passphraseField.text?.isEmpty == true ? nil : passphraseField.text
            auth = .privateKey(pem: pem, passphrase: pp)
        }

        let params = ConnectParams(host: host, port: port, username: user, auth: auth)

        let intent: ConnectIntent
        switch mode {
        case .transient:
            let label = labelField.text?.trimmingCharacters(in: .whitespaces) ?? ""
            if saveToggle.isOn && !label.isEmpty {
                intent = .save(label: label)
            } else {
                intent = .transient
            }
        case .save:
            let label = labelField.text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !label.isEmpty else { return }
            intent = .save(label: label)
        case .edit(let h):
            let label = labelField.text?.trimmingCharacters(in: .whitespaces) ?? h.label
            intent = .update(h, label: label)
        }

        onSubmit?(params, intent)
        dismiss(animated: true)
    }
}

extension ConnectViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        keyPlaceholder.isHidden = !(textView.text?.isEmpty ?? true)
    }
}

private func makeField(placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
    let f = UITextField()
    f.placeholder = placeholder
    f.borderStyle = .roundedRect
    f.autocorrectionType = .no
    f.autocapitalizationType = .none
    f.keyboardType = keyboard
    f.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    return f
}
