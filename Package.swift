// swift-tools-version: 6.0
import PackageDescription

// Macus — a native macOS bootable-USB creator with Liquid Glass UI.
// Developed by Harith Dilshan / h4rithd.com — built with the help of Claude Code.
//
// Two targets keep UI and logic cleanly separated and testable:
//   • MacusKit — pure Swift engine (disk enumeration, writers, checksums). No UI.
//   • Macus    — the SwiftUI app (@main), depends on MacusKit.
//
// Builds with the Command Line Tools toolchain (no full Xcode required).
// `scripts/build_app.sh` wraps the product into a portable Macus.app.
let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5)
]

let package = Package(
    name: "Macus",
    platforms: [
        .macOS("26.0") // Liquid Glass requires the macOS 26 SDK
    ],
    targets: [
        .target(name: "MacusDiskAccess", path: "Sources/MacusDiskAccess", publicHeadersPath: "include"),
        .target(
            name: "MacusKit",
            dependencies: ["MacusDiskAccess"],
            path: "Sources/MacusKit",
            resources: [
                .process("Resources/distros.json"),
                .process("Resources/windows-write.sh"),
                .copy("Resources/InventoryToolkit")
            ],
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "Macus",
            dependencies: ["MacusKit"],
            path: "Sources/Macus",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "macusctl",
            dependencies: ["MacusKit"],
            path: "Sources/macusctl",
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "MacusKitTests",
            dependencies: ["MacusKit"],
            path: "Tests/MacusKitTests",
            swiftSettings: commonSwiftSettings
        )
    ]
)
