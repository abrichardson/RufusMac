import Foundation

/// Enumerates write-eligible USB drives via `diskutil`.
///
/// All listing here is **read-only**. Destructive operations live in the writer
/// engines and always run through `PrivilegedRunner` behind an explicit
/// confirmation. `DiskService` only ever returns external, removable disks.
public struct DiskService: Sendable {
    static let diskutilPath = "/usr/sbin/diskutil"

    public init() {}

    /// List external, physical, removable whole disks suitable as targets.
    public func listRemovableDrives() async throws -> [USBDrive] {
        let listOutput = try await Shell.output(
            Self.diskutilPath, ["list", "-plist", "external", "physical"]
        )
        let wholeDisks = try DiskParser.wholeDisks(fromListPlist: Data(listOutput.utf8))

        var drives: [USBDrive] = []
        for whole in wholeDisks {
            guard isWholeDiskID(whole.id) else { continue }
            let infoOutput = try await Shell.output(
                Self.diskutilPath, ["info", "-plist", whole.id]
            )
            if let drive = try DiskParser.drive(
                fromInfoPlist: Data(infoOutput.utf8),
                mountPoints: whole.mountPoints,
                content: whole.content
            ) {
                drives.append(drive)
            }
        }
        return drives.sorted { $0.id < $1.id }
    }

    /// `disk4` is a whole disk; `disk4s1` is a slice. We only target whole disks.
    private func isWholeDiskID(_ id: String) -> Bool {
        guard id.hasPrefix("disk") else { return false }
        return id.dropFirst(4).allSatisfy(\.isNumber)
    }
}
