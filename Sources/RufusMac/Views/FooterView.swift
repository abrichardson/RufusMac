import SwiftUI
import RufusMacKit

struct FooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CREATED BY").font(.system(size: 9, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.4))
            Text(Brand.author).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Brand.name).font(.largeTitle.bold())
            Text("Created by \(Brand.author)").font(.headline)
            Text("Version \(RufusMacInfo.version)").foregroundStyle(.secondary)
            Divider()
            Text("Built on RufusMac by Harith Dilshan (h4rithd.com). Original copyright and GPLv3 license retained. Windows image support uses wimlib by Eric Biggers and contributors. This app is not affiliated with the official Rufus project.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Source & license", destination: Brand.repoURL)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
    }
}
