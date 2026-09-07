import Foundation

/// Inspects a selected image to determine its size, kind (Windows / Linux /
/// raw), and whether its `install.wim` is too large for FAT32 — mirroring how
/// Rufus auto-detects sensible defaults from the chosen ISO.
public struct ImageInspector: Sendable {
    public init() {}

    public func inspect(_ url: URL) async -> BootImage {
        let size = fileSize(url)
        let ext = url.pathExtension.lowercased()

        // .img/.dmg are written raw; only .iso is worth mounting to classify.
        if ext == "img" || ext == "dmg" {
            return BootImage(url: url, sizeBytes: size, kind: .raw, hasOversizedWIM: false)
        }

        if let existing = try? await existingMount(url) {
            let (kind, oversized) = classify(mountPoint: existing)
            return BootImage(url: url, sizeBytes: size, kind: kind, hasOversizedWIM: oversized, windowsArchitecture: architecture(at: existing))
        }
        if let mount = try? await mountReadOnly(url) {
            let (kind, oversized) = classify(mountPoint: mount)
            let arch = architecture(at: mount)
            try? await detach(mount)
            return BootImage(url: url, sizeBytes: size, kind: kind, hasOversizedWIM: oversized, windowsArchitecture: arch)
        }

        // Never guess Linux after a mount failure: this may be a Windows ISO.
        return BootImage(url: url, sizeBytes: size, kind: .unknown, hasOversizedWIM: false)
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func classify(mountPoint: String) -> (ImageKind, Bool) {
        let fm = FileManager.default
        let win = ["sources/install.wim", "sources/install.esd", "sources/boot.wim", "bootmgr"]
        let isWindows = win.contains { fm.fileExists(atPath: "\(mountPoint)/\($0)") }

        if isWindows {
            var oversized = false
            let wimPath = "\(mountPoint)/sources/install.wim"
            if let attrs = try? fm.attributesOfItem(atPath: wimPath),
               let bytes = (attrs[.size] as? NSNumber)?.int64Value {
                oversized = bytes > 4_294_967_295 // FAT32 4 GB file limit
            }
            return (.windows, oversized)
        }

        let linuxMarkers = ["casper", "isolinux", "boot/grub", "live", "EFI/BOOT", "arch", "LiveOS"]
        let isLinux = linuxMarkers.contains { fm.fileExists(atPath: "\(mountPoint)/\($0)") }
        return (isLinux ? .linux : .unknown, false)
    }

    private func architecture(at mount: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: "\(mount)/efi/boot/bootx64.efi") { return "amd64" }
        if fm.fileExists(atPath: "\(mount)/efi/boot/bootaa64.efi") { return "arm64" }
        return nil
    }

    private func existingMount(_ url: URL) async throws -> String? {
        let output = try await Shell.output(ToolPaths().hdiutil, ["info", "-plist"])
        let plist = try PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any]
        for image in plist?["images"] as? [[String: Any]] ?? [] {
            guard let path = image["image-path"] as? String,
                  URL(fileURLWithPath: path).standardizedFileURL == url.standardizedFileURL else { continue }
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                if let mount = entity["mount-point"] as? String { return mount }
            }
        }
        return nil
    }

    private func mountReadOnly(_ url: URL) async throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rm-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
        _ = try await Shell.output(ToolPaths().hdiutil, [
            "attach", "-readonly", "-nobrowse", "-noverify",
            "-mountpoint", dir.path, url.path
        ])
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        return dir.path
    }

    private func detach(_ mountPoint: String) async throws {
        _ = try await Shell.run(ToolPaths().hdiutil, ["detach", mountPoint, "-force"])
        try? FileManager.default.removeItem(atPath: mountPoint)
    }
}
