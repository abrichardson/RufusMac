import Foundation
import Security
import Darwin
import CryptoKit
import MacusDiskAccess

/// Uses the macOS authorization dialog to obtain a descriptor, then performs
/// I/O in the app's own process, retaining its removable-volume permission.
enum AuthorizedDevice {
    static func open(_ path: String) throws -> FileHandle {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess,
              let authorization else { throw failure("Could not start macOS disk authorization.") }
        defer { AuthorizationFree(authorization, []) }
        var external = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authorization, &external) == errAuthorizationSuccess else {
            throw failure("Could not prepare macOS disk authorization.")
        }
        let fd = withUnsafePointer(to: &external) { pointer in
            path.withCString { macus_authorized_open($0, pointer, MemoryLayout<AuthorizationExternalForm>.size) }
        }
        guard fd >= 0 else {
            throw failure("USB access was not authorized. No data was written. Allow the macOS authorization and removable-volume prompts. If access remains blocked, check System Settings → Privacy & Security → Files and Folders → Macus → Removable Volumes, then reopen Macus and retry.")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func size(of handle: FileHandle) throws -> UInt64 {
        var size: UInt64 = 0
        guard macus_device_size(handle.fileDescriptor, &size) == 0 else {
            throw failure("Could not verify the opened USB device. No data was written.")
        }
        return size
    }

    /// Shared with regular-file fixtures. Caller validates physical device first.
    static func write(image: URL, to target: FileHandle, capacity: UInt64, expectedHash: String) throws {
        let source = try FileHandle(forReadingFrom: image)
        defer { try? source.close() }
        let size = try source.seekToEnd()
        guard size > 0, size % 1048576 == 0, size + 1048576 <= capacity else {
            throw failure("USB is too small or the image is incomplete. No data was written.")
        }
        // Verify through the same source descriptor used for copying.
        try source.seek(toOffset: 0)
        guard try digest(source, count: size) == expectedHash else {
            throw failure("Diagnostics image checksum failed. No data was written.")
        }
        try source.seek(toOffset: 0)
        try target.seek(toOffset: 0)
        var remaining = size
        while remaining > 0 {
            let count = Int(min(remaining, 4 * 1048576))
            guard let data = try source.read(upToCount: count), data.count == count else {
                throw failure("Image read failed. Recreate this USB before using it.")
            }
            try target.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
        // Remove stale backup partition maps on drives larger than the image.
        try target.seek(toOffset: capacity - 1048576)
        try target.write(contentsOf: Data(repeating: 0, count: 1048576))
        try target.synchronize()
        try target.seek(toOffset: 0)
        guard try digest(target, count: size) == expectedHash else {
            throw failure("USB verification failed. Recreate this USB before using it.")
        }
        try target.seek(toOffset: capacity - 1048576)
        guard try target.read(upToCount: 1048576) == Data(repeating: 0, count: 1048576) else {
            throw failure("USB partition-map cleanup could not be verified. Recreate this USB.")
        }
    }

    static func digest(_ handle: FileHandle, count: UInt64) throws -> String {
        var hash = SHA256()
        var remaining = count
        while remaining > 0 {
            let size = Int(min(remaining, 4 * 1048576))
            guard let data = try handle.read(upToCount: size), !data.isEmpty else {
                throw failure("Could not read all bytes for verification.")
            }
            hash.update(data: data)
            remaining -= UInt64(data.count)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Macus.AuthorizedDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
