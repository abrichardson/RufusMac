import SwiftUI

/// Application entry point.
///
/// RufusMac is a single-window utility, so we use `Window` (not `WindowGroup`)
/// to keep exactly one instance. The whole UI is rendered on Apple's Liquid Glass
/// material, available natively on macOS 26 (Tahoe) and later.
@main
struct RufusMacApp: App {
    @State private var showCredits = false
    var body: some Scene {
        Window(Brand.name, id: "main") {
            ContentView()
                .frame(minWidth: 880, idealWidth: 940, minHeight: 700)
                .sheet(isPresented: $showCredits) { CreditsView() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 940, height: 840)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.name)") { showCredits = true }
            }
        }
    }
}
