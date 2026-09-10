import Foundation

/// Resolves the external CLI tools the engines shell out to.
///
/// Built-in macOS tools (`diskutil`, `hdiutil`, `dd`) are always present.
/// The extras (`wimlib-imagex`, `mke2fs`, Ventoy boot files) are bundled in the
/// app's `Resources/thirdparty` by `scripts/fetch_thirdparty.sh`; during
/// development we fall back to Homebrew locations.
public struct ToolPaths: Sendable {
    public var diskutil = "/usr/sbin/diskutil"
    public var hdiutil = "/usr/bin/hdiutil"
    public var dd = "/bin/dd"
    public var rsync = "/usr/bin/rsync"
    public var shasum = "/usr/bin/shasum"

    public var wimlib: String
    public var mke2fs: String
    public var ventoyDir: String

    public init(wimlib: String = "wimlib-imagex", mke2fs: String = "mke2fs", ventoyDir: String = "ventoy") {
        self.wimlib = wimlib
        self.mke2fs = mke2fs
        self.ventoyDir = ventoyDir
    }

    /// Resolve tool locations, preferring bundled copies, then Homebrew.
    public static func resolve(thirdPartyDir: String?) -> ToolPaths {
        func pick(_ candidates: [String], fallback: String) -> String {
            for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
            return fallback
        }

        let bundled = thirdPartyDir.map { dir in
            (
                wimlib: "\(dir)/wimlib-imagex",
                mke2fs: "\(dir)/mke2fs",
                ventoy: "\(dir)/ventoy"
            )
        }

        return ToolPaths(
            wimlib: pick([bundled?.wimlib, "/opt/homebrew/bin/wimlib-imagex", "/usr/local/bin/wimlib-imagex"].compactMap { $0 },
                         fallback: "wimlib-imagex"),
            mke2fs: pick([bundled?.mke2fs, "/opt/homebrew/sbin/mke2fs", "/opt/homebrew/opt/e2fsprogs/sbin/mke2fs"].compactMap { $0 },
                         fallback: "mke2fs"),
            ventoyDir: bundled?.ventoy ?? (thirdPartyDir.map { "\($0)/ventoy" } ?? "ventoy")
        )
    }
}
