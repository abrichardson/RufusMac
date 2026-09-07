import Foundation

/// Pure, side-effect-free parsing of `diskutil` plist output into `USBDrive`
/// values. Kept separate from `DiskService` so the parsing and — crucially —
/// the internal-disk safety filter can be unit-tested with fixtures.
public enum DiskParser {

    public struct WholeDisk: Sendable, Equatable {
        public let id: String
        public let mountPoints: [String]
        public let content: String?
    }

    /// Extract whole-disk identifiers and mount points from
    /// `diskutil list -plist external physical`.
    public static func wholeDisks(fromListPlist data: Data) throws -> [WholeDisk] {
        guard
            let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let disks = root["AllDisksAndPartitions"] as? [[String: Any]]
        else { return [] }

        return disks.compactMap { disk in
            guard let id = disk["DeviceIdentifier"] as? String else { return nil }
            var mounts: [String] = []
            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for part in partitions {
                    if let mount = part["MountPoint"] as? String, !mount.isEmpty {
                        mounts.append(mount)
                    }
                }
            }
            if let mount = disk["MountPoint"] as? String, !mount.isEmpty {
                mounts.append(mount)
            }
            return WholeDisk(id: id, mountPoints: mounts, content: disk["Content"] as? String)
        }
    }

    /// Build a `USBDrive` from `diskutil info -plist <id>`, applying the
    /// external/removable safety filter. Returns `nil` for internal or
    /// otherwise ineligible disks — this is the core data-loss guard.
    public static func drive(
        fromInfoPlist data: Data,
        mountPoints: [String],
        content: String?
    ) throws -> USBDrive? {
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let id: String
        if let identifier = info["DeviceIdentifier"] as? String {
            id = identifier
        } else if let node = info["DeviceNode"] as? String {
            id = node.replacingOccurrences(of: "/dev/", with: "")
        } else {
            return nil
        }

        if let whole = info["WholeDisk"] as? Bool, !whole { return nil }
        if let physical = info["VirtualOrPhysical"] as? String, physical != "Physical" { return nil }
        let isInternal = (info["Internal"] as? Bool) ?? true   // fail safe: assume internal
        let isRemovable = (info["Removable"] as? Bool) ?? (info["RemovableMedia"] as? Bool) ?? false
        let isEjectable = (info["Ejectable"] as? Bool) ?? false
        let bus = (info["BusProtocol"] as? String) ?? ""
        let size = int64(info["TotalSize"]) ?? int64(info["Size"]) ?? 0
        let mediaName = (info["MediaName"] as? String) ?? ""
        let model = (info["IORegistryEntryName"] as? String) ?? mediaName

        let drive = USBDrive(
            id: id,
            mediaName: mediaName,
            model: model,
            sizeBytes: size,
            busProtocol: bus,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isInternal: isInternal,
            mountPoints: mountPoints,
            partitionContent: content
        )

        // Never surface anything that isn't a clearly external, removable target.
        guard drive.isSafeTarget else { return nil }
        return drive
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let n as Int64: return n
        case let n as Int: return Int64(n)
        case let n as NSNumber: return n.int64Value
        default: return nil
        }
    }
}
