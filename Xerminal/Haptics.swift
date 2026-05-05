import UIKit

@MainActor
enum Haptics {
    static func tap()   { play(.light) }
    static func clack() { play(.medium) }
    static func snap()  { play(.rigid) }

    private static func play(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard SettingsStore.shared.current.haptics else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.impactOccurred()
    }
}
