import UIKit
import SwiftTerm

enum CursorShape: String, Codable, CaseIterable {
    case block, underline, bar
}

struct AppSettings: Codable, Equatable {
    var themeName: String
    var fontName: String         // "System" or PostScript name like "Menlo"
    var fontSize: CGFloat
    var cursorShape: CursorShape
    var cursorBlink: Bool
    var requireAuthOnLaunch: Bool
    var haptics: Bool
    var showInputAccessory: Bool

    static let `default` = AppSettings(
        themeName: Theme.kakuDark.name,
        fontName: "System",
        fontSize: 13,
        cursorShape: .block,
        cursorBlink: true,
        requireAuthOnLaunch: false,
        haptics: true,
        showInputAccessory: false
    )

    init(themeName: String, fontName: String, fontSize: CGFloat,
         cursorShape: CursorShape, cursorBlink: Bool,
         requireAuthOnLaunch: Bool, haptics: Bool, showInputAccessory: Bool) {
        self.themeName = themeName
        self.fontName = fontName
        self.fontSize = fontSize
        self.cursorShape = cursorShape
        self.cursorBlink = cursorBlink
        self.requireAuthOnLaunch = requireAuthOnLaunch
        self.haptics = haptics
        self.showInputAccessory = showInputAccessory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName) ?? d.themeName
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? d.fontSize
        cursorShape = try c.decodeIfPresent(CursorShape.self, forKey: .cursorShape) ?? d.cursorShape
        cursorBlink = try c.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? d.cursorBlink
        requireAuthOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .requireAuthOnLaunch) ?? d.requireAuthOnLaunch
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        showInputAccessory = try c.decodeIfPresent(Bool.self, forKey: .showInputAccessory) ?? d.showInputAccessory
    }

    static let availableFonts: [String] = [
        "System",
        "Menlo",
        "Courier",
        "Courier New",
        // Bundled (PostScript names)
        "JetBrainsMono-Regular",
        "FiraCode-Regular",
        "IBMPlexMono",
        "CascadiaCode-Regular",
    ]

    /// Pretty display name for the picker.
    static func displayName(for fontName: String) -> String {
        switch fontName {
        case "JetBrainsMono-Regular": return "JetBrains Mono"
        case "FiraCode-Regular":      return "Fira Code"
        case "IBMPlexMono":           return "IBM Plex Mono"
        case "CascadiaCode-Regular":  return "Cascadia Code"
        default: return fontName
        }
    }

    var theme: Theme { Theme.named(themeName) }

    var font: UIFont {
        if fontName == "System" {
            return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return UIFont(name: fontName, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var swiftTermCursorStyle: CursorStyle {
        switch (cursorShape, cursorBlink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        }
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let key = "xerminal.settings.v1"
    private(set) var current: AppSettings

    var onChange: (AppSettings) -> Void = { _ in }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.current = s
        } else {
            self.current = .default
        }
    }

    static let didChangeNotification = Notification.Name("xerminal.settings.didChange")

    func update(_ mutate: (inout AppSettings) -> Void) {
        var s = current
        mutate(&s)
        guard s != current else { return }
        current = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
        onChange(s)
        NotificationCenter.default.post(name: SettingsStore.didChangeNotification, object: self)
    }

    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 32

    func cycleTheme() {
        let names = Theme.bundled.map(\.name)
        guard !names.isEmpty else { return }
        let i = names.firstIndex(of: current.themeName) ?? 0
        let next = names[(i + 1) % names.count]
        update { $0.themeName = next }
    }

    func bumpFontSize(by delta: CGFloat) {
        let target = (current.fontSize + delta)
            .clamped(to: SettingsStore.minFontSize...SettingsStore.maxFontSize)
        update { $0.fontSize = target }
    }

    /// Apply current theme/font/cursor to a TerminalView.
    func apply(to view: TerminalView) {
        let s = current
        s.theme.apply(to: view)
        view.font = s.font
        view.getTerminal().setCursorStyle(s.swiftTermCursorStyle)
        applyInputAccessory(to: view, show: s.showInputAccessory)
    }

    func applyInputAccessory(to view: TerminalView, show: Bool) {
        if show {
            if view.inputAccessoryView == nil {
                let h: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 36 : 48
                let ta = TerminalAccessory(
                    frame: CGRect(x: 0, y: 0, width: view.frame.width, height: h),
                    inputViewStyle: .keyboard,
                    container: view)
                ta.sizeToFit()
                view.inputAccessoryView = ta
            }
        } else {
            view.inputAccessoryView = nil
        }
        if view.isFirstResponder {
            view.reloadInputViews()
        }
    }
}
