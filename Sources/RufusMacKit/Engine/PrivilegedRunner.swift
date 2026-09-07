import Foundation

/// Executes a privileged shell script (partitioning, formatting, `dd`, …) with a
/// single administrator-password prompt via macOS Authorization Services
/// (`osascript … with administrator privileges`).
///
/// The whole burn pipeline is assembled as one script and run once, so the user
/// is prompted a single time per operation. Set `dryRun` to capture the exact
/// script **without executing** — used by tests and the in-app "Preview
/// commands" feature so destructive actions are always auditable first.
public actor PrivilegedRunner {
    public var dryRun: Bool
    public private(set) var lastScript: String = ""

    public init(dryRun: Bool = false) {
        self.dryRun = dryRun
    }

    public func setDryRun(_ value: Bool) {
        dryRun = value
    }

    /// Run `script` as administrator. The user sees one native password dialog
    /// labelled with `prompt`. In dry-run mode the script is returned verbatim.
    @discardableResult
    public func run(script: String, prompt: String) async throws -> String {
        lastScript = script

        if dryRun {
            return "[dry-run] would execute as administrator:\n\(script)"
        }

        // Write the script to a temp file and execute it as admin in one prompt.
        // This avoids fragile AppleScript escaping of multi-line shell scripts.
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rufusmac-\(UUID().uuidString).sh")
        let fullScript = "#!/bin/sh\nset -euo pipefail\n\(script)\n"
        try fullScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        func appleQuote(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        let command = "/bin/bash " + Shell.quote(scriptURL.path)
        let appleScript = "do shell script \"\(appleQuote(command))\" with prompt \"\(appleQuote(prompt))\" with administrator privileges"

        let result = try await Shell.run("/usr/bin/osascript", ["-e", appleScript])
        guard result.ok else {
            throw ShellError.nonZeroExit(command: "osascript (admin)", status: result.status, stderr: result.stderr)
        }
        return result.stdout
    }
}
