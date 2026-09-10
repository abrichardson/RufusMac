import Foundation

/// Downloads an image from a direct URL (e.g. a catalog `directURL` or a link
/// the user pastes). Verification is handled separately by `ChecksumService`.
public actor Downloader {
    public init() {}

    public enum DownloadError: LocalizedError {
        case badStatus(Int)
        public var errorDescription: String? {
            switch self {
            case let .badStatus(code): return "Download failed (HTTP \(code))."
            }
        }
    }

    /// Download `url` to `destination`, returning the destination on success.
    @discardableResult
    public func download(from url: URL, to destination: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.badStatus(http.statusCode)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
