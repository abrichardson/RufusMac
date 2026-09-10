import SwiftUI
import MacusKit

extension BurnMode {
    var systemImage: String {
        switch self {
        case .single: return "opticaldisc"
        case .multiboot: return "square.stack.3d.up"
        case .dd: return "doc.badge.gearshape"
        case .reclaim: return "arrow.counterclockwise"
        }
    }
    var navigationTitle: String {
        switch self {
        case .single: return "Create installer"
        case .dd: return "Write disk image"
        case .reclaim: return "Restore USB"
        case .multiboot: return "Multiboot"
        }
    }
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var showCredits = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(spacing: 18) {
                            if model.requiresImage { BootSelectionView(model: model) }
                            DevicePickerView(model: model)
                            FormatOptionsView(model: model)
                        }
                        .padding(28)
                    }
                    actionBar
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .disabled(model.isRunning)
            if model.isRunning {
                RunningOverlay(stage: model.runningStage, detail: model.runningDetail, startedAt: model.runStartedAt)
            }
        }
        .tint(Brand.accent)
        .task { await model.refreshDrives() }
        .sheet(isPresented: $model.showConfirm) { ConfirmationView(model: model) }
        .sheet(isPresented: $showCredits) { CreditsView() }
        .alert(model.resultMessage ?? "", isPresented: Binding(
            get: { model.resultMessage != nil },
            set: { if !$0 { model.dismissResult() } }
        )) { Button("OK") { model.dismissResult() } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "externaldrive.fill.badge.plus")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Brand.accent, in: .rect(cornerRadius: 15))
                Text(Brand.name).font(.system(size: 23, weight: .bold))
                Text("A fresh start.\nOne USB away.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4)).padding(.bottom, 8)
                ForEach([BurnMode.single, .dd, .reclaim]) { mode in
                    Button { model.mode = mode } label: {
                        Label(mode.navigationTitle, systemImage: mode.systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(model.mode == mode ? .white.opacity(0.12) : .clear, in: .rect(cornerRadius: 9))
                            .foregroundStyle(model.mode == mode ? .white : .white.opacity(0.58))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label("Built for macOS", systemImage: "desktopcomputer")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
                Divider().overlay(.white.opacity(0.1))
                FooterView()
                Button("About & credits") { showCredits = true }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(22)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color(red: 0.065, green: 0.09, blue: 0.15))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.mode.navigationTitle).font(.system(size: 27, weight: .semibold))
                Text(model.mode == .reclaim ? "Turn your USB back into everyday storage." : "Choose your image, connect a USB, and make it bootable.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("MAC EDITION").font(.system(size: 9, weight: .bold)).tracking(1)
                .padding(8).background(Brand.accent.opacity(0.08), in: .capsule)
                .foregroundStyle(Brand.accent)
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 16)
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedDrive?.title ?? "Connect a USB to continue")
                    .font(.callout.weight(.semibold)).lineLimit(1)
                Text(model.selectedDrive == nil ? "Your internal storage is excluded." : "All data on the selected USB will be erased.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.prepare() } label: {
                Label(model.mode == .reclaim ? "Review & restore" : "Review & write", systemImage: "arrow.right")
                    .font(.callout.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStart)
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
