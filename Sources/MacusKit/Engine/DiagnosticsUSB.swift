import Foundation

/// Dedicated bootable USB with a separate, writable 512 MiB report partition.
public struct DiagnosticsUSB: Sendable {
    public static let fileName = "Macus-Diagnostics-USB.img"
    public let image: URL
    public let sha256: String

    public init(image: URL, sha256: String) {
        self.image = image
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }



    public func create(on drive: USBDrive) async throws {
        try validate(drive)
        try await revalidate(drive)
        guard try await ChecksumService().verify(image, expected: sha256) else {
            throw failure("Diagnostics image checksum failed. No data was written.")
        }
        try await revalidate(drive)
        _ = try await Shell.output("/usr/sbin/diskutil", ["unmountDisk", drive.deviceNode])
        let handle = try await Task.detached { try AuthorizedDevice.open(drive.rawDeviceNode) }.value
        defer { try? handle.close() }
        let actualSize = try AuthorizedDevice.size(of: handle)
        guard actualSize == UInt64(drive.sizeBytes) else {
            throw failure("The opened USB changed size. No data was written.")
        }
        try await revalidate(drive)
        try await Task.detached {
            try AuthorizedDevice.write(image: image, to: handle, capacity: actualSize, expectedHash: sha256)
        }.value
        try handle.close()
        _ = try await Shell.output("/usr/sbin/diskutil", ["eject", drive.deviceNode])
    }

    private func revalidate(_ drive: USBDrive) async throws {
        let current = try await DiskService().listRemovableDrives()
        guard current.contains(where: { $0.id == drive.id && $0.isSafeTarget && $0.sizeBytes == drive.sizeBytes && $0.mediaName == drive.mediaName }) else {
            throw failure("The selected USB changed. Refresh and select it again.")
        }
    }

    func validate(_ drive: USBDrive) throws {
        guard drive.isSafeTarget else { throw failure("Select an external USB whole disk.") }
        guard sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw failure("Invalid diagnostics image checksum.") }
        let path = image.resolvingSymlinksInPath().path
        guard !drive.mountPoints.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            throw failure("Move Macus off the USB you want to erase, then try again.")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size % 1048576 == 0, Int64(size) + 1048576 <= drive.sizeBytes else {
            throw failure("The USB is too small or the diagnostics image is incomplete. Use a USB of at least 2 GB.")
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Macus.DiagnosticsUSB", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
