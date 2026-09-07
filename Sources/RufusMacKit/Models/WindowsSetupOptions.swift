import Foundation

/// Windows OOBE customization, independent of hardware requirement bypasses.
/// Uses documented unattended-setup settings and Rufus's OEM/Panther placement.
public struct WindowsSetupOptions: Sendable {
    public var createLocalAccount = false
    public var username = ""
    public var skipMicrosoftAccount = false
    public var skipPrivacyQuestions = false

    public init() {}
    public var isEnabled: Bool { createLocalAccount || skipMicrosoftAccount || skipPrivacyQuestions }

    public var validationError: String? {
        guard createLocalAccount else { return nil }
        // Conservative subset avoids both Windows reserved characters and
        // command interpretation in FirstLogonCommands. Never silently rename.
        guard username.range(of: "^[A-Za-z0-9][A-Za-z0-9 _.-]{0,19}$", options: .regularExpression) != nil,
              !username.hasSuffix(" "), !username.hasSuffix(".") else {
            return "Use 1–20 characters: start with a letter or number; use letters, numbers, spaces, dots, hyphens, or underscores. Don't end with a space or dot."
        }
        let reserved = ["administrator", "guest", "defaultaccount", "defaultuser0", "wdagutilityaccount", "system", "local service", "network service", "default", "public"]
        guard !reserved.contains(username.lowercased()) else { return "That name is reserved by Windows. Choose another username." }
        return nil
    }

    public func answerFile(architecture: String, bypassHardware: Bool = false) throws -> String? {
        guard isEnabled || bypassHardware else { return nil }
        if let error = validationError { throw SetupError.invalid(error) }
        guard ["amd64", "arm64"].contains(architecture) else {
            throw SetupError.invalid("Windows customization requires an identified x64 or ARM64 installer.")
        }
        func component(_ name: String, _ contents: String) -> String {
            "<component name=\"\(name)\" processorArchitecture=\"\(architecture)\" publicKeyToken=\"31bf3856ad364e35\" language=\"neutral\" versionScope=\"nonSxS\">\n\(contents)\n</component>"
        }
        var passes: [String] = []
        if bypassHardware {
            let commands = ["BypassTPMCheck", "BypassSecureBootCheck", "BypassRAMCheck"].enumerated().map { index, key in
                "<RunSynchronousCommand wcm:action=\"add\"><Order>\(index + 1)</Order><Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v \(key) /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>"
            }.joined(separator: "\n")
            passes.append("<settings pass=\"windowsPE\">\(component("Microsoft-Windows-Setup", "<RunSynchronous>" + commands + "</RunSynchronous>"))</settings>")
        }
        if skipMicrosoftAccount {
            let command = #"reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f"#
            let content = "<RunSynchronous><RunSynchronousCommand wcm:action=\"add\"><Order>1</Order><Path>\(Self.xml(command))</Path></RunSynchronousCommand></RunSynchronous>"
            passes.append("<settings pass=\"specialize\">\(component("Microsoft-Windows-Deployment", content))</settings>")
        }
        var shell: [String] = []
        if skipPrivacyQuestions {
            shell.append("<OOBE><ProtectYourPC>3</ProtectYourPC></OOBE>")
        }
        if createLocalAccount {
            let name = Self.xml(username)
            let command = Self.xml("net user \"\(username)\" /logonpasswordchg:yes")
            shell.append("""
            <UserAccounts><LocalAccounts><LocalAccount wcm:action="add">
              <Name>\(name)</Name><DisplayName>\(name)</DisplayName><Group>Administrators</Group>
              <Password><Value>UABhAHMAcwB3AG8AcgBkAA==</Value><PlainText>false</PlainText></Password>
            </LocalAccount></LocalAccounts></UserAccounts>
            <FirstLogonCommands><SynchronousCommand wcm:action="add">
              <Order>1</Order><CommandLine>\(command)</CommandLine>
              <Description>Request an account password at the next sign-in</Description>
            </SynchronousCommand></FirstLogonCommands>
            """)
        }
        if !shell.isEmpty {
            passes.append("<settings pass=\"oobeSystem\">\(component("Microsoft-Windows-Shell-Setup", shell.joined(separator: "\n")))</settings>")
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
        \(passes.joined(separator: "\n"))
        </unattend>
        """
    }

    static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    enum SetupError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}
