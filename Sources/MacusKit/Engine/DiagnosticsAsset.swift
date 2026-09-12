import Foundation

/// Diagnostics are a separate download. The adjacent SHA-256 checks transfer
/// integrity; it is not a publisher signature. Only user-selected files are used.
public enum DiagnosticsAsset {
    public static func checksum(for image: URL) throws -> String {
        let checksum = image.appendingPathExtension("sha256")
        let attributes = try FileManager.default.attributesOfItem(atPath: checksum.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 4096,
              let line = try String(contentsOf: checksum, encoding: .utf8).split(whereSeparator: \.isNewline).first else {
            throw failure("The diagnostics checksum file is invalid.")
        }
        let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let first = parts.first else { throw failure("The diagnostics checksum file is empty.") }
        let hash = String(first).lowercased()
        guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw failure("The diagnostics checksum file is invalid.")
        }
        if parts.count == 2 {
            let name = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "", options: .anchored)
            guard name == image.lastPathComponent else { throw failure("The checksum names a different image.") }
        }
        return hash
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Macus.DiagnosticsAsset", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
