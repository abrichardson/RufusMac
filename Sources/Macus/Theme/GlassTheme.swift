import SwiftUI
import MacusKit

/// Brand constants and shared design tokens for Macus.
/// Identity strings come from `MacusInfo` (single source of truth).
enum Brand {
    static let name = MacusInfo.name
    static let tagline = MacusInfo.tagline
    static let author = MacusInfo.author
    static let site = MacusInfo.site
    static let siteURL = URL(string: "https://\(MacusInfo.site)")!
    static let repoURL = URL(string: MacusInfo.repo)!

    /// Primary accent — a refined teal that reads well on Liquid Glass.
    static let accent = Color(red: 0.22, green: 0.37, blue: 0.91)
    /// Deeper companion accent for gradients.
    static let accentDeep = Color(red: 0.09, green: 0.46, blue: 0.78)
    /// Destructive / warning red for disk-erase actions.
    static let danger = Color(red: 0.95, green: 0.29, blue: 0.33)
}

/// A soft, color-tinted backdrop so the Liquid Glass material has something
/// rich to refract and reflect. Adapts automatically to light/dark appearance.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Brand.accent.opacity(0.18),
                    Brand.accentDeep.opacity(0.12),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Brand.accent.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// A labelled section header used above each glass card.
struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}
