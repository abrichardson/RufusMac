import SwiftUI
import UniformTypeIdentifiers
import AppKit
import RufusMacKit

/// Drag-and-drop / file-picker selection of the boot image, with auto-detected
/// type badge and size.
struct BootSelectionView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false
    @State private var showCatalog = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "Boot selection", systemImage: "opticaldisc")
                    Spacer()
                    Button {
                        showCatalog = true
                    } label: {
                        Label("Browse catalog", systemImage: "square.grid.2x2")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.accent)
                }

                if model.isInspecting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Inspecting image…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                } else if let image = model.image {
                    selectedRow(image)
                } else {
                    dropZone
                }
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted, perform: acceptDrop)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isTargeted ? Brand.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showCatalog) {
            CatalogView { showCatalog = false }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Extension filtering also accepts ISO files whose registered UTI does
        // not conform to public.data (seen with third-party ISO associations).
        panel.allowedFileTypes = ["iso", "img", "dmg"]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.selectImage(url) }
        }
    }

    private var dropZone: some View {
        Button {
            chooseImage()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(Brand.accent)
                Text("Drag an ISO / IMG here")
                    .fontWeight(.medium)
                Text("or click to choose · Windows, Linux, and other images supported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Brand.accent : .secondary.opacity(0.4))
                .allowsHitTesting(false)
        )
    }

    /// Finder provides public.file-url data. Load that representation directly
    /// instead of relying on URL Transferable's generic URL conversion.
    /// The handler lives on the whole card so a drop can replace an image too.
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isRunning, !model.isInspecting, !model.showConfirm,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
              }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            } else if let value = item as? String {
                url = URL(string: value)
            } else {
                url = nil
            }
            Task { @MainActor in
                guard error == nil, let url, url.isFileURL else {
                    model.resultIsError = true
                    model.resultMessage = "Couldn't read the dropped file. Drag an ISO, IMG, or DMG from Finder."
                    return
                }
                await model.selectImage(url)
            }
        }
        return true
    }

    private func selectedRow(_ image: BootImage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: image.kind.systemImage)
                .font(.title2)
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(image.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    kindBadge(image.kind)
                    Text(image.displaySize).font(.caption).foregroundStyle(.secondary)
                    if image.hasOversizedWIM {
                        Text("WIM > 4 GB → auto-split")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button {
                chooseImage()
            } label: { Text("Change") }
                .buttonStyle(.plain).foregroundStyle(Brand.accent)
            Button {
                model.clearImage()
            } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func kindBadge(_ kind: ImageKind) -> some View {
        Text(kind.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(badgeColor(kind).opacity(0.22), in: .capsule)
            .foregroundStyle(badgeColor(kind))
    }

    private func badgeColor(_ kind: ImageKind) -> Color {
        switch kind {
        case .windows: return .blue
        case .linux: return .orange
        case .raw: return .purple
        case .unknown: return .gray
        }
    }
}
