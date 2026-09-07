import Foundation

/// What kind of bootable image we're dealing with — drives smart defaults and
/// which writer engine is used.
public enum ImageKind: String, Sendable, Codable {
    case windows = "Windows"
    case linux = "Linux"
    case raw = "Disk image"
    case unknown = "Image"

    public var systemImage: String {
        switch self {
        case .windows: return "windowsill"
        case .linux: return "terminal"
        case .raw: return "opticaldisc.fill"
        case .unknown: return "opticaldisc"
        }
    }

    /// Linux/hybrid and raw images are written byte-for-byte with `dd`.
    /// Windows images need the file-copy + WIM-split pipeline.
    public var usesRawWrite: Bool {
        self == .linux || self == .raw || self == .unknown
    }
}

/// A selected bootable image plus everything RufusMac learned by inspecting it.
public struct BootImage: Identifiable, Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let kind: ImageKind
    /// True when `sources/install.wim` exceeds the FAT32 4 GB file limit and
    /// therefore must be split into `.swm` files for a UEFI FAT32 target.
    public let hasOversizedWIM: Bool
    public let windowsArchitecture: String?

    public init(url: URL, sizeBytes: Int64, kind: ImageKind, hasOversizedWIM: Bool, windowsArchitecture: String? = nil) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.hasOversizedWIM = hasOversizedWIM
        self.windowsArchitecture = windowsArchitecture
    }

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var displaySize: String { ByteCount.string(sizeBytes) }
}
