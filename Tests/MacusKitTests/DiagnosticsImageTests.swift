import Foundation
import Testing
@testable import MacusKit

struct DiagnosticsImageTests {
    func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let usb = root.appendingPathComponent("USB")
        try FileManager.default.createDirectory(at: usb, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.iso")
        try Data("test ISO content".utf8).write(to: source)
        return (root, usb, source)
    }

    @Test func onlyRecognizesVentoyPartitionLayout() throws {
        func plist(_ name: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["AllDisksAndPartitions": [["Partitions": [["VolumeName": name]]]]], format: .xml, options: 0)
        }
        #expect(DiagnosticsImage.hasVentoyPartition(try plist("VTOYEFI")))
        #expect(!DiagnosticsImage.hasVentoyPartition(try plist("Backup")))
        #expect(!DiagnosticsImage.hasVentoyPartition(Data()))
    }

    @Test func copiesVerifiesAndPreservesReportsOnRepeat() async throws {
        let (root, usb, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let digest = try await ChecksumService().checksum(of: source)
        let image = DiagnosticsImage(image: source, sha256: digest)
        _ = try await image.copyFiles(to: usb)
        #expect(DiagnosticsImage.isPrepared(usb))
        let report = usb.appendingPathComponent("MacusReports/existing.json")
        try Data("keep".utf8).write(to: report)
        _ = try await image.copyFiles(to: usb)
        #expect(try String(contentsOf: report, encoding: .utf8) == "keep")
        #expect(try await ChecksumService().verify(usb.appendingPathComponent(DiagnosticsImage.fileName), expected: digest))
    }

    @Test func badChecksumNeverPublishesImageOrMarker() async throws {
        let (root, usb, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = DiagnosticsImage(image: source, sha256: String(repeating: "0", count: 64))
        await #expect(throws: (any Error).self) { try await image.copyFiles(to: usb) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: usb.path).isEmpty)
    }

    @Test func refusesSymlinkAndExistingDifferentImage() async throws {
        let (root, usb, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = DiagnosticsImage(image: source, sha256: try await ChecksumService().checksum(of: source))
        let destination = usb.appendingPathComponent(DiagnosticsImage.fileName)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
        await #expect(throws: (any Error).self) { try await image.copyFiles(to: usb) }
        try FileManager.default.removeItem(at: destination)
        try Data("existing".utf8).write(to: destination)
        await #expect(throws: (any Error).self) { try await image.copyFiles(to: usb) }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "existing")
    }
}
