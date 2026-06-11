import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var config = ConfigStore()
    @StateObject private var permissions = PermissionService()
    @StateObject private var windows = WindowProvider()
    @StateObject private var bot = BotProcessController()

    @State private var selectedWindowID: UInt32?
    @State private var targetWindowX = 0
    @State private var targetWindowY = 33
    @State private var targetWindowWidth = 1280
    @State private var targetWindowHeight = 804
    @State private var windowResizeMessage = ""
    @State private var isAdvancedExpanded = false
    @State private var localEmergencyStopMonitor: Any?
    @State private var globalEmergencyStopMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                status: bot.status,
                isRunning: bot.isRunning,
                onStart: start,
                onPause: bot.pause,
                onStop: bot.stop
            )
            Divider()
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionPanel(permissions: permissions)
                        WindowPanel(
                            windows: windows.windows,
                            selectedWindowID: $selectedWindowID,
                            windowMatch: $config.selectedWindowMatch,
                            targetX: $targetWindowX,
                            targetY: $targetWindowY,
                            targetWidth: $targetWindowWidth,
                            targetHeight: $targetWindowHeight,
                            resizeMessage: windowResizeMessage,
                            refresh: refreshWindows,
                            applyFixedSize: applyFixedWindowSize
                        )
                        FishingPlanPanel(tuning: $config.tuning)
                        AdvancedSettingsPanel(
                            isExpanded: $isAdvancedExpanded,
                            tuning: $config.tuning,
                            detection: bot.detection,
                            status: bot.status,
                            runProbe: runProbe
                        )
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)

                VStack(spacing: 12) {
                    RunOverviewPanel(
                        detection: bot.detection,
                        status: bot.status,
                        isRunning: bot.isRunning
                    )
                    LogPanel(logs: bot.logs)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            config.loadDefaults()
            permissions.refresh()
            refreshWindows()
            installEmergencyStopMonitors()
        }
        .onDisappear {
            bot.emergencyStop(reason: "控制視窗關閉")
            removeEmergencyStopMonitors()
        }
    }

    private func refreshWindows() {
        windows.refresh()
        if selectedWindowID == nil {
            if let nte = windows.windows.first(where: { $0.label.localizedCaseInsensitiveContains("異環") || $0.label.localizedCaseInsensitiveContains("NTE") }) {
                selectedWindowID = nte.id
                config.selectedWindowMatch = nte.matchText
            }
        }
    }

    private func start() {
        do {
            let url = try config.saveRuntimeConfig()
            bot.start(
                configURL: url,
                dryRun: config.tuning.dryRun,
                maxFishCount: config.tuning.infiniteLoop ? 0 : max(1, config.tuning.maxFishCount)
            )
        } catch {
            bot.lastError = error.localizedDescription
        }
    }

    private func runProbe() {
        do {
            let url = try config.saveRuntimeConfig()
            bot.runProbe(configURL: url) { _ in }
        } catch {
            bot.lastError = error.localizedDescription
        }
    }

    private func installEmergencyStopMonitors() {
        guard localEmergencyStopMonitor == nil, globalEmergencyStopMonitor == nil else { return }
        localEmergencyStopMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isEmergencyStopEvent(event) {
                bot.emergencyStop(reason: "緊急停止快捷鍵")
                return nil
            }
            return event
        }
        globalEmergencyStopMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard isEmergencyStopEvent(event) else { return }
            DispatchQueue.main.async {
                bot.emergencyStop(reason: "緊急停止快捷鍵")
            }
        }
    }

    private func removeEmergencyStopMonitors() {
        if let localEmergencyStopMonitor {
            NSEvent.removeMonitor(localEmergencyStopMonitor)
            self.localEmergencyStopMonitor = nil
        }
        if let globalEmergencyStopMonitor {
            NSEvent.removeMonitor(globalEmergencyStopMonitor)
            self.globalEmergencyStopMonitor = nil
        }
    }

    private func isEmergencyStopEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && flags.contains(.option)
            && (event.keyCode == 47 || event.charactersIgnoringModifiers == ".")
    }

    private func applyFixedWindowSize() {
        guard let selectedWindowID,
              let window = windows.windows.first(where: { $0.id == selectedWindowID }) else {
            windowResizeMessage = "請先選擇遊戲視窗"
            return
        }

        let target = CGRect(
            x: targetWindowX,
            y: targetWindowY,
            width: max(320, targetWindowWidth),
            height: max(240, targetWindowHeight)
        )

        do {
            try windows.resize(window, to: target)
            windowResizeMessage = "已套用 \(Int(target.minX)),\(Int(target.minY)) \(Int(target.width))x\(Int(target.height))"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                refreshWindows()
            }
        } catch {
            windowResizeMessage = error.localizedDescription
        }
    }
}

private struct HeaderView: View {
    let status: BotRunStatus
    let isRunning: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("異環釣魚助手")
                    .font(.title3.weight(.semibold))
                StatusBadge(status: status)
            }
            Spacer()
            Button(action: onStart) {
                Label("開始", systemImage: "play.fill")
            }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            Button(action: onPause) {
                Label("暫停", systemImage: "pause.fill")
            }
                .disabled(!isRunning)
            Button(action: onStop) {
                Label("停止", systemImage: "stop.fill")
            }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!isRunning && status == .stopped)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StatusBadge: View {
    let status: BotRunStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(status.rawValue)
                .font(.headline)
        }
    }

    private var color: Color {
        switch status {
        case .stopped:
            return .secondary
        case .waitingFishing, .waitingHook:
            return .orange
        case .pulling:
            return .green
        case .result:
            return .blue
        case .paused:
            return .red
        }
    }
}
