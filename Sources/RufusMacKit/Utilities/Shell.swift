import Foundation

/// Result of running an external process.
struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(command: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return "Failed to launch process: \(message)"
        case let .nonZeroExit(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed (exit \(status))" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// Minimal async wrapper around `Process` for read-only / unprivileged commands
/// (`diskutil info`, `hdiutil`, checksum tools). Destructive work goes through
/// `PrivilegedRunner` instead.
enum Shell {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                    return
                }

                // Drain stderr concurrently so a full pipe cannot deadlock the writer.
                let errorRead = DispatchGroup()
                errorRead.enter()
                final class Buffer: @unchecked Sendable { var data = Data() }
                let errors = Buffer()
                DispatchQueue.global().async {
                    errors.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errorRead.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                errorRead.wait()
                let errData = errors.data
                process.waitUntilExit()

                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }

    /// Run, requiring success; returns stdout or throws `ShellError.nonZeroExit`.
    static func output(_ launchPath: String, _ arguments: [String]) async throws -> String {
        let result = try await run(launchPath, arguments)
        guard result.ok else {
            throw ShellError.nonZeroExit(
                command: ([launchPath] + arguments).joined(separator: " "),
                status: result.status,
                stderr: result.stderr
            )
        }
        return result.stdout
    }
}
