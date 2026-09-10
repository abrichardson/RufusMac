import Foundation

/// One entry in the built-in ISO catalog.
public struct CatalogEntry: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let category: String      // Linux · Security · Utility · Windows
    public let summary: String
    public let pageURL: String       // official download page
    public let directURL: String?    // direct ISO link when stably available
    public let kindRaw: String       // "Linux" | "Windows" | "Disk image"

    public var kind: ImageKind { ImageKind(rawValue: kindRaw) ?? .unknown }
}

/// A curated catalog of popular bootable images, shipped with the app so users
/// can jump straight to a verified download.
public struct DistroCatalog: Codable, Sendable {
    public let entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) { self.entries = entries }

    /// Load the catalog bundled in the app's resources.
    public static func bundled() -> DistroCatalog {
        guard
            let url = Bundle.module.url(forResource: "distros", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(DistroCatalog.self, from: data)
        else {
            return DistroCatalog(entries: [])
        }
        return catalog
    }

    public var categories: [String] {
        Array(Set(entries.map(\.category))).sorted()
    }
}
