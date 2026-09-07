import Foundation

public enum PartitionScheme: String, CaseIterable, Sendable, Identifiable, Codable {
    case gpt = "GPT"
    case mbr = "MBR"
    public var id: String { rawValue }
    /// `diskutil` partition-scheme token.
    public var diskutilToken: String { self == .gpt ? "GPT" : "MBR" }
}

public enum TargetSystem: String, CaseIterable, Sendable, Identifiable, Codable {
    case uefi = "UEFI (non-CSM)"
    case both = "BIOS or UEFI"
    public var id: String { rawValue }
}

public enum BootFileSystem: String, CaseIterable, Sendable, Identifiable, Codable {
    case fat32 = "FAT32"
    case exfat = "exFAT"
    case ntfs = "NTFS"
    public var id: String { rawValue }
    /// `diskutil` filesystem token used by `eraseDisk` / `partitionDisk`.
    public var diskutilToken: String {
        switch self {
        case .fat32: return "MS-DOS FAT32"
        case .exfat: return "ExFAT"
        case .ntfs: return "ExFAT" // macOS can't natively format NTFS; UEFI:NTFS path handles real NTFS.
        }
    }
}

/// Everything the user can configure for a burn — the RufusMac equivalent of
/// Rufus's main options panel.
public struct WriteConfig: Sendable {
    public var windowsSetup = WindowsSetupOptions()
    public var volumeLabel: String
    public var partitionScheme: PartitionScheme
    public var targetSystem: TargetSystem
    public var fileSystem: BootFileSystem
    public var quickFormat: Bool
    public var verifyAfterWrite: Bool
    /// Windows 11: bypass TPM / Secure Boot / RAM checks + skip the online account.
    public var windows11Bypass: Bool
    /// Linux persistence partition size in MB (0 = none).
    public var persistenceMB: Int

    public init(
        volumeLabel: String = "REFUSEMAC",
        partitionScheme: PartitionScheme = .gpt,
        targetSystem: TargetSystem = .uefi,
        fileSystem: BootFileSystem = .fat32,
        quickFormat: Bool = true,
        verifyAfterWrite: Bool = true,
        windows11Bypass: Bool = false,
        persistenceMB: Int = 0
    ) {
        self.volumeLabel = volumeLabel
        self.partitionScheme = partitionScheme
        self.targetSystem = targetSystem
        self.fileSystem = fileSystem
        self.quickFormat = quickFormat
        self.verifyAfterWrite = verifyAfterWrite
        self.windows11Bypass = windows11Bypass
        self.persistenceMB = persistenceMB
    }

    /// FAT32 volume labels must be uppercase and ≤ 11 chars.
    public var sanitizedLabel: String {
        let upper = volumeLabel.uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return String(upper.prefix(11))
    }

    /// Rufus-style smart defaults inferred from the inspected image.
    public static func recommended(for image: BootImage) -> WriteConfig {
        switch image.kind {
        case .windows:
            return WriteConfig(
                volumeLabel: "WIN_USB",
                partitionScheme: .gpt,
                targetSystem: .uefi,
                fileSystem: .fat32,
                quickFormat: true,
                verifyAfterWrite: true,
                windows11Bypass: false,
                persistenceMB: 0
            )
        case .linux, .raw, .unknown:
            let base = image.url.deletingPathExtension().lastPathComponent
            let label = String(base.uppercased().prefix(11))
            return WriteConfig(
                volumeLabel: label.isEmpty ? "LINUX_USB" : label,
                partitionScheme: .mbr,
                targetSystem: .both,
                fileSystem: .fat32,
                quickFormat: true,
                verifyAfterWrite: true,
                windows11Bypass: false,
                persistenceMB: 0
            )
        }
    }
}
