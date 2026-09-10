import Foundation
import Testing
@testable import MacusKit

struct WindowsSetupTests {
    @Test func defaultsLeaveSetupUntouched() throws {
        #expect(try WindowsSetupOptions().answerFile(architecture: "") == nil)
    }

    @Test(arguments: ["", "Administrator", "GUEST", "DefaultAccount", "user&admin", "user\"", "user%name", " user", "user.", "user ", "abcdefghijklmnopqrstu", "../user"])
    func invalidNamesAreRejected(name: String) {
        var options = WindowsSetupOptions()
        options.createLocalAccount = true
        options.username = name
        #expect(options.validationError != nil)
        #expect(throws: (any Error).self) { try options.answerFile(architecture: "amd64") }
    }

    @Test(arguments: 1..<16)
    func combinationsProduceValidXML(mask: Int) throws {
        var options = WindowsSetupOptions()
        options.createLocalAccount = mask & 1 != 0
        options.skipMicrosoftAccount = mask & 2 != 0
        options.skipPrivacyQuestions = mask & 4 != 0
        options.username = "Adam Test"
        for architecture in ["amd64", "arm64"] {
            let xml = try #require(try options.answerFile(architecture: architecture, bypassHardware: mask & 8 != 0))
            let document = try XMLDocument(xmlString: xml)
            let accounts = try document.nodes(forXPath: "//*[local-name()='LocalAccount']")
            #expect(accounts.count == (options.createLocalAccount ? 1 : 0))
            #expect(xml.contains("pass=\"windowsPE\"") == (mask & 8 != 0))
            #expect(xml.contains("BypassNRO") == options.skipMicrosoftAccount)
            #expect(xml.contains("ProtectYourPC") == options.skipPrivacyQuestions)
            #expect(xml.contains("processorArchitecture=\"\(architecture)\""))
            #expect(!xml.contains("AutoLogon"))
            #expect(!xml.contains("DiskConfiguration"))
            #expect(!xml.contains("HideEULAPage"))
            if options.createLocalAccount {
                let commands = try document.nodes(forXPath: "//*[local-name()='CommandLine']")
                #expect(commands.first?.stringValue == "net user \"Adam Test\" /logonpasswordchg:yes")
            }
        }
    }

    @Test func customizationRequiresKnownArchitecture() throws {
        var options = WindowsSetupOptions()
        options.skipMicrosoftAccount = true
        #expect(throws: (any Error).self) { try options.answerFile(architecture: "") }
    }

    @Test func userAndOEMPlacement() async throws {
        let fixture = try WindowsWriterTests.Fixture()
        var options = WindowsSetupOptions()
        options.createLocalAccount = true
        options.username = "Adam"
        options.skipMicrosoftAccount = true
        let result = try await fixture.run(setup: options)
        #expect(result.ok, "\(result.stderr)")
        let answer = fixture.destination.appendingPathComponent("sources/$OEM$/$$/Panther/unattend.xml")
        let xml = try String(contentsOf: answer, encoding: .utf8)
        #expect(xml.contains("<Name>Adam</Name>"))
        #expect(xml.contains("pass=\"specialize\""))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("autounattend.xml").path))
    }

    @Test func invalidAccountStopsBeforeDiskAccess() async throws {
        let fixture = try WindowsWriterTests.Fixture()
        var options = WindowsSetupOptions()
        options.createLocalAccount = true
        options.username = "Administrator"
        let result = try await fixture.run(setup: options)
        #expect(!result.ok)
        #expect(fixture.calls.isEmpty)
    }

    @Test func streamedOutputArrivesBeforeProcessExit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let signal = directory.appendingPathComponent("received")
        // The child only succeeds if its output callback runs while it is alive.
        let result = try await Shell.run("/bin/bash", ["-c", "printf 'RM_STAGE|Copying\\n'; for ((i=0;i<50;i++)); do [ -f \(Shell.quote(signal.path)) ] && exit 0; sleep 0.05; done; exit 1"], onOutput: { _ in
            try? Data().write(to: signal)
        })
        #expect(result.ok)
    }
}
