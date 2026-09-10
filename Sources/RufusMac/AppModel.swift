import Foundation
import Observation
import RufusMacKit

/// Central observable state for the app: the selected mode, drives, image,
/// configuration, and the burn lifecycle (prepare → confirm → execute).
@MainActor
@Observable
final class AppModel {
    var mode: BurnMode = .single
    var drives: [USBDrive] = []
    var selectedDriveID: String?
    var image: BootImage?
    var config = WriteConfig()

    var isRefreshing = false
    var isInspecting = false
    var isRunning = false
    var runningStage = "Preparing"
    var runningDetail = ""
    var runStartedAt = Date()
    private var outputFragment = ""


    var showConfirm = false
    var acknowledgedErase = false

    var pendingPlan: BurnPlan?
    var log: [String] = []
    var resultMessage: String?
    var resultIsError = false

    private let diskService = DiskService()
    private let inspector = ImageInspector()
    private let runner = PrivilegedRunner(dryRun: false)

    // MARK: Derived state

    var selectedDrive: USBDrive? { drives.first { $0.id == selectedDriveID } }
    var requiresImage: Bool { mode == .single || mode == .dd }
    var isWindowsSingle: Bool { mode == .single && image?.kind == .windows }
    var showsFormatOptions: Bool { mode == .reclaim || isWindowsSingle }

    var canStart: Bool {
        guard !isRunning, !isInspecting, mode != .multiboot, selectedDrive != nil else { return false }
        if isWindowsSingle && config.windowsSetup.validationError != nil { return false }
        if requiresImage && image == nil { return false }
        return true
    }

    var startTitle: String {
        switch mode {
        case .single, .dd: return "START"
        case .multiboot: return "BUILD MULTIBOOT"
        case .reclaim: return "RECLAIM DRIVE"
        }
    }

    // MARK: Actions

    func refreshDrives() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            drives = try await diskService.listRemovableDrives()
            if selectedDriveID == nil || !drives.contains(where: { $0.id == selectedDriveID }) {
                selectedDriveID = drives.first?.id
            }
        } catch {
            resultIsError = true
            resultMessage = "Couldn't list drives: \(error.localizedDescription)"
        }
    }

    func selectImage(_ url: URL) async {
        guard !isRunning, !isInspecting, !showConfirm else { return }
        guard ["iso", "img", "dmg"].contains(url.pathExtension.lowercased()) else {
            resultIsError = true
            resultMessage = "Select an ISO, IMG, or DMG disk image."
            return
        }
        isInspecting = true
        defer { isInspecting = false }
        let inspected = await inspector.inspect(url)
        image = inspected
        config = WriteConfig.recommended(for: inspected)
        if inspected.kind == .windows && mode == .dd { mode = .single }
    }

    func clearImage() { image = nil }

    /// Planner wired to bundled tools (Resources/thirdparty) when present,
    /// falling back to Homebrew locations during development.
    private var planner: BurnPlanner {
        let thirdParty = Bundle.main.resourceURL?.appendingPathComponent("thirdparty").path
        return BurnPlanner(tools: .resolve(thirdPartyDir: thirdParty))
    }

    func prepare() {
        guard let drive = selectedDrive else { return }
        pendingPlan = planner.makePlan(mode: mode, image: image, drive: drive, config: config)
        acknowledgedErase = false
        showConfirm = true
    }

    func execute(dryRun: Bool) async {
        guard let plan = pendingPlan else { return }
        showConfirm = false
        isRunning = true
        runningStage = "Preparing"
        runningDetail = ""
        outputFragment = ""
        runStartedAt = Date()
        defer { isRunning = false }

        log = ["# \(plan.summary)"]
        await runner.setDryRun(dryRun)
        do {
            let output = try await runner.run(
                script: plan.script,
                prompt: "\(Brand.name) needs administrator access to \(plan.mode.rawValue.lowercased()) on \(plan.summary)",
                requiresAdministrator: plan.mode != .single,
                onOutput: { [weak self] text in
                    Task { @MainActor in self?.receiveOutput(text) }
                }
            )
            log.append(output)
            resultIsError = false
            resultMessage = dryRun
                ? "Dry run complete — nothing was written."
                : "\(plan.mode.rawValue) completed successfully."
            if !dryRun { await refreshDrives() }
        } catch {
            resultIsError = true
            resultMessage = "Failed: \(error.localizedDescription)"
            log.append("ERROR: \(error.localizedDescription)")
        }
    }

    private func receiveOutput(_ text: String) {
        outputFragment += text.replacingOccurrences(of: "\r", with: "\n")
        let lines = outputFragment.components(separatedBy: "\n")
        outputFragment = String((lines.last ?? "").suffix(4096))
        for line in lines.dropLast() where !line.isEmpty {
            if line.hasPrefix("RM_STAGE|") {
                runningStage = String(line.dropFirst(9))
                runningDetail = ""
            } else if line.hasPrefix("==>") {
                runningStage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                runningDetail = ""
            } else {
                runningDetail = String(line.prefix(220))
            }
        }
    }

    func dismissResult() { resultMessage = nil }
}
