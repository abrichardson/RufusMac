import Foundation

/// Single source of truth for app identity, shared by the SwiftUI app, the
/// `rmctl` CLI, and the test suite.
public enum RufusMacInfo {
    public static let name = "Macus"
    public static let version = "0.2.0"
    public static let tagline = "A fresh start. One USB away."
    public static let author = "SynapsEdge"
    public static let site = "github.com/abrichardson/RufusMac"
    public static let repo = "https://github.com/abrichardson/RufusMac"
}
