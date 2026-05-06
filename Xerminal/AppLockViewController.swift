import UIKit
import LocalAuthentication

final class AppLockViewController: UIViewController {

    var onUnlock: () -> Void = {}
    var authenticatesOnAppear = true

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "xerminal"
        l.font = .monospacedSystemFont(ofSize: 22, weight: .regular)
        l.textColor = .lightGray
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let lockIcon: UIImageView = {
        let cfg = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        let v = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: cfg))
        v.tintColor = .lightGray
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let unlockButton: UIButton = {
        var cfg = UIButton.Configuration.tinted()
        cfg.title = "Unlock"
        cfg.baseForegroundColor = .white
        cfg.baseBackgroundColor = UIColor(white: 0.2, alpha: 1)
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private var isAuthenticating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let stack = UIStackView(arrangedSubviews: [lockIcon, titleLabel, unlockButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        unlockButton.addTarget(self, action: #selector(authenticate), for: .touchUpInside)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if authenticatesOnAppear {
            authenticate()
        }
    }

    @objc func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"

        var biometricError: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) {
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock xerminal") { [weak self] ok, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if ok {
                        self.isAuthenticating = false
                        self.onUnlock()
                        return
                    }

                    let code = (error as? LAError)?.code
                    if code == .userFallback || code == .biometryLockout {
                        self.evaluateDevicePasscode()
                    } else {
                        self.isAuthenticating = false
                    }
                }
            }
            return
        }

        evaluateDevicePasscode()
    }

    private func evaluateDevicePasscode() {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock xerminal") { [weak self] ok, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isAuthenticating = false
                    if ok { self.onUnlock() }
                }
            }
        } else {
            // No biometrics + no passcode set on device → unlock anyway.
            isAuthenticating = false
            onUnlock()
        }
    }
}
