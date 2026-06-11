import SwiftUI

struct PermissionPanel: View {
    @ObservedObject var permissions: PermissionService

    private var allGranted: Bool {
        permissions.screenRecordingGranted && permissions.accessibilityGranted
    }

    var body: some View {
        GroupBox("權限") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(allGranted ? "可正式執行" : "等待授權", systemImage: allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(allGranted ? .green : .orange)
                    Spacer()
                    Button("重新檢查") {
                        permissions.refresh()
                    }
                    .controlSize(.small)
                }
                PermissionRow(title: "螢幕錄製", granted: permissions.screenRecordingGranted) {
                    permissions.requestScreenRecording()
                }
                PermissionRow(title: "輔助使用", granted: permissions.accessibilityGranted) {
                    permissions.requestAccessibility()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(granted ? "已允許" : "未允許")
                .foregroundStyle(.secondary)
            Button("開啟", action: request)
                .controlSize(.small)
        }
    }
}

struct WindowPanel: View {
    let windows: [WindowCandidate]
    @Binding var selectedWindowID: UInt32?
    @Binding var windowMatch: String
    @Binding var targetX: Int
    @Binding var targetY: Int
    @Binding var targetWidth: Int
    @Binding var targetHeight: Int
    let resizeMessage: String
    let refresh: () -> Void
    let applyFixedSize: () -> Void

    @State private var showManualControls = false

    var selectedWindow: WindowCandidate? {
        windows.first(where: { $0.id == selectedWindowID })
    }

    var body: some View {
        GroupBox("遊戲視窗") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("目前視窗", selection: $selectedWindowID) {
                    Text("未選擇").tag(Optional<UInt32>.none)
                    ForEach(windows) { window in
                        Text(window.label).tag(Optional(window.id))
                    }
                }
                .onChange(of: selectedWindowID) { _, _ in
                    if let selectedWindow {
                        windowMatch = selectedWindow.matchText
                    }
                }

                HStack {
                    Button("刷新", action: refresh)
                    Button("套用平衡尺寸", action: applyFixedSize)
                        .disabled(selectedWindowID == nil)
                    Spacer()
                }

                if let selectedWindow {
                    Label(selectedWindow.frameText, systemImage: "rectangle.inset.filled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !resizeMessage.isEmpty {
                    Text(resizeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup("手動視窗設定", isExpanded: $showManualControls) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("視窗關鍵字", text: $windowMatch)
                            .textFieldStyle(.roundedBorder)

                        Button("平衡 1280x804") {
                            targetX = 0
                            targetY = 33
                            targetWidth = 1280
                            targetHeight = 804
                        }
                        .controlSize(.small)
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                            GridRow {
                                Stepper("x \(targetX)", value: $targetX, in: -5000...5000, step: 1)
                                Stepper("y \(targetY)", value: $targetY, in: -5000...5000, step: 1)
                            }
                            GridRow {
                                Stepper("w \(targetWidth)", value: $targetWidth, in: 320...4096, step: 1)
                                Stepper("h \(targetHeight)", value: $targetHeight, in: 240...2400, step: 1)
                            }
                        }
                        HStack {
                            Button("套用", action: applyFixedSize)
                                .disabled(selectedWindowID == nil)
                            Spacer()
                            Button("使用目前尺寸") {
                                if let selectedWindow {
                                    targetX = Int(selectedWindow.frame.minX)
                                    targetY = Int(selectedWindow.frame.minY)
                                    targetWidth = Int(selectedWindow.frame.width)
                                    targetHeight = Int(selectedWindow.frame.height)
                                }
                            }
                            .disabled(selectedWindowID == nil)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}

struct FishingPlanPanel: View {
    @Binding var tuning: BotTuning

    var body: some View {
        GroupBox("釣魚目標") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("持續釣魚", isOn: $tuning.infiniteLoop)

                Stepper(value: $tuning.maxFishCount, in: 1...999, step: 1) {
                    HStack {
                        Text("完成後暫停")
                        Spacer()
                        Text(tuning.infiniteLoop ? "不限" : "\(max(1, tuning.maxFishCount)) 隻")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(tuning.infiniteLoop)

                HStack {
                    Text("執行模式")
                    Spacer()
                    Text(tuning.dryRun ? "模擬執行" : "正式執行")
                        .foregroundStyle(tuning.dryRun ? .orange : .green)
                }
                .font(.callout)
            }
            .onChange(of: tuning.infiniteLoop) { _, infinite in
                if !infinite && tuning.maxFishCount < 1 {
                    tuning.maxFishCount = 1
                }
            }
        }
    }
}

struct AdvancedSettingsPanel: View {
    @Binding var isExpanded: Bool
    @Binding var tuning: BotTuning
    let detection: DetectionSnapshot
    let status: BotRunStatus
    let runProbe: () -> Void

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ParameterPanel(tuning: $tuning)
                    DetectionPanel(
                        detection: detection,
                        status: status,
                        runProbe: runProbe
                    )
                }
                .padding(.top, 8)
            } label: {
                Label("進階設定", systemImage: "slider.horizontal.3")
            }
        }
    }
}

struct ParameterPanel: View {
    @Binding var tuning: BotTuning

    var body: some View {
        GroupBox("技術參數") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("死區(px)")
                    Slider(value: $tuning.deadzonePx, in: 4...60, step: 1)
                    Text("\(Int(tuning.deadzonePx))")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }

                Stepper(value: $tuning.loopIntervalMs, in: 8...120, step: 1) {
                    HStack {
                        Text("循環間隔(ms)")
                        Spacer()
                        Text("\(tuning.loopIntervalMs)")
                            .monospacedDigit()
                    }
                }

                Picker("控制模式", selection: $tuning.controlMode) {
                    ForEach(ControlMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("實驗性後台輸入", isOn: $tuning.backgroundInput)

                Toggle("模擬執行", isOn: $tuning.dryRun)
            }
        }
    }
}

struct RunOverviewPanel: View {
    let detection: DetectionSnapshot
    let status: BotRunStatus
    let isRunning: Bool

    var body: some View {
        GroupBox("運行狀態") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    StatusSummary(status: status)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(detection.caughtCount)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("已釣上")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        SignalValue(label: "綠條", active: detection.greenFound)
                        SignalValue(label: "游標", active: detection.cursorFound)
                    }
                    GridRow {
                        LabelValue(label: "目前按鍵", value: actionText)
                        LabelValue(label: "執行", value: isRunning ? "進行中" : "未開始")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionText: String {
        detection.action == "-" ? "無" : detection.action.uppercased()
    }
}

private struct StatusSummary: View {
    let status: BotRunStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.rawValue)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        switch status {
        case .stopped:
            return "尚未啟動"
        case .waitingFishing:
            return "等待開始釣魚"
        case .waitingHook:
            return "等待魚上鉤"
        case .pulling:
            return "正在控制跑條"
        case .result:
            return "正在關閉結算畫面"
        case .paused:
            return "已停止操作"
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

private struct SignalValue: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(active ? .green : .secondary)
            Text(label)
            Text(active ? "已抓到" : "未抓到")
                .foregroundStyle(.secondary)
        }
    }
}

struct DetectionPanel: View {
    let detection: DetectionSnapshot
    let status: BotRunStatus
    let runProbe: () -> Void

    var body: some View {
        GroupBox("偵測細節") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    LabelValue(label: "狀態", value: status.rawValue)
                    LabelValue(label: "目前按鍵", value: detection.action)
                }
                GridRow {
                    LabelValue(label: "綠條", value: detection.greenFound ? "抓到" : "未抓到")
                    LabelValue(label: "游標", value: detection.cursorFound ? "抓到" : "未抓到")
                }
                GridRow {
                    LabelValue(label: "偏移", value: detection.offset.map { String(format: "%.1f", $0) } ?? "-")
                    LabelValue(label: "已結算", value: "\(detection.caughtCount)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("探測一次", action: runProbe)
            }
            .padding(.top, 8)
        }
    }
}

private struct LabelValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct LogPanel: View {
    let logs: String

    var body: some View {
        GroupBox("運行紀錄") {
            ScrollView {
                Text(logs.isEmpty ? "尚未開始。" : localizedLogs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var localizedLogs: String {
        logs
            .replacingOccurrences(of: "Fish mode: dry-run", with: "模式：模擬執行")
            .replacingOccurrences(of: "Fish mode: live", with: "模式：正式執行")
            .replacingOccurrences(of: "Input mode: pid-targeted experimental", with: "輸入模式：PID 後台實驗")
            .replacingOccurrences(of: "Input mode: global frontmost", with: "輸入模式：前台穩定")
            .replacingOccurrences(of: "Press Ctrl-C to stop.", with: "按 Ctrl-C 停止。")
            .replacingOccurrences(of: "prompt visible; pressing f", with: "偵測到釣魚提示，按 F")
            .replacingOccurrences(of: "hook prompt visible", with: "偵測到上鉤提示")
            .replacingOccurrences(of: "start prompt visible", with: "偵測到開始釣魚提示")
            .replacingOccurrences(of: "waiting for blue hook prompt; ignoring", with: "等待藍圈上鉤提示，忽略")
            .replacingOccurrences(of: "target window is not frontmost; waiting", with: "遊戲不是前台，暫停輸入並等待")
            .replacingOccurrences(of: "target window still not frontmost; waiting", with: "遊戲仍不是前台，持續等待")
            .replacingOccurrences(of: "target window frontmost again; resuming", with: "遊戲回到前台，繼續執行")
            .replacingOccurrences(of: "kind=blue", with: "類型=藍圈")
            .replacingOccurrences(of: "kind=ready", with: "類型=就緒")
            .replacingOccurrences(of: "kind=result", with: "類型=結算")
            .replacingOccurrences(of: "pressing f", with: "按 F")
            .replacingOccurrences(of: "attempt", with: "第")
            .replacingOccurrences(of: "result prompt visible; closing with mouseClickResultPrompt", with: "偵測到結算畫面，點擊文字關閉")
            .replacingOccurrences(of: "result prompt visible; closing with mouseClickBlank", with: "偵測到結算畫面，點擊空白處關閉")
            .replacingOccurrences(of: "result prompt visible; closing", with: "偵測到結算畫面，關閉")
            .replacingOccurrences(of: "result close retry", with: "結算關閉重試")
            .replacingOccurrences(of: "result close stuck", with: "結算畫面仍未關閉")
            .replacingOccurrences(of: "prompt stuck", with: "提示未進入下一步")
            .replacingOccurrences(of: "no actionable fishing state", with: "沒有可操作的釣魚狀態")
            .replacingOccurrences(of: "paused: unable to continue fishing after retries", with: "已暫停：重試後仍無法繼續釣魚")
            .replacingOccurrences(of: "bar centered", with: "跑條置中")
            .replacingOccurrences(of: "bar offset=", with: "跑條偏移=")
            .replacingOccurrences(of: " control=", with: " 預測=")
            .replacingOccurrences(of: "dry-run", with: "模擬")
            .replacingOccurrences(of: "keyTap", with: "按鍵")
            .replacingOccurrences(of: "keyDown", with: "按下")
            .replacingOccurrences(of: "keyUp", with: "放開")
            .replacingOccurrences(of: "mouseClickResultPrompt", with: "點擊結算文字")
            .replacingOccurrences(of: "mouseClickBlank", with: "點擊空白處")
            .replacingOccurrences(of: "hold=", with: "按住=")
            .replacingOccurrences(of: "pulse=", with: "點按=")
    }
}
