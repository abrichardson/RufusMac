import SwiftUI
import MacusKit

/// Destructive-action gate. Shows the plan summary, the data-loss warnings, an
/// expandable preview of the exact commands, and requires an explicit
/// acknowledgement before the write button is enabled. Also offers a safe
/// dry-run ("Preview only").
struct ConfirmationView: View {
    @Bindable var model: AppModel
    @State private var showScript = false

    var body: some View {
        let plan = model.pendingPlan
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Brand.danger)
                Text("Confirm — \(plan?.mode.rawValue ?? "")")
                    .font(.title2.bold())
            }

            Text(plan?.summary ?? "")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan?.warnings ?? [], id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(Brand.danger)
                }
                if plan?.experimental == true {
                    Label("This is an experimental feature.", systemImage: "flask.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            DisclosureGroup("Preview the exact commands", isExpanded: $showScript) {
                ScrollView {
                    Text(plan?.script ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 180)
                .background(.black.opacity(0.25), in: .rect(cornerRadius: 8))
            }

            Toggle(isOn: $model.acknowledgedErase) {
                Text("I understand **all data** on \(model.selectedDrive?.title ?? "the drive") will be erased.")
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Cancel") { model.showConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview only") {
                    Task { await model.execute(dryRun: true) }
                }
                Button("Erase & Write") {
                    Task { await model.execute(dryRun: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.danger)
                .disabled(!model.acknowledgedErase)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
