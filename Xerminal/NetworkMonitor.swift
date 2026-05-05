import Foundation
import Network

@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "xerminal.network")
    private var lastSatisfied: Bool?

    /// Fires once on each transition. `true` = path became satisfied (reconnect candidate).
    var onChange: (Bool) -> Void = { _ in }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.lastSatisfied != satisfied {
                    self.lastSatisfied = satisfied
                    self.onChange(satisfied)
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
