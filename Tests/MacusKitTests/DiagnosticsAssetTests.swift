import Foundation
import Testing
@testable import MacusKit

struct DiagnosticsAssetTests {
    @Test func externalChecksumValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Macus-Diagnostics-USB.img")
        let sidecar = image.appendingPathExtension("sha256")
        let hash = String(repeating: "a", count: 64)
        try (hash + "  " + image.lastPathComponent + "\n").write(to: sidecar, atomically: true, encoding: .utf8)
        #expect(try DiagnosticsAsset.checksum(for: image) == hash)
        for invalid in ["   \n", "", "bad", hash + "  wrong.img", String(repeating: "a", count: 5000)] {
            try invalid.write(to: sidecar, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try DiagnosticsAsset.checksum(for: image) }
        }
    }
}
