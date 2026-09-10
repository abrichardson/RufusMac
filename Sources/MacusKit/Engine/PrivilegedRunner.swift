import Foundation

/// Executes auditable write scripts. Windows scripts run as the current user
/// and elevate only formatting; raw/reclaim scripts use an administrator
/// process. Normal-user stdout/stderr is streamed for live progress.
public actor PrivilegedRunner {
    public var dryRun: Bool
    public private(set) var lastScript: String = ""

    public init(dryRun: Bool = false) {
        self.dryRun = dryRun
    }

    public func setDryRun(_ value: Bool) {
        dryRun = value
    }

    /// Run with the requested privilege mode, or return a dry-run preview.
    @discardableResult
    public func run(script: String, prompt: String, requiresAdministrator: Bool = true, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> String {
        lastScript = script

        if dryRun {
            return "[dry-run] execution skipped:\n\(script)"
        }

        // Write the script to a temp file and execute it as admin in one prompt.
        // This avoids fragile AppleScript escaping of multi-line shell scripts.
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macus-\(UUID().uuidString).sh")
        let fullScript = "#!/bin/sh\nset -euo pipefail\n\(script)\n"
        try fullScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        func appleQuote(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        if !requiresAdministrator {
            return try await Shell.output("/bin/bash", [scriptURL.path], onOutput: onOutput)
        }
        let command = "/bin/bash " + Shell.quote(scriptURL.path)
        let appleScript = "do shell script \"\(appleQuote(command))\" with prompt \"\(appleQuote(prompt))\" with administrator privileges"

        let result = try await Shell.run("/usr/bin/osascript", ["-e", appleScript], onOutput: onOutput)
        guard result.ok else {
            throw ShellError.nonZeroExit(command: "osascript (admin)", status: result.status, stderr: result.stderr)
        }
        return result.stdout
    }
}
