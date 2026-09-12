import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacusKit

struct InventoryView: View {
    @AppStorage("diagnosticsUSBPath") private var usbImagePath = ""
    @AppStorage("diagnosticsISOPath") private var isoImagePath = ""
    @State private var message = ""
    @State private var reports: [InventoryReport] = []
    @State private var selected: InventoryReport?
    @Binding var isBusy: Bool
    @State private var drives: [USBDrive] = []
    @State private var selectedDrive = ""
    @State private var usbRoots: [URL] = []
    @State private var selectedUSB = ""
    @State private var detectedReports: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Inventory & Diagnostics").font(.system(size: 27, weight: .semibold))
                Text("Know what’s inside. Record what works.")
                    .font(.callout).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Boot. Scan. Save.", systemImage: "stethoscope")
                            .font(.headline)
                        Text("Create a Diagnostics USB from a regular USB drive. Boot it on a PC and the scan starts automatically. Everything works offline.")
                        HStack {
                            Button("Choose diagnostics image…") { chooseImage(usb: true) }
                            Text(usbImagePath.isEmpty ? "Separate download · .img + .sha256" : URL(fileURLWithPath: usbImagePath).lastPathComponent)
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                        Picker("USB drive", selection: $selectedDrive) {
                            Text("Select a USB to erase").tag("")
                            ForEach(drives) { drive in
                                Text("\(drive.title) · \(drive.subtitle)").tag(drive.id)
                            }
                        }
                        HStack {
                            Button("Create Diagnostics USB", systemImage: "externaldrive.badge.plus") { createUSB() }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedDrive.isEmpty || usbImagePath.isEmpty)
                            Button("Refresh") { Task { await refreshUSBs() } }
                        }
                        Text("Erases the selected USB. Use a 2 GB or larger drive. Includes 512 MB for saved reports; remaining space is unused. For Intel/AMD PCs.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Then: boot the PC from USB → scan → Save & Shut Down → reconnect to your Mac and import reports.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Diagnostics is downloaded separately and stays outside Macus. Extract the image download first and keep its .sha256 file beside it.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Already have a Ventoy USB?") {
                            Button("Choose diagnostics ISO…") { chooseImage(usb: false) }
                            Text(isoImagePath.isEmpty ? "Select the separate .iso download" : URL(fileURLWithPath: isoImagePath).lastPathComponent).font(.caption)
                            Picker("Ventoy USB", selection: $selectedUSB) {
                                Text("Select a mounted Ventoy USB").tag("")
                                ForEach(usbRoots, id: \.path) { root in
                                    Text(root.lastPathComponent).tag(root.path)
                                }
                            }
                            Button("Add diagnostics to Ventoy") { installImage() }
                                .disabled(selectedUSB.isEmpty || isoImagePath.isEmpty)
                            Text("Preserves existing images and reports.").font(.caption)
                        }
                        DisclosureGroup("Advanced: export the standalone Linux toolkit") {
                            Button("Export toolkit folder…") { exportToolkit() }
                        }.font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                if !detectedReports.isEmpty {
                    HStack {
                        Label("Diagnostics USB detected", systemImage: "externaldrive.badge.checkmark")
                        Spacer()
                        Button("Import saved reports") { importDetectedReports() }
                    }.padding(12).background(Brand.accent.opacity(0.08), in: .rect(cornerRadius: 10))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Saved reports").font(.title3.weight(.semibold))
                        Text("Load the Reports folder from your USB. Every run is kept separately.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Load reports…") { loadReports() }
                    Button("Export CSV…") { exportCSV() }.disabled(reports.isEmpty)
                }
                if reports.isEmpty {
                    ContentUnavailableView("No reports loaded", systemImage: "doc.text.magnifyingglass", description: Text("Run the toolkit on a PC, then load its Reports folder here."))
                } else {
                    ForEach(reports) { report in
                        Button { selected = report } label: {
                            HStack(alignment: .top) {
                                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(Brand.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text((report.assetID.isEmpty ? report.serial : report.assetID) + " · " + report.model).font(.headline)
                                    Text(report.cpu).font(.caption)
                                    Text("RAM: \(report.installedMemory) · \(report.ramType) | GPU: \(report.gpu)").font(.caption)
                                    Text("Storage: \(report.storageHealth)  •  Battery health: \(report.batteryHealth)  •  \(report.cosmetics)").font(.caption).foregroundStyle(.secondary)
                                    if !report.manualFailures.isEmpty { Text("Failed checks: \(report.manualFailures)").font(.caption).foregroundStyle(.red) }
                                    Text(report.collectedAt).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                if isBusy { ProgressView() }
                if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
                Text("Unknown and not tested never mean pass. Organization enrollment, firmware passwords and Windows eligibility require separate checks.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .disabled(isBusy)
        .task { await refreshUSBs() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            if !isBusy { Task { await refreshUSBs() } }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            if !isBusy { Task { await refreshUSBs() } }
        }
        .sheet(item: $selected) { report in
            VStack(alignment: .leading, spacing: 16) {
                Text(report.model).font(.title2.bold())
                ScrollView {
                    Text("Asset: \(report.assetID)\nSerial: \(report.serial)\nCPU: \(report.cpu)\nUsable RAM (bytes): \(report.memoryBytes)\n\n\(report.hardwareDetails)\n\nStorage health: \(report.storageHealth)\nBattery health (%): \(report.batteryHealth)\nCosmetics: \(report.cosmetics)\nCPU test: \(report.cpuTest)\nMemory test: \(report.memoryTest)\nFailed manual checks: \(report.manualFailures.isEmpty ? "None recorded; untested checks may remain" : report.manualFailures)\n\nNotes: \(report.notes)")
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Show report files") { NSWorkspace.shared.activateFileViewerSelecting([report.url]) }
                    Spacer()
                    Button("Done") { selected = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 600, height: 470)
        }
    }

    private func chooseImage(usb: Bool) {
        let panel = NSOpenPanel()
        panel.title = usb ? "Choose Macus Diagnostics USB image" : "Choose Macus Diagnostics ISO"
        panel.allowedContentTypes = [UTType(filenameExtension: usb ? "img" : "iso") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            _ = try DiagnosticsAsset.checksum(for: source)
            if usb { usbImagePath = source.path } else { isoImagePath = source.path }
            message = "Image selected. Its checksum will be verified before use."
        } catch { message = "Extract the separate diagnostics download and keep the image and its .sha256 file together. " + error.localizedDescription }
    }

    private func refreshUSBs() async {
        do {
            drives = try await DiskService().listRemovableDrives().filter(\.isSafeTarget)
            if !drives.contains(where: { $0.id == selectedDrive }) { selectedDrive = "" }
            usbRoots = try await DiagnosticsImage.ventoyRoots()
            if !usbRoots.contains(where: { $0.path == selectedUSB }) {
                selectedUSB = usbRoots.count == 1 ? usbRoots[0].path : ""
            }
            detectedReports = try await DiagnosticsImage.usbRoots().filter { DiagnosticsImage.isPrepared($0) }
                .map { $0.appendingPathComponent(DiagnosticsImage.reportsName) }
        } catch { message = error.localizedDescription }
    }

    private func createUSB() {
        guard !usbImagePath.isEmpty, let drive = drives.first(where: { $0.id == selectedDrive }) else { return }
        let source = URL(fileURLWithPath: usbImagePath)
        let image: DiagnosticsUSB
        do { image = DiagnosticsUSB(image: source, sha256: try DiagnosticsAsset.checksum(for: source)) }
        catch { message = "Select the diagnostics .img and keep its matching .sha256 file beside it. " + error.localizedDescription; return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Erase \(drive.title) and create Diagnostics USB?"
        alert.informativeText = "\(drive.subtitle)\n\nAll files on this USB will be deleted. Macus will install diagnostics and a 512 MB reports area."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Erase & Create")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        isBusy = true
        message = "Creating and verifying Diagnostics USB. Keep it connected until Macus finishes…"
        Task {
            do {
                try await image.create(on: drive)
                message = "Ready — verified and safely ejected. Plug the USB into the PC and select it in the boot menu. Diagnostics starts automatically."
                selectedDrive = ""
                await refreshUSBs()
            } catch { message = error.localizedDescription }
            isBusy = false
        }
    }

    private func installImage() {
        guard !isoImagePath.isEmpty, !selectedUSB.isEmpty else { return }
        let source = URL(fileURLWithPath: isoImagePath)
        let image: DiagnosticsImage
        do { image = DiagnosticsImage(image: source, sha256: try DiagnosticsAsset.checksum(for: source)) }
        catch { message = "Select the diagnostics .iso and keep its matching .sha256 file beside it. " + error.localizedDescription; return }
        let root = URL(fileURLWithPath: selectedUSB)
        isBusy = true
        message = "Copying and verifying the diagnostics image. Keep the USB connected…"
        Task {
            do {
                _ = try await image.install(on: root)
                message = "Ready. Eject the USB, boot it on the PC, and choose Macus Diagnostics in Ventoy."
                await refreshUSBs()
            } catch { message = error.localizedDescription }
            isBusy = false
        }
    }

    private func importDetectedReports() {
        let folders = detectedReports
        isBusy = true
        Task {
            do {
                let results = try await Task.detached { try folders.map { try InventoryReport.load(from: $0) } }.value
                reports = results.flatMap(\.reports).sorted { $0.collectedAt > $1.collectedAt }
                message = "Loaded \(reports.count) reports. \(results.reduce(0) { $0 + $1.skipped }) unreadable reports skipped."
            } catch { message = error.localizedDescription }
            isBusy = false
        }
    }

    private func folderPanel(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportToolkit() {
        guard let folder = folderPanel(title: "Choose the Ventoy data partition or a staging folder") else { return }
        do {
            let output = try InventoryToolkit.export(to: folder)
            message = "Toolkit exported. Open README.txt for the live-session steps."
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { message = error.localizedDescription }
    }

    private func loadReports() {
        guard let folder = folderPanel(title: "Choose the toolkit’s Reports folder") else { return }
        isBusy = true
        Task {
            do {
                let result = try await Task.detached { try InventoryReport.load(from: folder) }.value
                reports = result.reports
                message = "Loaded \(reports.count) reports. \(result.skipped) unreadable or unsupported reports skipped."
            } catch { message = error.localizedDescription }
            isBusy = false
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Macus-Inventory.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try InventoryReport.csv(reports).write(to: url, atomically: true, encoding: .utf8)
            message = "Exported \(reports.count) reports to \(url.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }
}
