import Foundation

/// Copies a versioned toolkit without formatting media or overwriting any files.
/// Folder-based API also serves a future Ventoy writer after its data volume mounts.
public enum InventoryToolkit {
    public static let version = "1.1.0"

    public static func export(to parent: URL) throws -> URL {
        let fm = FileManager.default
        guard let source = Bundle.module.url(forResource: "InventoryToolkit", withExtension: nil) else {
            throw failure("The bundled diagnostics toolkit is missing. Rebuild Macus.")
        }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isWritableKey])
        guard values.isDirectory == true, values.isWritable == true else {
            throw failure("Choose a writable folder or the mounted Ventoy data partition.")
        }
        let destination = parent.appendingPathComponent("Macus-Diagnostics-\(version)")
        guard !fm.fileExists(atPath: destination.path) else {
            throw failure("This toolkit version already exists here. Use it, or select another folder. Existing reports have been preserved.")
        }
        let staging = parent.appendingPathComponent(".macus-toolkit-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        try fm.createDirectory(at: staging.appendingPathComponent("Reports"), withIntermediateDirectories: false)
        // A same-volume move publishes the completed folder without replacing existing data.
        try fm.moveItem(at: staging, to: destination)
        return destination
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Macus.Inventory", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

public struct InventoryReport: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let assetID: String
    public let manufacturer: String
    public let model: String
    public let serial: String
    public let cpu: String
    public let collectedAt: String
    public let memoryBytes: String
    public let hardwareDetails: String
    public let gpu: String
    public let ramType: String
    public let installedMemory: String
    public let driveDetails: String
    public let storageHealth: String
    public let batteryHealth: String
    public let cosmetics: String
    public let manualFailures: String
    public let cpuTest: String
    public let memoryTest: String
    public let notes: String

    public init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema_version"] as? Int == 1,
              let system = root["system"] as? [String: Any],
              let reportID = root["report_id"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        func text(_ value: Any?) -> String {
            if let value = value as? String { return value }
            if let value = value as? NSNumber { return value.stringValue }
            return "Unknown"
        }
        self.url = url
        // A copied report can appear in more than one folder. Keep UI identity distinct.
        id = reportID + "|" + url.path
        assetID = root["asset_id"] as? String ?? ""
        manufacturer = text(system["manufacturer"])
        model = text(system["model"])
        serial = text(system["serial"])
        cpu = text(system["cpu"])
        memoryBytes = text(system["usable_memory_bytes"])
        collectedAt = text(root["collected_at"])
        let disks = root["storage"] as? [[String: Any]] ?? []
        let memory = root["memory"] as? [String: Any] ?? [:]
        let modules = memory["modules"] as? [[String: Any]] ?? []
        let gpus = root["gpus"] as? [[String: Any]] ?? []
        func capacity(_ value: Any?, decimal: Bool = false) -> String {
            guard let number = value as? NSNumber else { return "Unknown" }
            return String(format: "%.1f %@", number.doubleValue / (decimal ? 1_000_000_000 : 1_073_741_824), decimal ? "GB" : "GiB")
        }
        installedMemory = capacity(memory["installed_bytes"])
        ramType = (memory["types"] as? [String]).flatMap { $0.isEmpty ? nil : $0.joined(separator: "; ") } ?? "Unknown"
        gpu = gpus.isEmpty ? "Unknown" : gpus.map { text($0["vendor"]) + " " + text($0["model"]) }.joined(separator: "; ")
        driveDetails = disks.isEmpty ? "Unknown" : disks.map {
            text($0["model"]) + " · " + capacity($0["size"], decimal: true) + " · " + text($0["drive_type"]) + " · " + text($0["interface"]) + " · serial " + text($0["serial"]) + " · health " + text($0["health"])
        }.joined(separator: "\n")
        var details = ["Installed RAM: " + installedMemory + " · " + ramType]
        details += modules.map { module in
            if module["populated"] as? Bool == false { return "Slot " + text(module["locator"]) + ": empty (firmware-reported)" }
            return "Slot " + text(module["locator"]) + ": " + capacity(module["size_bytes"]) + " · " + text(module["type"]) + " · " + text(module["form_factor"]) + "\nConfigured speed: " + text(module["configured_speed"]) + " · rated: " + text(module["speed"]) + "\n" + text(module["manufacturer"]) + " · part " + text(module["part_number"]) + " · serial " + text(module["serial"])
        }
        details += gpus.isEmpty ? ["GPU: Unknown"] : gpus.map {
            "GPU: " + text($0["vendor"]) + " " + text($0["model"]) + "\nDriver: " + text($0["driver"]) + " · reported VRAM: " + capacity($0["vram_bytes"])
        }
        details.append("Drives:\n" + driveDetails)
        details.append("BIOS: " + text(system["bios_version"]) + " · " + text(system["bios_date"]))
        hardwareDetails = details.joined(separator: "\n\n")
        storageHealth = disks.isEmpty ? "Unknown" : disks.map { text($0["health"]) }.joined(separator: "; ")
        let batteries = root["batteries"] as? [[String: Any]] ?? []
        batteryHealth = batteries.isEmpty ? "Unknown / not present" : batteries.map { text($0["health_percent"]) }.joined(separator: "; ")
        cosmetics = text(root["cosmetics"])
        let checks = root["manual_checks"] as? [String: String] ?? [:]
        manualFailures = checks.filter { $0.value == "fail" }.keys.sorted().joined(separator: "; ")
        let tests = root["tests"] as? [String: [String: Any]] ?? [:]
        cpuTest = text(tests["cpu"]?["status"])
        memoryTest = text(tests["memory"]?["status"])
        notes = root["notes"] as? String ?? ""
    }

    /// Reads only immediate report directories, avoiding arbitrary recursive scans/symlinks.
    public static func load(from folder: URL) throws -> (reports: [InventoryReport], skipped: Int) {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles])
        var reports: [InventoryReport] = []
        var skipped = 0
        for child in children {
            let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true else { continue }
            let candidate = values.isDirectory == true ? child.appendingPathComponent("report.json") : child
            guard candidate.lastPathComponent == "report.json", fm.fileExists(atPath: candidate.path) else { continue }
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            do { reports.append(try InventoryReport(url: candidate)) } catch { skipped += 1 }
        }
        return (reports.sorted { $0.collectedAt > $1.collectedAt }, skipped)
    }

    public static func csv(_ reports: [InventoryReport]) -> String {
        func cell(_ value: String) -> String {
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = ["asset_id", "manufacturer", "model", "serial", "cpu", "usable_memory_bytes", "installed_memory", "ram_type", "gpu", "drive_details", "hardware_details", "storage_health", "battery_health_percent", "cosmetics", "failed_manual_checks", "cpu_test", "memory_test", "collected_at", "notes"]
        let rows = reports.map { [$0.assetID, $0.manufacturer, $0.model, $0.serial, $0.cpu, $0.memoryBytes, $0.installedMemory, $0.ramType, $0.gpu, $0.driveDetails, $0.hardwareDetails, $0.storageHealth, $0.batteryHealth, $0.cosmetics, $0.manualFailures, $0.cpuTest, $0.memoryTest, $0.collectedAt, $0.notes] }
        return ([header] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
