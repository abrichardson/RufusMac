import SwiftUI
import MacusKit

/// Lists external/removable USB drives and lets the user pick the target.
/// Internal disks never appear here — `DiskService` filters them out.
struct DevicePickerView: View {
    @Bindable var model: AppModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: model.requiresImage ? "02 / USB destination" : "USB destination", systemImage: "externaldrive")
                    Spacer()
                    Button {
                        Task { await model.refreshDrives() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: model.isRefreshing)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan for USB drives")
                }

                if model.drives.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.drives) { drive in
                            driveRow(drive)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("No USB drive detected")
                    .fontWeight(.medium)
                Text("Plug in a USB drive, then press refresh. Internal disks are never shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func driveRow(_ drive: USBDrive) -> some View {
        let isSelected = drive.id == model.selectedDriveID
        return Button {
            model.selectedDriveID = drive.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mediastick")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Brand.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.title).fontWeight(.medium)
                    Text(drive.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Brand.accent : .secondary.opacity(0.5))
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Brand.accent.opacity(0.08) : Color.primary.opacity(0.025), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Brand.accent.opacity(0.35) : .clear).allowsHitTesting(false) }
    }
}
