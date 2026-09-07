import SwiftUI
import RufusMacKit

/// The configuration panel — Rufus-style options, shown contextually per mode.
struct FormatOptionsView: View {
    @Bindable var model: AppModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Options", systemImage: "slider.horizontal.3")

                if model.showsFormatOptions || model.mode == .multiboot {
                    labelField
                }

                if model.showsFormatOptions {
                    schemeAndSystem
                    fileSystemRow
                }

                togglesRow
            }
        }
    }

    private var labelField: some View {
        HStack {
            Text("Volume label").frame(width: 130, alignment: .leading)
            TextField("Label", text: $model.config.volumeLabel)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var schemeAndSystem: some View {
        HStack(spacing: 12) {
            HStack {
                Text("Scheme").frame(width: 130, alignment: .leading)
                Picker("", selection: $model.config.partitionScheme) {
                    ForEach(PartitionScheme.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            HStack {
                Text("Target").frame(alignment: .leading)
                Picker("", selection: $model.config.targetSystem) {
                    ForEach(model.isWindowsSingle ? [TargetSystem.uefi] : TargetSystem.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    private var fileSystemRow: some View {
        HStack {
            Text("File system").frame(width: 130, alignment: .leading)
            Picker("", selection: $model.config.fileSystem) {
                ForEach(model.isWindowsSingle ? [BootFileSystem.fat32] : [.fat32, .exfat]) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var togglesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.requiresImage {
                Toggle("Verify after write", isOn: $model.config.verifyAfterWrite)
            }

            if model.isWindowsSingle {
                Toggle("Bypass Windows 11 checks (experimental; compatibility varies)",
                       isOn: $model.config.windows11Bypass)
                .tint(Brand.accent)
            }
            if model.mode == .multiboot {
                Stepper(
                    "Linux persistence: \(model.config.persistenceMB == 0 ? "off" : "\(model.config.persistenceMB) MB")",
                    value: $model.config.persistenceMB, in: 0...32768, step: 512
                )
            }
            if model.mode == .dd {
                Text("DD mode writes the image byte-for-byte. Partition scheme, file system, and label come from the image itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}
