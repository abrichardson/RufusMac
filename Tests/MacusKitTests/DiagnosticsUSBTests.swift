import Foundation
import Testing
@testable import MacusKit

struct DiagnosticsUSBTests {
    func drive(id: String = "disk42", size: Int64 = 2_000_000_000, internalDisk: Bool = false, mounts: [String] = []) -> USBDrive {
        USBDrive(id: id, mediaName: "Test USB", model: "Test", sizeBytes: size, busProtocol: "USB", isRemovable: true, isEjectable: true, isInternal: internalDisk, mountPoints: mounts, partitionContent: nil)
    }

    @Test func rejectsUnsafeTargetsAndMalformedImages() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0, count: 1048576).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let image = DiagnosticsUSB(image: path, sha256: String(repeating: "a", count: 64))
        #expect(throws: (any Error).self) { try image.validate(drive(internalDisk: true)) }
        #expect(throws: (any Error).self) { try image.validate(drive(id: "disk42s1")) }
        #expect(throws: (any Error).self) { try image.validate(drive(size: 1048576)) }
        #expect(throws: (any Error).self) { try image.validate(drive(mounts: [path.deletingLastPathComponent().resolvingSymlinksInPath().path])) }
        #expect(throws: (any Error).self) { try DiagnosticsUSB(image: path, sha256: "bad").validate(drive()) }
        try Data("truncated".utf8).write(to: path)
        #expect(throws: (any Error).self) { try image.validate(drive()) }
    }

    @Test(arguments: ["ok", "bad-hash", "too-small", "read-only"])
    func nativeWriterChecksAndVerifies(scenario: String) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source.img")
        let target = root.appendingPathComponent("target.img")
        let contents = Data(repeating: 7, count: 1048576)
        let original = Data(repeating: 9, count: 3 * 1048576)
        try contents.write(to: source)
        try original.write(to: target)
        let handle = try scenario == "read-only" ? FileHandle(forReadingFrom: target) : FileHandle(forUpdating: target)
        defer { try? handle.close() }
        let hash = scenario == "bad-hash" ? String(repeating: "0", count: 64) : try await ChecksumService().checksum(of: source)
        if scenario == "ok" {
            try AuthorizedDevice.write(image: source, to: handle, capacity: UInt64(original.count), expectedHash: hash)
            let written = try Data(contentsOf: target)
            #expect(written.prefix(contents.count) == contents)
            #expect(written.suffix(1048576) == Data(repeating: 0, count: 1048576))
            #expect(written[1048576..<2097152] == original[1048576..<2097152])
        } else {
            #expect(throws: (any Error).self) {
                try AuthorizedDevice.write(image: source, to: handle, capacity: scenario == "too-small" ? 1048576 : UInt64(original.count), expectedHash: hash)
            }
            #expect(try Data(contentsOf: target) == original)
        }
    }

    @Test func rejectsNonDeviceDescriptor() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        #expect(throws: (any Error).self) { try AuthorizedDevice.size(of: handle) }
    }
}
