import Testing
import Foundation
@testable import MacusKit

/// Tests for `DiskParser` — especially the internal-disk safety filter, which is
/// the single most important data-loss guard in the whole app.
///
/// Uses Swift Testing (`import Testing`), which ships with the Swift toolchain,
/// so the suite runs without a full Xcode install.
struct DiskParserTests {

    let listPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>AllDisksAndPartitions</key>
      <array>
        <dict>
          <key>Content</key><string>FDisk_partition_scheme</string>
          <key>DeviceIdentifier</key><string>disk4</string>
          <key>Partitions</key>
          <array>
            <dict>
              <key>Content</key><string>Windows_NTFS</string>
              <key>DeviceIdentifier</key><string>disk4s1</string>
              <key>MountPoint</key><string>/Volumes/SanDisk</string>
              <key>VolumeName</key><string>SanDisk</string>
            </dict>
          </array>
          <key>Size</key><integer>125162225664</integer>
        </dict>
      </array>
    </dict>
    </plist>
    """

    let externalInfoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
      <key>DeviceNode</key><string>/dev/disk4</string>
      <key>MediaName</key><string>SanDisk 3.2 Gen1</string>
      <key>IORegistryEntryName</key><string>SanDisk SanDisk 3.2 Gen1 Media</string>
      <key>TotalSize</key><integer>125162225664</integer>
      <key>BusProtocol</key><string>USB</string>
      <key>Internal</key><false/>
      <key>Removable</key><true/>
      <key>Ejectable</key><true/>
    </dict></plist>
    """

    let internalInfoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
      <key>DeviceNode</key><string>/dev/disk0</string>
      <key>MediaName</key><string>APPLE SSD AP1024</string>
      <key>TotalSize</key><integer>994662584320</integer>
      <key>BusProtocol</key><string>Apple Fabric</string>
      <key>Internal</key><true/>
      <key>Removable</key><false/>
      <key>Ejectable</key><false/>
    </dict></plist>
    """

    @Test func wholeDiskParsing() throws {
        let disks = try DiskParser.wholeDisks(fromListPlist: Data(listPlist.utf8))
        #expect(disks.count == 1)
        #expect(disks.first?.id == "disk4")
        #expect(disks.first?.mountPoints == ["/Volumes/SanDisk"])
        #expect(disks.first?.content == "FDisk_partition_scheme")
    }

    @Test func externalDriveAccepted() throws {
        let drive = try #require(
            try DiskParser.drive(
                fromInfoPlist: Data(externalInfoPlist.utf8),
                mountPoints: ["/Volumes/SanDisk"],
                content: "FDisk_partition_scheme"
            ),
            "External USB drive must be accepted"
        )
        #expect(drive.id == "disk4")
        #expect(drive.sizeBytes == 125_162_225_664)
        #expect(drive.deviceNode == "/dev/disk4")
        #expect(drive.rawDeviceNode == "/dev/rdisk4")
        #expect(drive.isSafeTarget)
        #expect(drive.isInternal == false)
    }

    @Test func internalDriveRejected() throws {
        // The critical safety assertion: an internal disk must NEVER be returned.
        let drive = try DiskParser.drive(
            fromInfoPlist: Data(internalInfoPlist.utf8),
            mountPoints: [],
            content: nil
        )
        #expect(drive == nil, "Internal disk must be filtered out — never a write target")
    }

    @Test func byteCountFormatting() {
        #expect(ByteCount.string(125_162_225_664).isEmpty == false)
    }
}
