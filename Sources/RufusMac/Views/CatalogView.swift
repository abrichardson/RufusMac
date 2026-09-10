import SwiftUI
import RufusMacKit

/// A browsable list of popular bootable images. Opens the official download
/// page; after downloading, the user drags the ISO into RufusMac (which can
/// verify its checksum before writing).
struct CatalogView: View {
    let onClose: () -> Void
    @State private var catalog = DistroCatalog.bundled()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ISO Catalog", systemImage: "square.grid.2x2")
                    .font(.title2.bold())
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Text("Jump to an official download. Verify the checksum after downloading, then drag the ISO into \(Brand.name).")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(catalog.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 560)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .foregroundStyle(Brand.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).fontWeight(.semibold)
                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.category)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Brand.accent.opacity(0.2), in: .capsule)
            if let url = URL(string: entry.pageURL) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.accent)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
