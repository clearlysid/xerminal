import Foundation

@MainActor
final class TabManager {
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex: Int = 0

    /// Fires after any structural change (add/remove/switch).
    var onChange: () -> Void = {}

    var activeTab: Tab? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }

    @discardableResult
    func newTab() -> Tab {
        let tab = Tab()
        tab.onTitleChange = { [weak self] in self?.onChange() }
        tabs.append(tab)
        activeIndex = tabs.count - 1
        onChange()
        return tab
    }

    func close(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        tab.session.disconnect()
        tabs.remove(at: idx)
        if tabs.isEmpty {
            activeIndex = 0
        } else if idx <= activeIndex {
            activeIndex = max(0, activeIndex - 1)
        }
        onChange()
    }

    func switchTo(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard idx != activeIndex else { return }
        activeIndex = idx
        onChange()
    }

    func switchTo(index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        activeIndex = index
        onChange()
    }

    func nextTab() {
        guard tabs.count > 1 else { return }
        activeIndex = (activeIndex + 1) % tabs.count
        onChange()
    }

    func prevTab() {
        guard tabs.count > 1 else { return }
        activeIndex = (activeIndex - 1 + tabs.count) % tabs.count
        onChange()
    }
}
