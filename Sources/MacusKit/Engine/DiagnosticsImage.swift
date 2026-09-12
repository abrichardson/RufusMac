import Foundation

/// A user-selected diagnostics image verified against its download checksum.
public struct DiagnosticsImage: Sendable {
    public static let fileName = "Macus-Diagnostics-amd64.iso"
    public static let markerName = ".macus-diagnostics.json"
    public static let reportsName = "MacusReports"
    public let image: URL
    public let sha256: String

    public init(image: URL, sha256: String) {
        self.image = image
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }



    public static func isPrepared(_ root: URL) -> Bool {
        let marker = root.appendingPathComponent(markerName)
        let reports = root.appendingPathComponent(reportsName)
        guard (try? marker.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? reports.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let size = try? marker.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024,
              let data = try? Data(contentsOf: marker),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["schema_version"] as? Int == 1 && object["purpose"] as? String == "macus-diagnostics"
    }

    /// Only mounted roots belonging to freshly enumerated external USB disks.
    public static func usbRoots() async throws -> [URL] {
        let drives = try await DiskService().listRemovableDrives()
        return drives.filter(\.isSafeTarget).flatMap(\.mountPoints)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { $0.lastPathComponent != "VTOYEFI" }
    }

    public static func ventoyRoots() async throws -> [URL] {
        let drives = try await DiskService().listRemovableDrives()
        var roots: [URL] = []
        for drive in drives where drive.isSafeTarget {
            let output = try await Shell.output("/usr/sbin/diskutil", ["list", "-plist", drive.id])
            if hasVentoyPartition(Data(output.utf8)) {
                roots += drive.mountPoints.map { URL(fileURLWithPath: $0).standardizedFileURL }
                    .filter { $0.lastPathComponent != "VTOYEFI" }
            }
        }
        return roots
    }

    static func hasVentoyPartition(_ plist: Data) -> Bool {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else { return false }
        return disks.contains { disk in
            (disk["Partitions"] as? [[String: Any]] ?? []).contains {
                $0["VolumeName"] as? String == "VTOYEFI"
            }
        }
    }

    public func install(on root: URL) async throws -> URL {
        let current = try await Self.ventoyRoots()
        guard current.contains(root.standardizedFileURL) else {
            throw Self.failure("No mounted Ventoy data partition was found for this selection. Prepare it with Ventoy, reconnect it and refresh.")
        }
        return try await copyFiles(to: root)
    }

    /// Separated from USB enumeration for file-level regression tests.
    func copyFiles(to root: URL) async throws -> URL {
        guard sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw Self.failure("The diagnostics image checksum is invalid.")
        }
        let fm = FileManager.default
        let iso = root.appendingPathComponent(Self.fileName)
        let marker = root.appendingPathComponent(Self.markerName)
        let reports = root.appendingPathComponent(Self.reportsName)
        for path in [iso, marker, reports] {
            if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Self.failure("A diagnostics path is a symbolic link. Choose a different USB.")
            }
        }
        if fm.fileExists(atPath: marker.path) && !Self.isPrepared(root) {
            throw Self.failure("This USB has an unrecognized diagnostics marker. Existing files were preserved.")
        }
        if fm.fileExists(atPath: reports.path) && (try? reports.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            throw Self.failure("MacusReports already exists as a file. Existing files were preserved.")
        }
        let checksum = ChecksumService()
        if fm.fileExists(atPath: iso.path) {
            guard try await checksum.verify(iso, expected: sha256) else {
                throw Self.failure("A different diagnostics image already exists on this USB. Move it elsewhere before adding this version.")
            }
        } else {
            let staging = root.appendingPathComponent(".macus-image-\(UUID().uuidString).partial")
            defer { try? fm.removeItem(at: staging) }
            try await Task.detached { try FileManager.default.copyItem(at: image, to: staging) }.value
            guard try await checksum.verify(staging, expected: sha256) else {
                throw Self.failure("Image verification failed. The incomplete copy was removed; try again.")
            }
            try fm.moveItem(at: staging, to: iso)
        }
        try fm.createDirectory(at: reports, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: marker.path) {
            let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "purpose": "macus-diagnostics"])
            try data.write(to: marker, options: .withoutOverwriting)
        }
        return iso
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "Macus.DiagnosticsImage", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
