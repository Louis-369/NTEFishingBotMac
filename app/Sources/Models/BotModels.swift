import Foundation
import CoreGraphics

enum BotRunStatus: String {
    case stopped = "停止"
    case waitingFishing = "等待釣魚"
    case waitingHook = "等上鉤"
    case pulling = "拉條中"
    case result = "結算"
    case paused = "暫停"
}

enum ControlMode: String, CaseIterable, Identifiable {
    case holdSwitch = "holdSwitch"
    case pulse = "pulse"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .holdSwitch:
            return "穩定按住"
        case .pulse:
            return "脈衝點按"
        }
    }
}

struct BotTuning {
    var deadzonePx: Double = 15
    var loopIntervalMs: Int = 16
    var controlMode: ControlMode = .holdSwitch
    var dryRun: Bool = false
    var backgroundInput: Bool = false
    var maxFishCount: Int = 0
    var infiniteLoop: Bool = true
}

struct DetectionSnapshot {
    var greenFound = false
    var cursorFound = false
    var offset: Double?
    var action = "-"
    var caughtCount = 0
}

struct WindowCandidate: Identifiable, Hashable {
    let id: UInt32
    let ownerPID: Int32
    let ownerName: String
    let title: String
    let frame: CGRect

    var label: String {
        let cleanTitle = title.isEmpty ? "(untitled)" : title
        return "\(ownerName) - \(cleanTitle)"
    }

    var matchText: String {
        if !title.isEmpty { return title }
        return ownerName
    }

    var frameText: String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }
}
