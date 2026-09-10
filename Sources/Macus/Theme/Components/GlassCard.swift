import SwiftUI

/// A rounded content container rendered on the Liquid Glass material.
///
/// Wrap related controls in a `GlassCard` to get the translucent, refractive
/// look that defines the Macus UI. Place multiple cards inside a
/// `GlassEffectContainer` so their glass blends and morphs together.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.07)).allowsHitTesting(false) }
    }
}
