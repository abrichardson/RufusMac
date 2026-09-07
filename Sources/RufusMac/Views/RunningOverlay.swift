import SwiftUI

/// Full-window overlay shown while a privileged operation is in progress.
struct RunningOverlay: View {
    let stage: String
    let detail: String
    let startedAt: Date

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(stage)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail).font(.caption.monospaced()).lineLimit(3)
                        .frame(maxWidth: 440).textSelection(.enabled)
                }
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                    Text("Elapsed: \(seconds / 60)m \(seconds % 60)s")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("You may be prompted for your administrator password.\nPlease don't unplug the drive.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .transition(.opacity)
    }
}
