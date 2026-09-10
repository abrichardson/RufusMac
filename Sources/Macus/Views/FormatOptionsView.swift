import SwiftUI
import MacusKit

/// The configuration panel — Rufus-style options, shown contextually per mode.
struct FormatOptionsView: View {
    @Bindable var model: AppModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: model.requiresImage ? "03 / Make it yours" : "Format settings", systemImage: "slider.horizontal.3")

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
                Toggle("Bypass TPM, Secure Boot, and RAM checks (experimental)",
                       isOn: $model.config.windows11Bypass)
                .tint(Brand.accent)
                Divider()
                Text("Windows account setup").font(.subheadline.bold())
                Toggle("Create a local administrator account", isOn: $model.config.windowsSetup.createLocalAccount)
                if model.config.windowsSetup.createLocalAccount {
                    TextField("Windows username", text: $model.config.windowsSetup.username)
                        .textFieldStyle(.roundedBorder)
                    if let error = model.config.windowsSetup.validationError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Text("Creates the account with a blank password, then requests a password change at the next sign-in. No password is stored on the USB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Allow setup without a Microsoft account", isOn: $model.config.windowsSetup.skipMicrosoftAccount)
                Text("The bypass alone may require disconnecting the PC from the internet. Windows S mode is not supported.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Skip privacy questions (decline optional data sharing)", isOn: $model.config.windowsSetup.skipPrivacyQuestions)

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
