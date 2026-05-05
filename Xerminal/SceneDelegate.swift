import UIKit
import CoreSpotlight

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var lockWindow: UIWindow?
    private var pendingHostID: UUID?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard scene is UIWindowScene else { return }
        window?.backgroundColor = SettingsStore.shared.current.theme.bg.uiColor
        window?.overrideUserInterfaceStyle = .dark
        if SettingsStore.shared.current.requireAuthOnLaunch {
            showLock(scene: scene)
        }
        // Cold-launch deep link from Spotlight.
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == CSSearchableItemActionType }) {
            extractHostID(from: activity)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let lock = lockWindow?.rootViewController as? AppLockViewController {
            lock.authenticate()
            return
        }
        deliverPendingHostID()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        if SettingsStore.shared.current.requireAuthOnLaunch {
            showLock(scene: scene)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}

    /// Active deep-link from Spotlight while running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == CSSearchableItemActionType {
            extractHostID(from: userActivity)
            deliverPendingHostID()
        }
    }

    private func extractHostID(from activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let uuid = UUID(uuidString: id) else { return }
        pendingHostID = uuid
    }

    private func deliverPendingHostID() {
        guard let id = pendingHostID else { return }
        guard let vc = window?.rootViewController as? ViewController else { return }
        pendingHostID = nil
        vc.connectToHost(id: id)
    }

    // MARK: - Lock window

    private func showLock(scene: UIScene) {
        guard lockWindow == nil, let windowScene = scene as? UIWindowScene else { return }
        let lock = AppLockViewController()
        lock.onUnlock = { [weak self] in
            self?.hideLock()
            self?.deliverPendingHostID()
        }
        let w = UIWindow(windowScene: windowScene)
        w.windowLevel = .alert + 1
        w.rootViewController = lock
        w.makeKeyAndVisible()
        lockWindow = w
    }

    private func hideLock() {
        lockWindow?.isHidden = true
        lockWindow = nil
        window?.makeKeyAndVisible()
    }
}
