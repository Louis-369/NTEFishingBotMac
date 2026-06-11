import Foundation
import Combine

final class ConfigStore: ObservableObject {
    @Published var selectedWindowMatch = "異環"
    @Published var tuning = BotTuning()

    private let fileManager = FileManager.default

    var supportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MacFishingBotControl", isDirectory: true)
    }

    var runtimeConfigURL: URL {
        supportDirectory.appendingPathComponent("runtime-fish-config.json")
    }

    func loadDefaults() {
        guard let url = Bundle.main.url(forResource: "sample-fish-config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        selectedWindowMatch = root["windowMatch"] as? String ?? selectedWindowMatch
        tuning.dryRun = root["dryRun"] as? Bool ?? tuning.dryRun
        if let inputMode = root["inputMode"] as? String {
            tuning.backgroundInput = ["pid", "targetpid", "background"].contains(inputMode.lowercased())
        }
        if let fish = root["fish"] as? [String: Any] {
            tuning.deadzonePx = number(fish["deadzonePx"]) ?? tuning.deadzonePx
            tuning.loopIntervalMs = Int(number(fish["loopIntervalMs"]) ?? Double(tuning.loopIntervalMs))
            if let controlMode = fish["controlMode"] as? String,
               let mode = ControlMode(rawValue: controlMode) {
                tuning.controlMode = mode
            }
        }
    }

    func saveRuntimeConfig() throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "sample-fish-config", withExtension: "json") else {
            throw ConfigError.missingDefaultConfig
        }

        let data = try Data(contentsOf: templateURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidConfig
        }

        root["windowMatch"] = selectedWindowMatch
        root["dryRun"] = tuning.dryRun
        root["inputMode"] = tuning.backgroundInput ? "pid" : "global"
        root["pauseWhenTargetNotFrontmost"] = !tuning.backgroundInput
        root["targetFocusGraceMs"] = 800

        var fish = root["fish"] as? [String: Any] ?? [:]
        fish["deadzonePx"] = tuning.deadzonePx
        fish["loopIntervalMs"] = tuning.loopIntervalMs
        fish["controlMode"] = tuning.controlMode.rawValue
        root["fish"] = fish

        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: runtimeConfigURL, options: .atomic)
        return runtimeConfigURL
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}

enum ConfigError: LocalizedError {
    case missingDefaultConfig
    case invalidConfig

    var errorDescription: String? {
        switch self {
        case .missingDefaultConfig:
            return "找不到內建 sample-fish-config.json"
        case .invalidConfig:
            return "設定檔格式無法解析"
        }
    }
}
