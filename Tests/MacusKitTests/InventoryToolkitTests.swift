import Foundation
import Testing
@testable import MacusKit

struct InventoryToolkitTests {
    @Test func exportPreservesExistingToolkitAndReports() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let iso = folder.appendingPathComponent("existing.iso")
        try Data("existing media".utf8).write(to: iso)
        let exported = try InventoryToolkit.export(to: folder)
        for name in ["inventory.py", "Start.sh", "README.txt", "Reports"] {
            #expect(FileManager.default.fileExists(atPath: exported.appendingPathComponent(name).path))
        }
        let report = exported.appendingPathComponent("Reports/keep.txt")
        try Data("keep".utf8).write(to: report)
        #expect(throws: (any Error).self) { try InventoryToolkit.export(to: folder) }
        #expect(try String(contentsOf: report, encoding: .utf8) == "keep")
        #expect(try String(contentsOf: iso, encoding: .utf8) == "existing media")
    }

    @Test func importHandlesUnknownsCorruptionAndFormulaCells() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for sub in ["valid", "bad", "future"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let object: [String: Any] = ["schema_version": 1, "report_id": "report1", "asset_id": "=formula", "system": ["model": "Test", "cpu": NSNull()], "notes": "\t@formula\n\"quoted\""]
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("valid/report.json"))
        try Data("broken".utf8).write(to: folder.appendingPathComponent("bad/report.json"))
        try Data("{\"schema_version\": 2}".utf8).write(to: folder.appendingPathComponent("future/report.json"))
        let result = try InventoryReport.load(from: folder)
        #expect(result.skipped == 2)
        let report = try #require(result.reports.first)
        #expect(report.cpu == "Unknown")
        #expect(report.storageHealth == "Unknown")
        let csv = InventoryReport.csv(result.reports)
        #expect(csv.contains("\"'=formula\""))
        #expect(csv.contains("\"'\t@formula\n\"\"quoted\"\"\""))
    }
    @Test func importsExpandedHardwareAndExportsIt() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: path) }
        let object: [String: Any] = ["schema_version": 1, "report_id": "hardware", "system": ["model": "Test PC"],
            "memory": ["installed_bytes": 17179869184, "types": ["DDR4"], "modules": [["locator": "DIMM 0", "size_bytes": 17179869184, "type": "DDR4", "configured_speed": "2667 MT/s", "part_number": "RAM123"]]],
            "gpus": [["vendor": "Intel", "model": "UHD Graphics", "driver": "i915"]],
            "storage": [["model": "Example SSD", "size": 512000000000, "drive_type": "SSD", "interface": "NVMe", "serial": "SSD123", "health": "unknown"]]]
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let report = try InventoryReport(url: path)
        #expect(report.ramType == "DDR4")
        #expect(report.gpu.contains("UHD Graphics"))
        #expect(report.hardwareDetails.contains("2667 MT/s"))
        #expect(report.driveDetails.contains("512.0 GB · SSD · NVMe"))
        let csv = InventoryReport.csv([report])
        #expect(csv.contains("RAM123"))
        #expect(csv.contains("SSD123"))
    }

}
