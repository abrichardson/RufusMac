import Foundation

/// A removable USB disk eligible as a write target.
///
/// Only external, physical, non-internal whole disks are ever represented here.
/// RufusMac never lists the Mac's internal/boot disk — see `isSafeTarget` and
/// `DiskParser`, which enforce this as defense-in-depth.
public struct USBDrive: Identifiable, Hashable, Sendable {
    /// BSD whole-disk identifier, e.g. `disk4`.
    public let id: String
    /// Marketing media name, e.g. `SanDisk 3.2 Gen1`.
    public let mediaName: String
    /// IORegistry entry name (more verbose model string).
    public let model: String
    public let sizeBytes: Int64
    /// Bus protocol, e.g. `USB`.
    public let busProtocol: String
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isInternal: Bool
    public let mountPoints: [String]
    /// Partition content hint, e.g. `Windows_NTFS`, `FDisk_partition_scheme`.
    public let partitionContent: String?

    public init(
        id: String,
        mediaName: String,
        model: String,
        sizeBytes: Int64,
        busProtocol: String,
        isRemovable: Bool,
        isEjectable: Bool,
        isInternal: Bool,
        mountPoints: [String],
        partitionContent: String?
    ) {
        self.id = id
        self.mediaName = mediaName
        self.model = model
        self.sizeBytes = sizeBytes
        self.busProtocol = busProtocol
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isInternal = isInternal
        self.mountPoints = mountPoints
        self.partitionContent = partitionContent
    }

    /// Buffered device node (`/dev/disk4`).
    public var deviceNode: String { "/dev/\(id)" }
    /// Raw device node (`/dev/rdisk4`) — much faster for `dd`.
    public var rawDeviceNode: String { "/dev/r\(id)" }

    public var displaySize: String { ByteCount.string(sizeBytes) }

    /// Friendly primary label for the picker.
    public var title: String { mediaName.isEmpty ? model : mediaName }

    /// Secondary detail line: size · bus · id · volume.
    public var subtitle: String {
        var parts = [displaySize, busProtocol, id]
        if let mount = mountPoints.first, !mount.isEmpty {
            parts.append(URL(fileURLWithPath: mount).lastPathComponent)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Hard safety gate. A drive is only a valid target if it is clearly
    /// external and removable. Internal disks can never be targets.
    public var isSafeTarget: Bool {
        id.range(of: "^disk[0-9]+$", options: .regularExpression) != nil && sizeBytes > 0 && !isInternal && busProtocol.uppercased() == "USB"
    }
}
