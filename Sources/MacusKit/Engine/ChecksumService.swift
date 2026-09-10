import Foundation

/// Computes and verifies image checksums. Used to confirm a download is intact
/// before writing, and (in the dd plan) to verify the drive after writing.
public struct ChecksumService: Sendable {
    public enum Algorithm: String, Sendable { case sha256 = "256", sha512 = "512", sha1 = "1" }

    public init() {}

    /// Compute a checksum of a file using the system `shasum`.
    public func checksum(of url: URL, algorithm: Algorithm = .sha256) async throws -> String {
        let output = try await Shell.output("/usr/bin/shasum", ["-a", algorithm.rawValue, url.path])
        return output.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Verify a file against an expected checksum (case-insensitive).
    public func verify(_ url: URL, expected: String, algorithm: Algorithm = .sha256) async throws -> Bool {
        let actual = try await checksum(of: url, algorithm: algorithm)
        return actual.caseInsensitiveCompare(expected.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
