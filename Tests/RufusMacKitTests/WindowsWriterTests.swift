import Foundation
import Testing
@testable import RufusMacKit

struct WindowsWriterTests {
    // Every external disk command is replaced by a fixture executable. Real
    // rsync copies only between temporary directories; no admin access occurs.
    final class Fixture {
        let root: URL
        let iso: URL
        let source: URL
        let destination: URL
        var tools = ToolPaths(wimlib: "/missing/wimlib")
        var drive: USBDrive {
            USBDrive(id: "disk99", mediaName: "Test USB", model: "Test", sizeBytes: 32_000_000_000,
                     busProtocol: "USB", isRemovable: true, isEjectable: true, isInternal: false,
                     mountPoints: [], partitionContent: nil)
        }
        init(payload: String = "install.wim", oversized: Bool = false, internalDisk: Bool = false, corrupt: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("writer test '\(UUID())")
            source = root.appendingPathComponent("source")
            destination = root.appendingPathComponent("destination")
            iso = root.appendingPathComponent("Windows ' $(false).iso")
            try FileManager.default.createDirectory(at: source.appendingPathComponent("sources"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source.appendingPathComponent("efi/boot"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data("iso".utf8).write(to: iso)
            try Data("boot".utf8).write(to: source.appendingPathComponent("efi/boot/bootx64.efi"))
            try Data("setup".utf8).write(to: source.appendingPathComponent("sources/boot.wim"))
            let payloadURL = source.appendingPathComponent("sources/\(payload)")
            try Data("payload".utf8).write(to: payloadURL)
            if oversized {
                let file = try FileHandle(forWritingTo: payloadURL)
                try file.truncate(atOffset: 4_294_967_296)
                try file.close()
            }
            func plist(_ name: String, _ value: [String: Any]) throws -> String {
                let path = root.appendingPathComponent(name)
                try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: path)
                return Shell.quote(path.path)
            }
            let images = try plist("images.plist", ["images": [["image-path": iso.path, "system-entities": [["mount-point": source.path]]]]])
            let sourceInfo = try plist("source.plist", ["WritableVolume": false])
            let targetInfo = try plist("target.plist", ["Internal": internalDisk, "WholeDisk": true,
                "VirtualOrPhysical": "Physical", "BusProtocol": "USB", "TotalSize": 32_000_000_000,
                "MediaName": "Test USB", "DeviceNode": "/dev/disk99", "Writable": true])
            let volume = try plist("volume.plist", ["MountPoint": destination.path])
            tools.hdiutil = try executable("hdiutil", "[ \"$1\" = info ] || exit 90\ncat \(images)")
            tools.diskutil = try executable("diskutil", """
            printf '%s\\n' "$*" >> \(Shell.quote(root.appendingPathComponent("calls").path))
            case "$1" in
              info)
                case "$3" in
                  \(Shell.quote(source.path))) cat \(sourceInfo);;
                  /dev/disk99) cat \(targetInfo);;
                  /dev/disk99s1|/dev/disk99s2) cat \(volume);;
                  *) exit 91;;
                esac;;
              eraseDisk|eject) exit 0;;
              *) exit 92;;
            esac
            """)
            if corrupt {
                tools.rsync = try executable("rsync", """
                /usr/bin/rsync "$@"
                case "$1" in -r) printf 'corrupted' > \(Shell.quote(destination.appendingPathComponent("sources/boot.wim").path));; esac
                """)
            }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func executable(_ name: String, _ script: String) throws -> String {
            let path = root.appendingPathComponent(name)
            try ("#!/bin/bash\nset -eu\n" + script + "\n").write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            return path.path
        }
        func run(scheme: PartitionScheme = .gpt) async throws -> ShellResult {
            let image = BootImage(url: iso, sizeBytes: 1024, kind: .windows, hasOversizedWIM: false)
            let plan = BurnPlanner(tools: tools).makePlan(mode: .single, image: image, drive: drive,
                config: WriteConfig(partitionScheme: scheme))
            return try await Shell.run("/bin/bash", ["-c", plan.script])
        }
        var calls: String { (try? String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8)) ?? "" }
    }

    @Test(arguments: ["install.wim", "install.esd", "install.swm"])
    func copiesSupportedPayloads(payload: String) async throws {
        let f = try Fixture(payload: payload)
        let result = try await f.run()
        #expect(result.ok, "\(result.stderr)")
        #expect(try Data(contentsOf: f.destination.appendingPathComponent("sources/\(payload)")) == Data("payload".utf8))
        #expect(f.calls.contains("GPT /dev/disk99"))
        #expect(f.calls.contains("info -plist /dev/disk99s2"))
    }
    @Test func mbrUsesFirstPartition() async throws {
        let f = try Fixture()
        let result = try await f.run(scheme: .mbr)
        #expect(result.ok, "\(result.stderr)")
        #expect(f.calls.contains("MBR /dev/disk99"))
        #expect(f.calls.contains("info -plist /dev/disk99s1"))
    }
    @Test func missingWimlibFailsBeforeErase() async throws {
        let f = try Fixture(oversized: true)
        let result = try await f.run()
        #expect(!result.ok)
        #expect(result.stderr.contains("wimlib is missing"))
        #expect(!f.calls.contains("eraseDisk"))
    }
    @Test func largeESDFailsBeforeErase() async throws {
        let f = try Fixture(payload: "install.esd", oversized: true)
        let result = try await f.run()
        #expect(!result.ok)
        #expect(result.stderr.contains("large ESD is not supported"))
        #expect(!f.calls.contains("eraseDisk"))
    }
    @Test func changedInternalDiskFailsBeforeErase() async throws {
        let f = try Fixture(internalDisk: true)
        let result = try await f.run()
        #expect(!result.ok)
        #expect(result.stderr.contains("internal disk"))
        #expect(!f.calls.contains("eraseDisk"))
    }
    @Test func corruptCopyFailsVerification() async throws {
        let f = try Fixture(corrupt: true)
        let result = try await f.run()
        #expect(!result.ok)
        #expect(result.stderr.contains("Verification failed"))
        #expect(!f.calls.contains("eject"))
    }
    @Test func oversizedWimUsesSplitAndVerify() async throws {
        let f = try Fixture(oversized: true)
        let calls = f.root.appendingPathComponent("wim-calls")
        f.tools.wimlib = try f.executable("wimlib", """
        printf '%s\\n' "$1" >> \(Shell.quote(calls.path))
        case "$1" in
          --version|verify) exit 0;;
          split) printf 'split payload' > "$3";;
          *) exit 93;;
        esac
        """)
        let result = try await f.run()
        #expect(result.ok, "\(result.stderr)")
        #expect(try String(contentsOf: calls, encoding: .utf8) == "--version\nsplit\nverify\n")
        #expect(!FileManager.default.fileExists(atPath: f.destination.appendingPathComponent("sources/install.wim").path))
        #expect(FileManager.default.fileExists(atPath: f.destination.appendingPathComponent("sources/install.swm").path))
    }

    @Test func windowsRunnerKeepsUserIdentity() async throws {
        let runner = PrivilegedRunner()
        let output = try await runner.run(script: "/usr/bin/id -u", prompt: "Unused",
                                          requiresAdministrator: false)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == String(getuid()))
    }

    @Test func shellDrainsLargeStderr() async throws {
        let result = try await Shell.run("/bin/bash", ["-c", "for ((i=0;i<10000;i++)); do printf 'some error output\\n' >&2; done; printf done"])
        #expect(result.ok)
        #expect(result.stdout == "done")
        #expect(result.stderr.count > 100_000)
    }
    @Test func failedInspectionIsUnknown() async {
        let image = await ImageInspector().inspect(URL(fileURLWithPath: "/nonexistent/windows.iso"))
        #expect(image.kind == .unknown)
    }
}
