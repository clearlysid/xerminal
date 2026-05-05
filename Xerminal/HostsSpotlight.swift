import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

@MainActor
enum HostsSpotlight {
    static let domain = "com.xerminal.hosts"

    static func indexAll(_ hosts: [StoredHost]) {
        let items = hosts.map(makeItem(for:))
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func index(_ host: StoredHost) {
        CSSearchableIndex.default().indexSearchableItems([makeItem(for: host)])
    }

    static func remove(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
    }

    private static func makeItem(for host: StoredHost) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = host.label
        attrs.contentDescription = host.subtitle
        attrs.keywords = [host.host, host.username, "ssh", "xerminal"]
        let item = CSSearchableItem(uniqueIdentifier: host.id.uuidString,
                                    domainIdentifier: domain,
                                    attributeSet: attrs)
        return item
    }
}
