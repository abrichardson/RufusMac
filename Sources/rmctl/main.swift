import Foundation
import RufusMacKit

// rmctl — RufusMac's command-line companion (diagnostics & automation).
//
// Read-only / dry-run by default. It never writes to a disk; the destructive
// engines live in the app behind an explicit confirmation + admin prompt.
// Handy for scripting, CI checks, and verifying drive detection.
//
// Developed by Harith Dilshan / h4rithd.com — built with the help of Claude Code.

func listDrives() async throws {
    let drives = try await DiskService().listRemovableDrives()
    guard !drives.isEmpty else {
        print("No external, removable USB drives detected.")
        print("(Internal disks are intentionally never listed.)")
        return
    }
    print("Detected \(drives.count) removable drive(s):\n")
    for drive in drives {
        print("  • \(drive.id)")
        print("      name:   \(drive.title)")
        print("      size:   \(drive.displaySize)")
        print("      bus:    \(drive.busProtocol)")
        print("      raw:    \(drive.rawDeviceNode)")
        print("      mounts: \(drive.mountPoints.isEmpty ? "—" : drive.mountPoints.joined(separator: ", "))")
        print("      safe:   \(drive.isSafeTarget ? "yes (external/removable)" : "NO")")
        print("")
    }
}

/// Preview (dry-run) the exact command pipeline for a mode against the first
/// detected drive. Nothing is executed — this only prints the plan.
func previewPlan(modeArg: String, isoPath: String?) async throws {
    guard let drive = try await DiskService().listRemovableDrives().first else {
        print("No external drive detected to preview against. Plug one in first.")
        return
    }
    let mode: BurnMode = {
        switch modeArg.lowercased() {
        case "dd": return .dd
        case "windows", "single": return .single
        case "multiboot": return .multiboot
        default: return .reclaim
        }
    }()

    var image: BootImage?
    if let isoPath {
        image = await ImageInspector().inspect(URL(fileURLWithPath: isoPath))
    }
    let config = image.map { WriteConfig.recommended(for: $0) } ?? WriteConfig()
    let plan = BurnPlanner().makePlan(mode: mode, image: image, drive: drive, config: config)

    print("PLAN: \(plan.mode.rawValue)\(plan.experimental ? "  [EXPERIMENTAL]" : "")")
    print("Target: \(drive.title) (\(drive.id), \(drive.displaySize))\n")
    print("Summary: \(plan.summary)\n")
    if !plan.warnings.isEmpty {
        print("Warnings:")
        plan.warnings.forEach { print("  ⚠ \($0)") }
        print("")
    }
    print("Script (dry-run, NOT executed):")
    print("------------------------------------------------------------")
    print(plan.script)
    print("------------------------------------------------------------")
}

/// List the bundled ISO catalog.
func showCatalog() {
    let catalog = DistroCatalog.bundled()
    guard !catalog.entries.isEmpty else {
        print("Catalog unavailable (resource not found).")
        return
    }
    for category in catalog.categories {
        print("\(category):")
        for entry in catalog.entries where entry.category == category {
            print("  • \(entry.name) — \(entry.summary)")
            print("    \(entry.pageURL)")
        }
        print("")
    }
}

/// Verify a file's SHA-256 against an expected value.
func verifyFile(path: String, expected: String) async throws {
    let matches = try await ChecksumService().verify(URL(fileURLWithPath: path), expected: expected)
    print(matches ? "✅ Checksum matches." : "❌ Checksum does NOT match.")
    if !matches { exit(1) }
}

func printHelp() {
    print("""
    rmctl — \(RufusMacInfo.name) CLI companion (v\(RufusMacInfo.version))
    \(RufusMacInfo.tagline)

    Usage:
      rmctl list                       List external/removable USB drives (read-only)
      rmctl preview <mode> [iso]       Dry-run the command pipeline (NOTHING is executed)
                                       modes: dd | windows | multiboot | reclaim
      rmctl version                    Print version
      rmctl help                       Show this help

    Internal disks are never listed. Destructive writes happen only inside the app.
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

do {
    switch command {
    case "list":
        try await listDrives()
    case "preview":
        try await previewPlan(modeArg: arguments.dropFirst().first ?? "reclaim",
                              isoPath: arguments.dropFirst(2).first)
    case "inspect":
        guard arguments.count == 2 else { print("Usage: rmctl inspect <iso>"); exit(1) }
        let image = await ImageInspector().inspect(URL(fileURLWithPath: arguments[1]))
        print("Kind: \(image.kind.rawValue)\nSize: \(image.sizeBytes)\nRequires WIM split: \(image.hasOversizedWIM)")
        if image.kind == .unknown { exit(1) }
    case "catalog":
        showCatalog()
    case "verify":
        if arguments.count >= 3 {
            try await verifyFile(path: arguments[1], expected: arguments[2])
        } else {
            print("Usage: rmctl verify <file> <sha256>")
        }
    case "version", "--version", "-v":
        print("rmctl \(RufusMacInfo.version)")
    default:
        printHelp()
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
