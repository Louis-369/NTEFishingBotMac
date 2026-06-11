import Foundation
@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import ImageIO
import UniformTypeIdentifiers

var interruptRequested: sig_atomic_t = 0

func requestMacFishingBotInterrupt() {
    interruptRequested = 1
}

struct BotError: Error, CustomStringConvertible {
    let description: String
}

func throwError(_ message: String) throws -> Never {
    throw BotError(description: message)
}

struct WindowInfo {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var label: String {
        let windowTitle = title.isEmpty ? "(untitled)" : title
        return "\(ownerName) - \(windowTitle)"
    }
}

struct RectConfig: Decodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct RatioRectConfig: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ActionConfig: Decodable {
    let type: String
    let key: String?
    let button: String?
    let durationMs: Int?
    let xOffset: Double?
    let yOffset: Double?
}

struct IdleActionConfig: Decodable {
    let afterMs: Int
    let action: ActionConfig
}

struct TemplateConfig: Decodable {
    let name: String
    let path: String
    let threshold: Double?
    let cooldownMs: Int?
    let region: RectConfig?
    let regionRatio: RatioRectConfig?
    let actions: [ActionConfig]
}

struct FishTemplateConfig: Decodable {
    let name: String
    let path: String
    let threshold: Double?
    let region: RectConfig?
    let regionRatio: RatioRectConfig?
    let actions: [ActionConfig]?
}

struct ColorRuleConfig: Decodable {
    let mode: String?
    let lower: [Int]?
    let upper: [Int]?
    let hue: [Double]?
    let saturation: [Double]?
    let brightness: [Double]?
}

struct FishConfig: Decodable {
    let loopIntervalMs: Int?
    let liveStartDelayMs: Int?
    let retryLimit: Int?
    let stallTimeoutMs: Int?
    let assistKey: String?
    let assistKeyIntervalMs: Int?
    let assistKeyMaxAttempts: Int?
    let controlMode: String?
    let barAssistEveryFrames: Int?
    let barAssistDurationMs: Int?
    let barAssistCooldownMs: Int?
    let barMissToleranceFrames: Int?
    let start: FishTemplateConfig?
    let hook: FishTemplateConfig?
    let result: FishTemplateConfig?
    let pause: [FishTemplateConfig]?
    let barRegion: RectConfig?
    let barRegionRatio: RatioRectConfig?
    let promptRegion: RectConfig?
    let promptRegionRatio: RatioRectConfig?
    let greenColor: ColorRuleConfig?
    let cursorColor: ColorRuleConfig?
    let promptActiveColor: ColorRuleConfig?
    let resultPromptColor: ColorRuleConfig?
    let colorStride: Int?
    let minGreenPixels: Int?
    let minCursorPixels: Int?
    let minPromptPixels: Int?
    let minResultPromptPixels: Int?
    let deadzonePx: Double?
    let releaseDeadzoneFactor: Double?
    let adaptiveDeadzoneFactor: Double?
    let predictionLeadMs: Int?
    let predictionMaxPxAt1280: Double?
    let invertControls: Bool?
    let promptKey: String?
    let promptCooldownMs: Int?
    let promptRepeatMs: Int?
    let startPromptRepeatMs: Int?
    let hookPromptRepeatMs: Int?
    let promptStableFrames: Int?
    let promptMaxAttempts: Int?
    let assistRequiresPrompt: Bool?
    let fallbackAssistWhenPromptMissing: Bool?
    let barAssistRequiresPrompt: Bool?
    let resultPromptRegion: RectConfig?
    let resultPromptRegionRatio: RatioRectConfig?
    let resultPromptKey: String?
    let resultPromptFallbackKey: String?
    let resultPromptCooldownMs: Int?
    let resultPromptMaxAttempts: Int?
    let resultPromptStuckTimeoutMs: Int?
    let resultPromptClickXRatio: Double?
    let resultPromptClickYRatio: Double?
    let pxPerSecondAt1280: Double?
    let factor: Double?
    let floorMs: Int?
    let capMs: Int?
}

struct BotConfig: Decodable {
    let windowMatch: String
    let activateWindow: Bool?
    let inputMode: String?
    let pauseWhenTargetNotFrontmost: Bool?
    let targetFocusGraceMs: Int?
    let loopIntervalMs: Int?
    let defaultThreshold: Double?
    let matchStride: Int?
    let pixelStride: Int?
    let dryRun: Bool?
    let templates: [TemplateConfig]?
    let idleAction: IdleActionConfig?
    let fish: FishConfig?
}

struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

struct RGBImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func rgbAt(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let index = (y * width + x) * 3
        return (pixels[index], pixels[index + 1], pixels[index + 2])
    }
}

struct TemplateRuntime {
    let config: TemplateConfig
    let image: GrayImage
}

struct FishTemplateRuntime {
    let config: FishTemplateConfig
    let image: GrayImage
}

struct FishTemplateSet {
    let start: FishTemplateRuntime?
    let hook: FishTemplateRuntime?
    let result: FishTemplateRuntime?
    let pause: [FishTemplateRuntime]

    var all: [FishTemplateRuntime] {
        [start, hook, result].compactMap { $0 } + pause
    }
}

struct MatchResult {
    let name: String
    let score: Double
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var centerX: Int { x + width / 2 }
    var centerY: Int { y + height / 2 }
}

struct ColorBlob {
    let count: Int
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var centerX: Double { Double(minX + maxX) / 2.0 }
    var centerY: Double { Double(minY + maxY) / 2.0 }
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

struct FishingBarDetection {
    let green: ColorBlob
    let cursor: ColorBlob
    let offset: Double
}

struct FishingBarControlSample {
    let bar: FishingBarDetection
    let timestamp: Date
}

enum PromptKind: String {
    case blue
    case ready
    case result
}

enum FishingRunPhase {
    case scanning
    case waitingFishing
    case waitingHook
    case pulling
    case result
}

struct PromptDetection {
    let blob: ColorBlob
    let kind: PromptKind
}

final class MacFishingBot {
    private let executableName = "mac-fishing-bot"
    private var inputTargetPID: pid_t?

    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        let rest = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "permissions":
            requestPermissions()
        case "self-test":
            try selfTest()
        case "list":
            let includeAll = rest.contains("--all")
            let filterParts = rest.filter { $0 != "--all" }
            let filter = filterParts.joined(separator: " ")
            listWindows(filter: filter.isEmpty ? nil : filter, includeAll: includeAll)
        case "list-all":
            let filter = rest.joined(separator: " ")
            listWindows(filter: filter.isEmpty ? nil : filter, includeAll: true)
        case "size":
            try size(arguments: rest)
        case "snapshot":
            try snapshot(arguments: rest)
        case "probe":
            try probe(arguments: rest)
        case "run":
            try runLoop(arguments: rest)
        case "fish-probe":
            try fishProbe(arguments: rest)
        case "fish-probe-image":
            try fishProbeImage(arguments: rest)
        case "fish-run":
            try fishRun(arguments: rest)
        default:
            try throwError("unknown command: \(command)")
        }
    }

    private func printHelp() {
        print("""
        Usage:
          \(executableName) permissions
          \(executableName) self-test
          \(executableName) list [--all] [filter]
          \(executableName) list-all [filter]
          \(executableName) size --match <window text> [--expect <width>x<height>]
          \(executableName) snapshot --match <window text> --out <path>
          \(executableName) probe <config.json>
          \(executableName) run <config.json> [--dry-run|--live]
          \(executableName) fish-probe <config.json>
          \(executableName) fish-probe-image <config.json> <image.png>
          \(executableName) fish-run <config.json> [--dry-run|--live]

        Notes:
          - Use permissions first if screenshot or input fails.
          - Use probe or fish-probe before live mode to tune detection.
        """)
    }

    private func selfTest() throws {
        let sourceWidth = 64
        let sourceHeight = 48
        let templateWidth = 8
        let templateHeight = 6
        let targetX = 31
        let targetY = 17

        var sourcePixels = [UInt8](repeating: 20, count: sourceWidth * sourceHeight)
        var templatePixels = [UInt8](repeating: 0, count: templateWidth * templateHeight)

        for y in 0..<templateHeight {
            for x in 0..<templateWidth {
                let value = UInt8(80 + ((x * 17 + y * 29) % 120))
                templatePixels[y * templateWidth + x] = value
                sourcePixels[(targetY + y) * sourceWidth + targetX + x] = value
            }
        }

        let source = GrayImage(width: sourceWidth, height: sourceHeight, pixels: sourcePixels)
        let template = GrayImage(width: templateWidth, height: templateHeight, pixels: templatePixels)
        guard let result = bestMatch(
            template: template,
            name: "synthetic",
            in: source,
            region: nil,
            matchStride: 1,
            pixelStride: 1
        ) else {
            try throwError("self-test failed: no match returned")
        }

        guard result.x == targetX, result.y == targetY, result.score >= 0.999 else {
            try throwError("self-test failed: got score=\(format(result.score)) at=\(result.x),\(result.y)")
        }

        let rgbWidth = 128
        let rgbHeight = 72
        var rgbPixels = [UInt8](repeating: 8, count: rgbWidth * rgbHeight * 3)
        func setPixel(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            let index = (y * rgbWidth + x) * 3
            rgbPixels[index] = r
            rgbPixels[index + 1] = g
            rgbPixels[index + 2] = b
        }
        for y in 8..<14 {
            for x in 36..<78 {
                setPixel(x, y, 48, 220, 180)
            }
        }
        for y in 6..<17 {
            for x in 72..<76 {
                setPixel(x, y, 255, 214, 32)
            }
        }
        let rgb = RGBImage(width: rgbWidth, height: rgbHeight, pixels: rgbPixels)
        let fish = FishConfig(
            loopIntervalMs: nil,
            liveStartDelayMs: nil,
            retryLimit: nil,
            stallTimeoutMs: nil,
            assistKey: nil,
            assistKeyIntervalMs: nil,
            assistKeyMaxAttempts: nil,
            controlMode: nil,
            barAssistEveryFrames: nil,
            barAssistDurationMs: nil,
            barAssistCooldownMs: nil,
            barMissToleranceFrames: nil,
            start: nil,
            hook: nil,
            result: nil,
            pause: nil,
            barRegion: RectConfig(x: 20, y: 0, width: 90, height: 25),
            barRegionRatio: nil,
            promptRegion: nil,
            promptRegionRatio: nil,
            greenColor: nil,
            cursorColor: nil,
            promptActiveColor: nil,
            resultPromptColor: nil,
            colorStride: 1,
            minGreenPixels: 10,
            minCursorPixels: 4,
            minPromptPixels: nil,
            minResultPromptPixels: nil,
            deadzonePx: 2,
            releaseDeadzoneFactor: nil,
            adaptiveDeadzoneFactor: nil,
            predictionLeadMs: nil,
            predictionMaxPxAt1280: nil,
            invertControls: nil,
            promptKey: nil,
            promptCooldownMs: nil,
            promptRepeatMs: nil,
            startPromptRepeatMs: nil,
            hookPromptRepeatMs: nil,
            promptStableFrames: nil,
            promptMaxAttempts: nil,
            assistRequiresPrompt: nil,
            fallbackAssistWhenPromptMissing: nil,
            barAssistRequiresPrompt: nil,
            resultPromptRegion: nil,
            resultPromptRegionRatio: nil,
            resultPromptKey: nil,
            resultPromptFallbackKey: nil,
            resultPromptCooldownMs: nil,
            resultPromptMaxAttempts: nil,
            resultPromptStuckTimeoutMs: nil,
            resultPromptClickXRatio: nil,
            resultPromptClickYRatio: nil,
            pxPerSecondAt1280: nil,
            factor: nil,
            floorMs: nil,
            capMs: nil
        )
        guard let bar = detectFishingBar(in: rgb, fish: fish), bar.offset > 10 else {
            try throwError("self-test failed: fishing color bar detection did not find expected offset")
        }

        print("self-test PASS: template score=\(format(result.score)) at=\(result.x),\(result.y); bar offset=\(format(bar.offset))")
    }

    private func requestPermissions() {
        if #available(macOS 10.15, *) {
            let hasScreenCapture = CGPreflightScreenCaptureAccess()
            print("Screen Recording permission: \(hasScreenCapture ? "granted" : "not granted")")
            if !hasScreenCapture {
                print("Requesting Screen Recording permission...")
                _ = CGRequestScreenCaptureAccess()
            }
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility permission: \(trusted ? "granted" : "not granted")")
    }

    private func listWindows(filter: String?, includeAll: Bool = false) {
        let windows = includeAll ? allWindows() : visibleWindows()
        let filtered = filterWindowList(windows, matching: filter)

        if filtered.isEmpty {
            print(includeAll ? "No matching windows." : "No matching visible windows.")
            return
        }

        for window in filtered {
            let bounds = window.bounds
            print("#\(window.id) pid=\(window.ownerPID) frame=\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height)) \(window.label)")
        }
    }

    private func size(arguments: [String]) throws {
        var matchText: String?
        var expectedSize: (width: Int, height: Int)?

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--match":
                guard index + 1 < arguments.count else { try throwError("--match needs a value") }
                matchText = arguments[index + 1]
                index += 2
            case "--expect":
                guard index + 1 < arguments.count else { try throwError("--expect needs a value like 2560x1440") }
                expectedSize = try parseSize(arguments[index + 1])
                index += 2
            default:
                try throwError("unknown size argument: \(arg)")
            }
        }

        guard let matchText else { try throwError("size requires --match <window text>") }

        let window = try findWindow(matching: matchText)
        let image = try capture(window: window)
        print("Window: \(window.label)")
        print("Frame points: \(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))")
        print("Capture pixels: \(image.width)x\(image.height)")

        if let expectedSize {
            guard expectedSize.width == image.width, expectedSize.height == image.height else {
                try throwError("capture size mismatch: expected \(expectedSize.width)x\(expectedSize.height), got \(image.width)x\(image.height)")
            }
            print("Expected size: matched")
        }
    }

    private func snapshot(arguments: [String]) throws {
        var matchText: String?
        var outputPath: String?

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--match":
                guard index + 1 < arguments.count else { try throwError("--match needs a value") }
                matchText = arguments[index + 1]
                index += 2
            case "--out":
                guard index + 1 < arguments.count else { try throwError("--out needs a value") }
                outputPath = arguments[index + 1]
                index += 2
            default:
                try throwError("unknown snapshot argument: \(arg)")
            }
        }

        guard let matchText else { try throwError("snapshot requires --match <window text>") }
        guard let outputPath else { try throwError("snapshot requires --out <path>") }

        let window = try findWindow(matching: matchText)
        let image = try capture(window: window)
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try savePNG(image, to: outputURL)
        print("Saved \(image.width)x\(image.height) screenshot for \(window.label)")
        print(outputURL.path)
    }

    private func probe(arguments: [String]) throws {
        guard let configPath = arguments.first else {
            try throwError("probe requires <config.json>")
        }

        let configURL = URL(fileURLWithPath: configPath)
        let config = try loadConfig(configURL)
        let window = try findWindow(matching: config.windowMatch)
        let image = try capture(window: window)
        let gray = try makeGrayImage(from: image)
        let templates = try loadTemplates(config: config, baseURL: configURL.deletingLastPathComponent())

        print("Window: \(window.label)")
        print("Screenshot: \(gray.width)x\(gray.height)")

        for template in templates {
            let result = bestMatch(
                template: template.image,
                name: template.config.name,
                in: gray,
                region: template.config.region,
                regionRatio: template.config.regionRatio,
                matchStride: max(1, config.matchStride ?? 3),
                pixelStride: max(1, config.pixelStride ?? 2)
            )
            let threshold = template.config.threshold ?? config.defaultThreshold ?? 0.92
            if let result {
                let pass = result.score >= threshold ? "PASS" : "fail"
                print("\(pass) \(template.config.name): score=\(format(result.score)) threshold=\(format(threshold)) at=\(result.x),\(result.y) size=\(result.width)x\(result.height)")
            } else {
                print("fail \(template.config.name): template does not fit screenshot or region")
            }
        }
    }

    private func runLoop(arguments: [String]) throws {
        guard let configPath = arguments.first else {
            try throwError("run requires <config.json>")
        }

        let forceDryRun = arguments.contains("--dry-run")
        let forceLive = arguments.contains("--live")
        if forceDryRun && forceLive {
            try throwError("choose only one of --dry-run or --live")
        }

        let configURL = URL(fileURLWithPath: configPath)
        let config = try loadConfig(configURL)
        let templates = try loadTemplates(config: config, baseURL: configURL.deletingLastPathComponent())
        let dryRun = forceLive ? false : (forceDryRun ? true : (config.dryRun ?? true))
        let matchStride = max(1, config.matchStride ?? 3)
        let pixelStride = max(1, config.pixelStride ?? 2)
        let loopInterval = Double(max(30, config.loopIntervalMs ?? 120)) / 1000.0

        var lastFireByTemplate: [String: Date] = [:]
        var lastActionAt = Date()
        var frameCount = 0

        print("Mode: \(dryRun ? "dry-run" : "live")")
        print("Press Ctrl-C to stop.")

        while true {
            let window = try findWindow(matching: config.windowMatch)
            if config.activateWindow ?? true {
                activate(window: window)
            }

            let cgImage = try capture(window: window)
            let gray = try makeGrayImage(from: cgImage)
            var acted = false
            let now = Date()

            for template in templates {
                let result = bestMatch(
                    template: template.image,
                    name: template.config.name,
                    in: gray,
                    region: template.config.region,
                    regionRatio: template.config.regionRatio,
                    matchStride: matchStride,
                    pixelStride: pixelStride
                )

                guard let result else { continue }
                let threshold = template.config.threshold ?? config.defaultThreshold ?? 0.92
                guard result.score >= threshold else { continue }

                let cooldown = Double(template.config.cooldownMs ?? 300) / 1000.0
                let lastFire = lastFireByTemplate[template.config.name] ?? .distantPast
                guard now.timeIntervalSince(lastFire) >= cooldown else { continue }

                print("[\(timestamp())] \(template.config.name) score=\(format(result.score)) at=\(result.x),\(result.y)")
                try perform(actions: template.config.actions, window: window, image: gray, match: result, dryRun: dryRun)
                lastFireByTemplate[template.config.name] = now
                lastActionAt = now
                acted = true
                break
            }

            if !acted, let idleAction = config.idleAction {
                let idleSeconds = Double(idleAction.afterMs) / 1000.0
                if Date().timeIntervalSince(lastActionAt) >= idleSeconds {
                    print("[\(timestamp())] idle action")
                    try perform(actions: [idleAction.action], window: window, image: gray, match: nil, dryRun: dryRun)
                    lastActionAt = Date()
                }
            }

            frameCount += 1
            if dryRun, frameCount % 50 == 0 {
                print("[\(timestamp())] dry-run scanning...")
            }

            Thread.sleep(forTimeInterval: loopInterval)
        }
    }

    private func fishProbe(arguments: [String]) throws {
        guard let configPath = arguments.first else {
            try throwError("fish-probe requires <config.json>")
        }

        let configURL = URL(fileURLWithPath: configPath)
        let config = try loadConfig(configURL)
        guard let fish = config.fish else {
            try throwError("fish-probe requires a 'fish' section in config")
        }

        let window = try findWindow(matching: config.windowMatch)
        let cgImage = try capture(window: window)
        let gray = try makeGrayImage(from: cgImage)
        let rgb = try makeRGBImage(from: cgImage)

        print("Window: \(window.label)")
        print("Screenshot: \(gray.width)x\(gray.height)")
        try printFishProbeDetails(gray: gray, rgb: rgb, fish: fish, config: config, configURL: configURL)
    }

    private func fishProbeImage(arguments: [String]) throws {
        guard arguments.count >= 2 else {
            try throwError("fish-probe-image requires <config.json> <image.png>")
        }

        let configURL = URL(fileURLWithPath: arguments[0])
        let imageURL = URL(fileURLWithPath: arguments[1])
        let config = try loadConfig(configURL)
        guard let fish = config.fish else {
            try throwError("fish-probe-image requires a 'fish' section in config")
        }

        guard let image = loadPNG(imageURL) else {
            try throwError("could not load image: \(imageURL.path)")
        }

        let gray = try makeGrayImage(from: image)
        let rgb = try makeRGBImage(from: image)
        print("Image: \(imageURL.path)")
        print("Screenshot: \(gray.width)x\(gray.height)")
        try printFishProbeDetails(gray: gray, rgb: rgb, fish: fish, config: config, configURL: configURL)
    }

    private func printFishProbeDetails(gray: GrayImage, rgb: RGBImage, fish: FishConfig, config: BotConfig, configURL: URL) throws {
        let templates = try loadFishTemplates(config: fish, baseURL: configURL.deletingLastPathComponent())
        for template in templates.all {
            let result = bestMatch(
                template: template.image,
                name: template.config.name,
                in: gray,
                region: template.config.region,
                regionRatio: template.config.regionRatio,
                matchStride: max(1, config.matchStride ?? 3),
                pixelStride: max(1, config.pixelStride ?? 2)
            )
            let threshold = template.config.threshold ?? config.defaultThreshold ?? 0.92
            if let result {
                let pass = result.score >= threshold ? "PASS" : "fail"
                print("\(pass) \(template.config.name): score=\(format(result.score)) threshold=\(format(threshold)) at=\(result.x),\(result.y) size=\(result.width)x\(result.height)")
            } else {
                print("fail \(template.config.name): template does not fit screenshot or region")
            }
        }

        let bar = detectFishingBar(in: rgb, fish: fish)
        if let bar {
            print("PASS green: count=\(bar.green.count) centerX=\(format(bar.green.centerX)) box=\(bar.green.minX),\(bar.green.minY) \(bar.green.width)x\(bar.green.height)")
            print("PASS cursor: count=\(bar.cursor.count) centerX=\(format(bar.cursor.centerX)) box=\(bar.cursor.minX),\(bar.cursor.minY) \(bar.cursor.width)x\(bar.cursor.height)")
            let deadzone = adaptiveDeadzone(fish: fish, width: rgb.width, greenWidth: bar.green.width)
            print("offset=\(format(bar.offset)) adaptiveDeadzone=\(format(deadzone)) action=\(barActionName(offset: bar.offset, fish: fish, width: rgb.width, greenWidth: bar.green.width))")
        } else {
            print("fail fishing bar: green/cursor color blobs not found")
        }

        if let prompt = detectPrompt(in: rgb, fish: fish) {
            print("PASS prompt: kind=\(prompt.kind.rawValue) count=\(prompt.blob.count) center=\(format(prompt.blob.centerX)),\(format(prompt.blob.centerY)) box=\(prompt.blob.minX),\(prompt.blob.minY) \(prompt.blob.width)x\(prompt.blob.height)")
        } else {
            print("fail prompt: F/key prompt color blob not found")
        }

        if let resultPrompt = detectResultPrompt(in: rgb, fish: fish) {
            print("PASS result-prompt: count=\(resultPrompt.blob.count) center=\(format(resultPrompt.blob.centerX)),\(format(resultPrompt.blob.centerY)) box=\(resultPrompt.blob.minX),\(resultPrompt.blob.minY) \(resultPrompt.blob.width)x\(resultPrompt.blob.height)")
        } else {
            print("fail result-prompt: close-result prompt not found")
        }
    }

    private func fishRun(arguments: [String]) throws {
        guard let configPath = arguments.first else {
            try throwError("fish-run requires <config.json>")
        }

        let forceDryRun = arguments.contains("--dry-run")
        let forceLive = arguments.contains("--live")
        if forceDryRun && forceLive {
            try throwError("choose only one of --dry-run or --live")
        }

        let configURL = URL(fileURLWithPath: configPath)
        let config = try loadConfig(configURL)
        guard let fish = config.fish else {
            try throwError("fish-run requires a 'fish' section in config")
        }

        let dryRun = forceLive ? false : (forceDryRun ? true : (config.dryRun ?? true))
        let loopInterval = Double(max(16, fish.loopIntervalMs ?? config.loopIntervalMs ?? 80)) / 1000.0
        let liveStartDelayMs = dryRun ? 0 : max(0, fish.liveStartDelayMs ?? 3000)
        let inputMode = (config.inputMode ?? "global").lowercased()
        let usePIDTargetedInput = inputMode == "pid" || inputMode == "targetpid" || inputMode == "background"
        let pauseWhenTargetNotFrontmost = usePIDTargetedInput ? false : (config.pauseWhenTargetNotFrontmost ?? false)
        let targetFocusGrace = Double(max(0, config.targetFocusGraceMs ?? 800)) / 1000.0
        let retryLimit = max(1, fish.retryLimit ?? 3)
        let stallTimeout = Double(max(1000, fish.stallTimeoutMs ?? 9000)) / 1000.0
        let assistKey = fish.assistKey ?? "f"
        let assistInterval = Double(max(250, fish.assistKeyIntervalMs ?? 1600)) / 1000.0
        let assistMaxAttempts = max(0, fish.assistKeyMaxAttempts ?? 2)
        let promptKey = fish.promptKey ?? assistKey
        let promptCooldown = Double(max(150, fish.promptCooldownMs ?? fish.assistKeyIntervalMs ?? 800)) / 1000.0
        let startPromptRepeat = Double(max(700, fish.startPromptRepeatMs ?? fish.promptRepeatMs ?? 2200)) / 1000.0
        let hookPromptRepeat = Double(max(250, fish.hookPromptRepeatMs ?? 450)) / 1000.0
        let promptStableFrames = max(1, fish.promptStableFrames ?? 2)
        let promptMaxAttempts = max(1, fish.promptMaxAttempts ?? 8)
        let assistRequiresPrompt = fish.assistRequiresPrompt ?? true
        let fallbackAssistWhenPromptMissing = fish.fallbackAssistWhenPromptMissing ?? false
        let barAssistRequiresPrompt = fish.barAssistRequiresPrompt ?? true
        let resultPromptKey = usePIDTargetedInput ? "space" : (fish.resultPromptKey ?? "mouseClickBlank")
        let resultPromptFallbackKey = usePIDTargetedInput ? "return" : (fish.resultPromptFallbackKey ?? "mouseClickBlank")
        let resultPromptCooldown = Double(max(300, fish.resultPromptCooldownMs ?? 1200)) / 1000.0
        let resultPromptMaxAttempts = max(2, fish.resultPromptMaxAttempts ?? 6)
        let resultPromptStuckTimeout = Double(max(1200, fish.resultPromptStuckTimeoutMs ?? 8000)) / 1000.0
        let resultClickXRatio = min(0.98, max(0.02, fish.resultPromptClickXRatio ?? 0.78))
        let resultClickYRatio = min(0.98, max(0.02, fish.resultPromptClickYRatio ?? 0.76))
        let controlMode = (fish.controlMode ?? "holdSwitch").lowercased()
        let barAssistEveryFrames = max(0, fish.barAssistEveryFrames ?? 10)
        let barAssistDurationMs = max(10, fish.barAssistDurationMs ?? 50)
        let barAssistCooldown = Double(max(0, fish.barAssistCooldownMs ?? 700)) / 1000.0
        let barMissToleranceFrames = max(0, fish.barMissToleranceFrames ?? 15)
        let templates = try loadFishTemplates(config: fish, baseURL: configURL.deletingLastPathComponent())

        var failureCount = 0
        var lastProgressAt = Date()
        var lastAssistAt = Date.distantPast
        var lastBarAssistAt = Date.distantPast
        var lastPromptAt = Date.distantPast
        var lastResultPromptAt = Date.distantPast
        var promptArmed = true
        var resultPromptAttempts = 0
        var resultPromptFirstSeenAt: Date?
        var targetFocusLostAt: Date?
        var currentPromptKind: PromptKind?
        var promptStableCount = 0
        var promptAttempts = 0
        var phase = FishingRunPhase.scanning
        var phaseChangedAt = Date()
        var assistAttempts = 0
        var heldBarKey: String?
        var lastBarDetection: FishingBarDetection?
        var previousBarSample: FishingBarControlSample?
        var barMissCount = 0
        var barFrame = 0
        var lastBarLogAt = Date.distantPast
        var frame = 0

        interruptRequested = 0
        #if !LIBRARY_MODE
        signal(SIGINT) { _ in
            interruptRequested = 1
        }
        #endif

        print("Fish mode: \(dryRun ? "dry-run" : "live")")
        print("Retry limit: \(retryLimit), stall timeout: \(Int(stallTimeout * 1000))ms, control=\(controlMode)")
        print("Input mode: \(usePIDTargetedInput ? "pid-targeted experimental" : "global frontmost")")
        print("Press Ctrl-C to stop.")
        if liveStartDelayMs > 0 {
            print("Live starts in \(liveStartDelayMs)ms; focus the game window now.")
            Thread.sleep(forTimeInterval: Double(liveStartDelayMs) / 1000.0)
        }

        func releaseHeldBarKey() throws {
            guard let key = heldBarKey else { return }
            if dryRun {
                print("  dry-run keyUp \(key)")
            } else {
                try keyUp(key)
            }
            heldBarKey = nil
        }

        func switchHeldBarKey(to newKey: String?) throws {
            if heldBarKey == newKey {
                return
            }
            try releaseHeldBarKey()
            guard let newKey else { return }
            if dryRun {
                print("  dry-run keyDown \(newKey)")
            } else {
                try keyDown(newKey)
            }
            heldBarKey = newKey
        }

        func transition(to nextPhase: FishingRunPhase) {
            if phase != nextPhase {
                phase = nextPhase
                phaseChangedAt = Date()
            }
        }

        func resetPromptCycle() {
            currentPromptKind = nil
            promptStableCount = 0
            promptAttempts = 0
            promptArmed = true
        }

        func promptTiming(for kind: PromptKind) -> (role: String, repeatInterval: TimeInterval, tapDurationMs: Int) {
            switch kind {
            case .blue:
                return ("hook", hookPromptRepeat, 75)
            case .ready:
                return ("start", startPromptRepeat, 45)
            case .result:
                return ("result", startPromptRepeat, 45)
            }
        }

        func promptAllowed(_ kind: PromptKind, during phase: FishingRunPhase) -> Bool {
            switch kind {
            case .blue:
                return true
            case .ready:
                return true
            case .result:
                return false
            }
        }

        func performResultClose(
            key: String,
            resultPrompt: PromptDetection,
            window: WindowInfo,
            image: CGImage,
            dryRun: Bool
        ) throws {
            let lowerKey = key.lowercased()
            if dryRun {
                if lowerKey == "mouseclickresultprompt" || lowerKey == "mouseclickprompt" {
                    print("  dry-run mouseClickResultPrompt x=\(format(resultPrompt.blob.centerX)) y=\(format(resultPrompt.blob.centerY))")
                } else if lowerKey == "mouseclickblank" {
                    print("  dry-run mouseClickBlank x=\(format(resultClickXRatio)) y=\(format(resultClickYRatio))")
                } else {
                    print("  dry-run keyTap \(key)")
                }
                return
            }

            if lowerKey == "mouseclickresultprompt" || lowerKey == "mouseclickprompt" {
                clickMouseAtPixel(
                    buttonName: "left",
                    window: window,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    pixelX: resultPrompt.blob.centerX,
                    pixelY: resultPrompt.blob.centerY
                )
            } else if lowerKey == "mouseclickblank" {
                clickMouseAtRatio(
                    buttonName: "left",
                    window: window,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    xRatio: resultClickXRatio,
                    yRatio: resultClickYRatio
                )
            } else {
                try tapKey(key, durationMs: usePIDTargetedInput ? 100 : 45)
            }
        }

        func promptIsVisible(in image: CGImage) throws -> Bool {
            try promptDetection(in: image) != nil
        }

        func promptDetection(in image: CGImage) throws -> PromptDetection? {
            let region = promptRegion(fish: fish, width: image.width, height: image.height)
            let rgb = try makeRGBImage(from: image, region: region)
            return detectPrompt(
                in: rgb,
                fish: fish,
                regionOverride: RectConfig(x: 0, y: 0, width: rgb.width, height: rgb.height)
            )
        }

        func resultPromptDetection(in image: CGImage) throws -> PromptDetection? {
            let rgb = try makeRGBImage(from: image)
            return detectResultPrompt(in: rgb, fish: fish)
        }

        func pulseAssistDuringBarIfNeeded(frame: Int, window: WindowInfo, fullWidth: Int, fullHeight: Int) throws {
            guard barAssistEveryFrames > 0, frame % barAssistEveryFrames == 0 else { return }
            let now = Date()
            guard now.timeIntervalSince(lastBarAssistAt) >= barAssistCooldown else { return }
            if barAssistRequiresPrompt {
                let region = promptRegion(fish: fish, width: fullWidth, height: fullHeight)
                guard let promptCapture = try? capture(window: window, region: region, fullWidth: fullWidth, fullHeight: fullHeight) else {
                    return
                }
                let rgb = try makeRGBImage(from: promptCapture)
                guard let prompt = detectPrompt(
                    in: rgb,
                    fish: fish,
                    regionOverride: RectConfig(x: 0, y: 0, width: rgb.width, height: rgb.height)
                ), prompt.kind != .ready else {
                    return
                }
            }
            let restoreKey = heldBarKey
            if let restoreKey {
                if dryRun {
                    print("  dry-run keyUp \(restoreKey)")
                } else {
                    try keyUp(restoreKey)
                }
            }
            if dryRun {
                print("  dry-run barAssist \(promptKey)")
            } else {
                try tapKey(promptKey, durationMs: barAssistDurationMs)
            }
            lastBarAssistAt = now
            if let restoreKey {
                if dryRun {
                    print("  dry-run keyDown \(restoreKey)")
                } else {
                    try keyDown(restoreKey)
                }
            }
        }

        while true {
            if interruptRequested != 0 {
                try releaseHeldBarKey()
                inputTargetPID = nil
                print("[\(timestamp())] stopped by Ctrl-C")
                return
            }

            let window = try findWindow(matching: config.windowMatch)
            inputTargetPID = usePIDTargetedInput ? window.ownerPID : nil
            if config.activateWindow ?? true {
                activate(window: window)
            }

            let estimatedSize = estimatedCaptureSize(window: window)
            let now = Date()
            frame += 1

            if pauseWhenTargetNotFrontmost && !isWindowOwnerFrontmost(window) {
                try releaseHeldBarKey()
                if targetFocusLostAt == nil {
                    targetFocusLostAt = now
                    print("[\(timestamp())] target window is not frontmost; waiting")
                } else if let lostAt = targetFocusLostAt,
                          now.timeIntervalSince(lostAt) >= targetFocusGrace,
                          frame % 60 == 0 {
                    print("[\(timestamp())] target window still not frontmost; waiting")
                }
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            } else {
                if targetFocusLostAt != nil {
                    print("[\(timestamp())] target window frontmost again; resuming")
                }
                targetFocusLostAt = nil
            }

            let barRegion = fishingBarRegion(fish: fish, width: estimatedSize.width, height: estimatedSize.height)
            var fullImage: CGImage?
            let regionCapture = try? capture(window: window, region: barRegion, fullWidth: estimatedSize.width, fullHeight: estimatedSize.height)
            let regionBar: FishingBarDetection?
            if let regionCapture {
                let barRGB = try makeRGBImage(from: regionCapture)
                regionBar = detectFishingBar(
                    in: barRGB,
                    fish: fish,
                    regionOverride: RectConfig(x: 0, y: 0, width: barRGB.width, height: barRGB.height)
                )
            } else {
                regionBar = nil
            }

            let detectedBar: FishingBarDetection?
            if let regionBar {
                detectedBar = regionBar
            } else {
                let cgImage = try capture(window: window)
                fullImage = cgImage
                let fallbackRegion = fishingBarRegion(fish: fish, width: cgImage.width, height: cgImage.height)
                let barRGB = try makeRGBImage(from: cgImage, region: fallbackRegion)
                detectedBar = detectFishingBar(
                    in: barRGB,
                    fish: fish,
                    regionOverride: RectConfig(x: 0, y: 0, width: barRGB.width, height: barRGB.height)
                )
            }
            let bar: FishingBarDetection?
            let usingStaleBar: Bool
            if let detectedBar {
                lastBarDetection = detectedBar
                barMissCount = 0
                bar = detectedBar
                usingStaleBar = false
            } else if let lastBarDetection, barMissCount < barMissToleranceFrames {
                barMissCount += 1
                bar = lastBarDetection
                usingStaleBar = true
            } else {
                lastBarDetection = nil
                barMissCount = 0
                bar = nil
                usingStaleBar = false
            }

            if let bar {
                transition(to: .pulling)
                promptArmed = true
                resultPromptAttempts = 0
                resultPromptFirstSeenAt = nil
                resetPromptCycle()
                barFrame += 1
                let controlOffset = adjustedBarOffset(
                    bar: bar,
                    previous: usingStaleBar ? nil : previousBarSample,
                    fish: fish,
                    width: estimatedSize.width,
                    now: now
                )
                if !usingStaleBar {
                    previousBarSample = FishingBarControlSample(bar: bar, timestamp: now)
                }
                let actionName = barActionName(
                    offset: controlOffset,
                    fish: fish,
                    width: estimatedSize.width,
                    greenWidth: bar.green.width
                )
                if controlMode == "holdswitch" {
                    let nextKey = holdSwitchKey(
                        offset: controlOffset,
                        fish: fish,
                        width: estimatedSize.width,
                        greenWidth: bar.green.width,
                        heldKey: heldBarKey
                    )
                    let changed = heldBarKey != nextKey
                    try switchHeldBarKey(to: nextKey)
                    if now.timeIntervalSince(lastBarLogAt) >= 0.35 || changed {
                        let status = nextKey.map { "hold=\($0)" } ?? "release"
                        let stale = usingStaleBar ? " stale=\(barMissCount)" : ""
                        let predicted = abs(controlOffset - bar.offset) >= 0.5 ? " control=\(format(controlOffset))" : ""
                        let deadzone = adaptiveDeadzone(fish: fish, width: estimatedSize.width, greenWidth: bar.green.width)
                        print("[\(timestamp())] bar offset=\(format(bar.offset))\(predicted) green=\(bar.green.width) zone=\(format(deadzone)) \(status)\(stale)")
                        lastBarLogAt = now
                    }
                    try pulseAssistDuringBarIfNeeded(frame: barFrame, window: window, fullWidth: estimatedSize.width, fullHeight: estimatedSize.height)
                } else {
                    try releaseHeldBarKey()
                    if actionName == "A" || actionName == "D" {
                        let duration = holdDurationMs(offset: controlOffset, fish: fish, width: estimatedSize.width)
                        if now.timeIntervalSince(lastBarLogAt) >= 0.25 {
                            let predicted = abs(controlOffset - bar.offset) >= 0.5 ? " control=\(format(controlOffset))" : ""
                            print("[\(timestamp())] bar offset=\(format(bar.offset))\(predicted) pulse=\(actionName) duration=\(duration)ms")
                            lastBarLogAt = now
                        }
                        if dryRun {
                            print("  dry-run keyPulse \(actionName.lowercased())")
                        } else {
                            try tapKey(actionName.lowercased(), durationMs: duration)
                        }
                    } else if frame % 20 == 0 {
                        print("[\(timestamp())] bar centered offset=\(format(bar.offset))")
                    }
                }
                lastProgressAt = now
                failureCount = 0
                assistAttempts = 0
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            barFrame = 0
            previousBarSample = nil

            let cgImage: CGImage
            if let fullImage {
                cgImage = fullImage
            } else {
                cgImage = try capture(window: window)
            }

            let resultPrompt = try resultPromptDetection(in: cgImage)
            if resultPrompt == nil {
                resultPromptAttempts = 0
                resultPromptFirstSeenAt = nil
            }
            if resultPrompt != nil {
                transition(to: .result)
                if resultPromptFirstSeenAt == nil {
                    resultPromptFirstSeenAt = now
                }
            }
            if let resultPrompt,
               now.timeIntervalSince(lastResultPromptAt) >= resultPromptCooldown {
                try releaseHeldBarKey()
                let firstSeenAt = resultPromptFirstSeenAt ?? now
                let stuck = now.timeIntervalSince(firstSeenAt) >= resultPromptStuckTimeout
                var resultCloseFailure = false
                if resultPromptAttempts >= resultPromptMaxAttempts {
                    failureCount += 1
                    resultCloseFailure = true
                    resultPromptAttempts = max(0, resultPromptMaxAttempts - 1)
                    print("[\(timestamp())] result close stuck; failure \(failureCount)/\(retryLimit)")
                    if failureCount >= retryLimit {
                        print("[\(timestamp())] paused: result screen did not close after retries")
                        return
                    }
                }
                resultPromptAttempts += 1
                lastResultPromptAt = now
                let closeKey = (stuck || resultPromptAttempts >= 3) ? resultPromptFallbackKey : resultPromptKey
                if resultPromptAttempts == 1 {
                    print("[\(timestamp())] result prompt visible; closing attempt \(resultPromptAttempts)/\(resultPromptMaxAttempts) with \(closeKey)")
                } else {
                    print("[\(timestamp())] result close retry \(resultPromptAttempts)/\(resultPromptMaxAttempts) with \(closeKey)")
                }
                try performResultClose(key: closeKey, resultPrompt: resultPrompt, window: window, image: cgImage, dryRun: dryRun)
                lastProgressAt = now
                if !resultCloseFailure {
                    failureCount = 0
                }
                assistAttempts = 0
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            let gray = try makeGrayImage(from: cgImage)

            if let pauseMatch = firstTemplateMatch(named: "pause", templates: templates.pause, in: gray, config: config) {
                try releaseHeldBarKey()
                failureCount += 1
                print("[\(timestamp())] pause condition \(pauseMatch.name) score=\(format(pauseMatch.score)); failure \(failureCount)/\(retryLimit)")
                if failureCount >= retryLimit {
                    print("[\(timestamp())] paused: repeated pause/error condition")
                    return
                }
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            if let resultMatch = firstTemplateMatch(named: "result", templates: templates.result.map { [$0] } ?? [], in: gray, config: config) {
                transition(to: .result)
                try releaseHeldBarKey()
                print("[\(timestamp())] result \(resultMatch.name) score=\(format(resultMatch.score)); closing")
                let defaultResultAction = ActionConfig(
                    type: "keyTap",
                    key: usePIDTargetedInput ? "space" : "escape",
                    button: nil,
                    durationMs: usePIDTargetedInput ? 100 : nil,
                    xOffset: nil,
                    yOffset: nil
                )
                try perform(actions: templates.result?.config.actions ?? [defaultResultAction], window: window, image: gray, match: resultMatch, dryRun: dryRun)
                lastProgressAt = now
                failureCount = 0
                assistAttempts = 0
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            try releaseHeldBarKey()

            if let hookMatch = firstTemplateMatch(named: "hook", templates: templates.hook.map { [$0] } ?? [], in: gray, config: config) {
                transition(to: .waitingHook)
                print("[\(timestamp())] hook \(hookMatch.name) score=\(format(hookMatch.score)); pressing F")
                let actions = templates.hook?.config.actions ?? [ActionConfig(type: "keyTap", key: "f", button: nil, durationMs: nil, xOffset: nil, yOffset: nil)]
                try perform(actions: actions, window: window, image: gray, match: hookMatch, dryRun: dryRun)
                lastProgressAt = now
                assistAttempts = 0
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            if let startMatch = firstTemplateMatch(named: "start", templates: templates.start.map { [$0] } ?? [], in: gray, config: config) {
                transition(to: .waitingHook)
                print("[\(timestamp())] start \(startMatch.name) score=\(format(startMatch.score)); starting")
                let actions = templates.start?.config.actions ?? [ActionConfig(type: "mouseClick", key: nil, button: "left", durationMs: nil, xOffset: nil, yOffset: nil)]
                try perform(actions: actions, window: window, image: gray, match: startMatch, dryRun: dryRun)
                lastProgressAt = now
                failureCount = 0
                assistAttempts = 0
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            let prompt = try promptDetection(in: cgImage)
            if prompt == nil {
                resetPromptCycle()
            }
            if let prompt {
                if currentPromptKind == prompt.kind {
                    promptStableCount += 1
                } else {
                    currentPromptKind = prompt.kind
                    promptStableCount = 1
                    promptAttempts = 0
                    promptArmed = true
                }
            }
            if let prompt,
               assistRequiresPrompt {
                let timing = promptTiming(for: prompt.kind)
                if !promptAllowed(prompt.kind, during: phase) {
                    if dryRun, frame % 90 == 0 {
                        print("[\(timestamp())] waiting for blue hook prompt; ignoring \(prompt.kind.rawValue)")
                    }
                } else {
                    transition(to: timing.role == "hook" ? .waitingHook : .waitingFishing)
                    let readyCooldown = prompt.kind == .ready ? 0.35 : promptCooldown
                    let requiredCooldown = min(readyCooldown, timing.repeatInterval)
                    let stableEnough = prompt.kind == .blue || prompt.kind == .ready || promptStableCount >= promptStableFrames
                    let repeatReady = promptArmed || now.timeIntervalSince(lastPromptAt) >= timing.repeatInterval
                    let canTap = stableEnough
                        && promptAttempts < promptMaxAttempts
                        && now.timeIntervalSince(lastPromptAt) >= requiredCooldown
                        && repeatReady
                    if canTap {
                        promptAttempts += 1
                        lastPromptAt = now
                        promptArmed = false
                        print("[\(timestamp())] \(timing.role) prompt visible kind=\(prompt.kind.rawValue); pressing \(promptKey) attempt \(promptAttempts)/\(promptMaxAttempts)")
                        if dryRun {
                            print("  dry-run keyTap \(promptKey)")
                        } else {
                            let tapDuration = usePIDTargetedInput ? max(timing.tapDurationMs, 100) : timing.tapDurationMs
                            try tapKey(promptKey, durationMs: tapDuration)
                        }
                        if prompt.kind == .ready {
                            transition(to: .waitingHook)
                            resetPromptCycle()
                        }
                        lastProgressAt = now
                        failureCount = 0
                        assistAttempts = 0
                        Thread.sleep(forTimeInterval: loopInterval)
                        continue
                    } else if promptAttempts >= promptMaxAttempts,
                              now.timeIntervalSince(phaseChangedAt) >= stallTimeout {
                        failureCount += 1
                        resetPromptCycle()
                        lastProgressAt = now
                        print("[\(timestamp())] \(timing.role) prompt stuck; failure \(failureCount)/\(retryLimit)")
                        if failureCount >= retryLimit {
                            try releaseHeldBarKey()
                            print("[\(timestamp())] paused: prompt did not advance after retries")
                            return
                        }
                        Thread.sleep(forTimeInterval: loopInterval)
                        continue
                    }
                }
            }
            if (!assistRequiresPrompt || fallbackAssistWhenPromptMissing),
               assistMaxAttempts > 0,
               assistAttempts < assistMaxAttempts,
               now.timeIntervalSince(lastAssistAt) >= assistInterval {
                assistAttempts += 1
                lastAssistAt = now
                resetPromptCycle()
                print("[\(timestamp())] fallback assist key \(assistKey) attempt \(assistAttempts)/\(assistMaxAttempts)")
                if dryRun {
                    print("  dry-run keyTap \(assistKey)")
                } else {
                    try tapKey(assistKey, durationMs: 45)
                }
                Thread.sleep(forTimeInterval: loopInterval)
                continue
            }

            if now.timeIntervalSince(lastProgressAt) >= stallTimeout {
                failureCount += 1
                lastProgressAt = now
                transition(to: .scanning)
                print("[\(timestamp())] no actionable fishing state; failure \(failureCount)/\(retryLimit)")
                if failureCount >= retryLimit {
                    try releaseHeldBarKey()
                    print("[\(timestamp())] paused: unable to continue fishing after retries")
                    return
                }
            } else if dryRun, frame % 50 == 0 {
                print("[\(timestamp())] dry-run fishing scan...")
            }

            Thread.sleep(forTimeInterval: loopInterval)
        }
    }

    private func visibleWindows() -> [WindowInfo] {
        windowList(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    private func allWindows() -> [WindowInfo] {
        windowList(options: [.optionAll, .excludeDesktopElements])
    }

    private func windowList(options: CGWindowListOption) -> [WindowInfo] {
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [WindowInfo] = []
        for entry in rawList {
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }

            guard let idNumber = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            let id = CGWindowID(idNumber.uint32Value)
            let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let title = entry[kCGWindowName as String] as? String ?? ""

            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            guard bounds.width >= 50, bounds.height >= 50 else { continue }

            windows.append(WindowInfo(
                id: id,
                ownerPID: pid_t(ownerPID),
                ownerName: ownerName,
                title: title,
                bounds: bounds
            ))
        }
        return windows
    }

    private func filterWindowList(_ windows: [WindowInfo], matching filter: String?) -> [WindowInfo] {
        guard let filter, !filter.isEmpty else { return windows }
        return windows.filter { window in
            contains(window.ownerName, filter) || contains(window.title, filter) || contains(window.label, filter)
        }
    }

    private func findWindow(matching text: String) throws -> WindowInfo {
        var matches = filterWindowList(visibleWindows(), matching: text)
        if matches.isEmpty {
            matches = filterWindowList(allWindows(), matching: text)
        }
        guard let first = matches.first else {
            try throwError("no window matched '\(text)'; use '\(executableName) list --all' to inspect titles")
        }
        return first
    }

    private func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func activate(window: WindowInfo) {
        guard window.ownerPID > 0 else { return }
        let app = NSRunningApplication(processIdentifier: window.ownerPID)
        app?.activate(options: [.activateIgnoringOtherApps])
    }

    private func isWindowOwnerFrontmost(_ window: WindowInfo) -> Bool {
        guard window.ownerPID > 0,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        return frontmostPID == window.ownerPID
    }

    private func capture(window: WindowInfo) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            try throwError("failed to capture window; check Screen Recording permission")
        }

        guard image.width > 8, image.height > 8 else {
            try throwError("captured image is unexpectedly small; check Screen Recording permission")
        }

        return image
    }

    private func capture(window: WindowInfo, region: RectConfig, fullWidth: Int, fullHeight: Int) throws -> CGImage {
        let screenRect = screenRectForWindowRegion(window: window, region: region, fullWidth: fullWidth, fullHeight: fullHeight)
        guard let image = CGWindowListCreateImage(
            screenRect,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            try throwError("failed to capture window region; check Screen Recording permission")
        }

        guard image.width > 2, image.height > 2 else {
            try throwError("captured region is unexpectedly small; check Screen Recording permission")
        }

        return image
    }

    private func estimatedCaptureSize(window: WindowInfo) -> (width: Int, height: Int) {
        let scale = displayScale(for: window)
        let width = max(1, Int((window.bounds.width * scale).rounded()))
        let height = max(1, Int((window.bounds.height * scale).rounded()))
        return (width, height)
    }

    private func screenRectForWindowRegion(window: WindowInfo, region: RectConfig, fullWidth: Int, fullHeight: Int) -> CGRect {
        let xScale = window.bounds.width / CGFloat(max(1, fullWidth))
        let yScale = window.bounds.height / CGFloat(max(1, fullHeight))
        var rect = CGRect(
            x: window.bounds.minX + CGFloat(region.x) * xScale,
            y: window.bounds.minY + CGFloat(region.y) * yScale,
            width: CGFloat(max(1, region.width)) * xScale,
            height: CGFloat(max(1, region.height)) * yScale
        ).integral
        rect = rect.intersection(window.bounds)
        if rect.isNull || rect.width <= 0 || rect.height <= 0 {
            return window.bounds
        }
        return rect
    }

    private func displayScale(for window: WindowInfo) -> CGFloat {
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        for screen in NSScreen.screens where screen.frame.contains(center) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 1.0
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            try throwError("could not create PNG destination: \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try throwError("could not write PNG: \(url.path)")
        }
    }

    private func loadConfig(_ url: URL) throws -> BotConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BotConfig.self, from: data)
    }

    private func loadTemplates(config: BotConfig, baseURL: URL) throws -> [TemplateRuntime] {
        try (config.templates ?? []).map { template in
            let templateURL = resolvePath(template.path, baseURL: baseURL)
            guard FileManager.default.fileExists(atPath: templateURL.path) else {
                try throwError("template '\(template.name)' not found: \(templateURL.path)")
            }

            guard let image = loadPNG(templateURL) else {
                try throwError("could not load template '\(template.name)': \(templateURL.path)")
            }

            let gray = try makeGrayImage(from: image)
            return TemplateRuntime(config: template, image: gray)
        }
    }

    private func loadFishTemplates(config: FishConfig, baseURL: URL) throws -> FishTemplateSet {
        let start = try loadFishTemplate(config.start, baseURL: baseURL)
        let hook = try loadFishTemplate(config.hook, baseURL: baseURL)
        let result = try loadFishTemplate(config.result, baseURL: baseURL)
        let pause = try (config.pause ?? []).map { template in
            guard let runtime = try loadFishTemplate(template, baseURL: baseURL) else {
                try throwError("unexpected empty pause template")
            }
            return runtime
        }
        return FishTemplateSet(start: start, hook: hook, result: result, pause: pause)
    }

    private func loadFishTemplate(_ config: FishTemplateConfig?, baseURL: URL) throws -> FishTemplateRuntime? {
        guard let config else { return nil }
        let templateURL = resolvePath(config.path, baseURL: baseURL)
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            try throwError("fish template '\(config.name)' not found: \(templateURL.path)")
        }
        guard let image = loadPNG(templateURL) else {
            try throwError("could not load fish template '\(config.name)': \(templateURL.path)")
        }
        return FishTemplateRuntime(config: config, image: try makeGrayImage(from: image))
    }

    private func firstTemplateMatch(named _: String, templates: [FishTemplateRuntime], in image: GrayImage, config: BotConfig) -> MatchResult? {
        var bestPassing: MatchResult?
        for template in templates {
            guard let result = bestMatch(
                template: template.image,
                name: template.config.name,
                in: image,
                region: template.config.region,
                regionRatio: template.config.regionRatio,
                matchStride: max(1, config.matchStride ?? 3),
                pixelStride: max(1, config.pixelStride ?? 2)
            ) else {
                continue
            }
            let threshold = template.config.threshold ?? config.defaultThreshold ?? 0.92
            guard result.score >= threshold else { continue }
            if bestPassing == nil || result.score > bestPassing!.score {
                bestPassing = result
            }
        }
        return bestPassing
    }

    private func resolvePath(_ path: String, baseURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return baseURL.appendingPathComponent(path)
    }

    private func loadPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func makeGrayImage(from image: CGImage) throws -> GrayImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drewImage = rgba.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else {
            try throwError("could not convert image to grayscale")
        }

        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let index = row + x * bytesPerPixel
                let r = Int(rgba[index])
                let g = Int(rgba[index + 1])
                let b = Int(rgba[index + 2])
                gray[y * width + x] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
            }
        }

        return GrayImage(width: width, height: height, pixels: gray)
    }

    private func makeRGBImage(from image: CGImage, region: RectConfig? = nil) throws -> RGBImage {
        let sourceImage: CGImage
        if let region {
            let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
            guard let cropped = image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)) else {
                try throwError("could not crop RGB region")
            }
            sourceImage = cropped
        } else {
            sourceImage = image
        }

        let width = sourceImage.width
        let height = sourceImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drewImage = rgba.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else {
            try throwError("could not convert image to RGB")
        }

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            let rgbaRow = y * bytesPerRow
            let rgbRow = y * width * 3
            for x in 0..<width {
                let rgbaIndex = rgbaRow + x * bytesPerPixel
                let rgbIndex = rgbRow + x * 3
                rgb[rgbIndex] = rgba[rgbaIndex]
                rgb[rgbIndex + 1] = rgba[rgbaIndex + 1]
                rgb[rgbIndex + 2] = rgba[rgbaIndex + 2]
            }
        }

        return RGBImage(width: width, height: height, pixels: rgb)
    }

    private func detectFishingBar(in image: RGBImage, fish: FishConfig, regionOverride: RectConfig? = nil) -> FishingBarDetection? {
        let region = regionOverride ?? fishingBarRegion(fish: fish, width: image.width, height: image.height)
        let stride = max(1, fish.colorStride ?? 2)
        let greenRule = fish.greenColor ?? ColorRuleConfig(
            mode: "hsv",
            lower: nil,
            upper: nil,
            hue: [145, 190],
            saturation: [0.25, 1.0],
            brightness: [0.30, 1.0]
        )
        let cursorRule = fish.cursorColor ?? ColorRuleConfig(
            mode: "hsv",
            lower: nil,
            upper: nil,
            hue: [35, 70],
            saturation: [0.35, 1.0],
            brightness: [0.45, 1.0]
        )

        guard let green = horizontalColorComponent(
                in: image,
                region: region,
                rule: greenRule,
                stride: stride,
                minPixels: max(1, fish.minGreenPixels ?? 30)
              ),
              green.count >= max(1, fish.minGreenPixels ?? 30),
              let cursor = verticalColorComponent(
                in: image,
                region: region,
                rule: cursorRule,
                stride: stride,
                minPixels: max(1, fish.minCursorPixels ?? 5),
                targetY: green.centerY
              ),
              cursor.count >= max(1, fish.minCursorPixels ?? 5) else {
            return nil
        }

        return FishingBarDetection(
            green: green,
            cursor: cursor,
            offset: cursor.centerX - green.centerX
        )
    }

    private func fishingBarRegion(fish: FishConfig, width: Int, height: Int) -> RectConfig {
        pixelRegion(
            region: fish.barRegion,
            regionRatio: fish.barRegionRatio ?? RatioRectConfig(x: 0.300, y: 0.075, width: 0.450, height: 0.040),
            width: width,
            height: height
        )
    }

    private func detectPrompt(in image: RGBImage, fish: FishConfig, regionOverride: RectConfig? = nil) -> PromptDetection? {
        let region = regionOverride ?? promptRegion(fish: fish, width: image.width, height: image.height)
        let stride = max(1, fish.colorStride ?? 2)
        let blueRule = fish.promptActiveColor ?? ColorRuleConfig(
            mode: "hsv",
            lower: nil,
            upper: nil,
            hue: [205, 245],
            saturation: [0.35, 1.0],
            brightness: [0.45, 1.0]
        )
        let readyRule = ColorRuleConfig(
            mode: "hsv",
            lower: nil,
            upper: nil,
            hue: [0, 360],
            saturation: [0.0, 0.45],
            brightness: [0.58, 1.0]
        )

        let minPixels = max(1, fish.minPromptPixels ?? 18)
        let buttonRegion = promptButtonRegion(in: region, imageWidth: image.width, imageHeight: image.height)
        let blueComponents = colorComponents(in: image, region: buttonRegion, rule: blueRule, stride: stride)
        if let blue = bestPromptComponent(in: image, region: buttonRegion, components: blueComponents, minPixels: max(minPixels, 28)) {
            return PromptDetection(blob: blue, kind: .blue)
        }

        if let ready = readyActionClusterPrompt(in: image, region: region, rule: readyRule, stride: stride, minPixels: minPixels) {
            return PromptDetection(blob: ready, kind: .ready)
        }

        return nil
    }

    private func detectResultPrompt(in image: RGBImage, fish: FishConfig, regionOverride: RectConfig? = nil) -> PromptDetection? {
        let region = regionOverride ?? resultPromptRegion(fish: fish, width: image.width, height: image.height)
        let stride = max(1, fish.colorStride ?? 2)
        let rule = fish.resultPromptColor ?? ColorRuleConfig(
            mode: "hsv",
            lower: nil,
            upper: nil,
            hue: [0, 360],
            saturation: [0.0, 0.38],
            brightness: [0.70, 1.0]
        )
        guard let blob = colorBlob(in: image, region: region, rule: rule, stride: stride),
              blob.count >= max(1, fish.minResultPromptPixels ?? 90) else {
            return nil
        }
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let minWidth = max(20, Int((Double(rect.width) * 0.20).rounded()))
        let maxWidth = max(minWidth, Int((Double(rect.width) * 0.85).rounded()))
        let minHeight = max(8, rect.height / 10)
        let maxHeight = max(minHeight, Int((Double(rect.height) * 0.72).rounded()))
        guard blob.width >= minWidth,
              blob.width <= maxWidth,
              blob.height >= minHeight,
              blob.height <= maxHeight else {
            return nil
        }
        return PromptDetection(blob: blob, kind: .result)
    }

    private func bestPromptComponent(in image: RGBImage, region: RectConfig, components: [ColorBlob], minPixels: Int) -> ColorBlob? {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let minSize = max(4, min(rect.width, rect.height) / 80)
        let maxSize = max(24, min(rect.width, rect.height) / 2)

        var best: (blob: ColorBlob, score: Double)?
        for component in components {
            guard component.count >= minPixels,
                  component.width >= minSize,
                  component.height >= minSize,
                  component.width <= maxSize,
                  component.height <= maxSize else {
                continue
            }

            let aspect = Double(component.width) / Double(max(1, component.height))
            guard aspect >= 0.35, aspect <= 2.8 else { continue }

            let sizeScore = Double(component.width + component.height)
            let centerBias = component.centerX / Double(max(1, image.width))
            let score = Double(component.count) * 3.0 + sizeScore + centerBias * 24.0
            if best == nil || score > best!.score {
                best = (component, score)
            }
        }

        return best?.blob
    }

    private func readyActionClusterPrompt(
        in image: RGBImage,
        region: RectConfig,
        rule: ColorRuleConfig,
        stride: Int,
        minPixels: Int
    ) -> ColorBlob? {
        let iconRegion = promptActionClusterRegion(in: region, imageWidth: image.width, imageHeight: image.height)
        let rect = pixelRegion(region: iconRegion, regionRatio: nil, width: image.width, height: image.height)

        let scanStride = max(stride, 2)
        let bucketCount = 6
        var buckets = Array(repeating: 0, count: bucketCount)
        var count = 0
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        let endX = min(image.width, rect.x + rect.width)
        let endY = min(image.height, rect.y + rect.height)
        guard rect.x < endX, rect.y < endY else { return nil }

        var y = rect.y
        while y < endY {
            var x = rect.x
            while x < endX {
                let color = image.rgbAt(x: x, y: y)
                if matchesColor(r: color.r, g: color.g, b: color.b, rule: rule) {
                    count += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)

                    let bucket = min(bucketCount - 1, max(0, ((x - rect.x) * bucketCount) / max(1, rect.width)))
                    buckets[bucket] += 1
                }
                x += scanStride
            }
            y += scanStride
        }

        let minBucketPixels = max(3, minPixels / 3)
        let activeBuckets = buckets.enumerated().compactMap { index, value in
            value >= minBucketPixels ? index : nil
        }
        guard count >= max(minPixels, 24),
              let firstBucket = activeBuckets.first,
              let lastBucket = activeBuckets.last,
              activeBuckets.count >= 2,
              lastBucket - firstBucket >= 2,
              maxX - minX >= max(36, Int((Double(rect.width) * 0.18).rounded())) else {
            return nil
        }

        return ColorBlob(count: count, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func promptRegion(fish: FishConfig, width: Int, height: Int) -> RectConfig {
        pixelRegion(
            region: fish.promptRegion,
            regionRatio: fish.promptRegionRatio ?? RatioRectConfig(x: 0.68, y: 0.45, width: 0.30, height: 0.52),
            width: width,
            height: height
        )
    }

    private func promptButtonRegion(in region: RectConfig, imageWidth: Int, imageHeight: Int) -> RectConfig {
        let x = region.x + Int((Double(region.width) * 0.66).rounded())
        let y = region.y + Int((Double(region.height) * 0.52).rounded())
        let width = max(24, Int((Double(region.width) * 0.34).rounded()))
        let height = max(24, Int((Double(region.height) * 0.48).rounded()))
        return clampRegion(RectConfig(x: x, y: y, width: width, height: height), width: imageWidth, height: imageHeight)
    }

    private func promptActionClusterRegion(in region: RectConfig, imageWidth: Int, imageHeight: Int) -> RectConfig {
        let x = region.x + Int((Double(region.width) * 0.02).rounded())
        let y = region.y + Int((Double(region.height) * 0.58).rounded())
        let width = max(32, Int((Double(region.width) * 0.60).rounded()))
        let height = max(24, Int((Double(region.height) * 0.40).rounded()))
        return clampRegion(RectConfig(x: x, y: y, width: width, height: height), width: imageWidth, height: imageHeight)
    }

    private func resultPromptRegion(fish: FishConfig, width: Int, height: Int) -> RectConfig {
        pixelRegion(
            region: fish.resultPromptRegion,
            regionRatio: fish.resultPromptRegionRatio ?? RatioRectConfig(x: 0.32, y: 0.80, width: 0.36, height: 0.16),
            width: width,
            height: height
        )
    }

    private func horizontalColorComponent(
        in image: RGBImage,
        region: RectConfig,
        rule: ColorRuleConfig,
        stride: Int,
        minPixels: Int
    ) -> ColorBlob? {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let components = colorComponents(in: image, region: rect, rule: rule, stride: stride)
        guard !components.isEmpty else { return nil }

        let minWidth = max(30, rect.width / 20)
        let maxWidth = max(minWidth, Int((Double(rect.width) * 0.72).rounded()))
        let minHeight = max(5, rect.height / 12)
        let maxHeight = max(minHeight, Int((Double(rect.height) * 0.68).rounded()))
        let targetY = Double(rect.y + rect.height / 2)

        var best: (blob: ColorBlob, score: Double)?
        for component in components {
            guard component.count >= minPixels,
                  component.width >= minWidth,
                  component.width <= maxWidth,
                  component.height >= minHeight,
                  component.height <= maxHeight else {
                continue
            }

            let area = max(1, component.width * component.height)
            let density = Double(component.count * stride * stride) / Double(area)
            let aspect = Double(component.width) / Double(max(1, component.height))
            guard density >= 0.12, aspect >= 3.0 else { continue }

            let yPenalty = abs(component.centerY - targetY) / Double(max(1, rect.height))
            let score = Double(component.width) * 4.0
                + Double(component.count) * 2.0
                + aspect * 8.0
                + density * 120.0
                - yPenalty * 80.0

            if best == nil || score > best!.score {
                best = (component, score)
            }
        }

        return best?.blob
    }

    private func horizontalColorBand(
        in image: RGBImage,
        region: RectConfig,
        rule: ColorRuleConfig,
        stride: Int,
        minPixels: Int
    ) -> ColorBlob? {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let endX = min(image.width, rect.x + rect.width)
        let endY = min(image.height, rect.y + rect.height)
        guard rect.x < endX, rect.y < endY else { return nil }

        struct RowBand {
            let y: Int
            let count: Int
            let minX: Int
            let maxX: Int
            let score: Double
        }

        var rows: [RowBand] = []
        var y = rect.y
        while y < endY {
            var count = 0
            var minX = Int.max
            var maxX = Int.min

            var x = rect.x
            while x < endX {
                let color = image.rgbAt(x: x, y: y)
                if matchesColor(r: color.r, g: color.g, b: color.b, rule: rule) {
                    count += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
                x += stride
            }

            if count > 0 {
                let width = max(1, maxX - minX + 1)
                let score = Double(count) * log2(Double(width) + 1.0)
                rows.append(RowBand(y: y, count: count, minX: minX, maxX: maxX, score: score))
            }
            y += stride
        }

        guard let best = rows.max(by: { $0.score < $1.score }) else { return nil }

        let minRowCount = max(2, Int((Double(best.count) * 0.35).rounded()))
        let halfHeight = max(stride * 4, min(36, rect.height / 2))
        var count = 0
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        for row in rows where abs(row.y - best.y) <= halfHeight && row.count >= minRowCount {
            count += row.count
            minX = min(minX, row.minX)
            minY = min(minY, row.y)
            maxX = max(maxX, row.maxX)
            maxY = max(maxY, row.y)
        }

        guard count >= minPixels else { return nil }
        return ColorBlob(count: count, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func verticalColorComponent(
        in image: RGBImage,
        region: RectConfig,
        rule: ColorRuleConfig,
        stride: Int,
        minPixels: Int,
        targetY: Double
    ) -> ColorBlob? {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let components = colorComponents(in: image, region: rect, rule: rule, stride: stride)
        guard !components.isEmpty else { return nil }

        let maxCursorWidth = max(4, min(80, rect.width / 10))
        let minCursorHeight = max(4, rect.height / 16)
        var best: (blob: ColorBlob, score: Double)?

        for component in components {
            guard component.count >= minPixels,
                  component.width <= maxCursorWidth,
                  component.height >= minCursorHeight else {
                continue
            }

            let verticality = Double(component.height) / Double(max(1, component.width))
            let yDistance = abs(component.centerY - targetY)
            let yPenalty = yDistance / Double(max(1, rect.height))
            let score = Double(component.count) * 2.0
                + Double(component.height) * 4.0
                + verticality * 12.0
                - Double(component.width)
                - yPenalty * 30.0

            if best == nil || score > best!.score {
                best = (component, score)
            }
        }

        return best?.blob
    }

    private func colorComponents(in image: RGBImage, region: RectConfig, rule: ColorRuleConfig, stride: Int) -> [ColorBlob] {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        let endX = min(image.width, rect.x + rect.width)
        let endY = min(image.height, rect.y + rect.height)
        guard rect.x < endX, rect.y < endY else { return [] }

        let gridWidth = max(1, (endX - rect.x + stride - 1) / stride)
        let gridHeight = max(1, (endY - rect.y + stride - 1) / stride)
        let cellCount = gridWidth * gridHeight
        var mask = [Bool](repeating: false, count: cellCount)
        var visited = [Bool](repeating: false, count: cellCount)

        for gy in 0..<gridHeight {
            let y = rect.y + gy * stride
            guard y < endY else { continue }
            for gx in 0..<gridWidth {
                let x = rect.x + gx * stride
                guard x < endX else { continue }
                let color = image.rgbAt(x: x, y: y)
                mask[gy * gridWidth + gx] = matchesColor(r: color.r, g: color.g, b: color.b, rule: rule)
            }
        }

        var components: [ColorBlob] = []
        var stack: [Int] = []
        stack.reserveCapacity(256)

        for start in 0..<cellCount {
            guard mask[start], !visited[start] else { continue }

            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)

            var count = 0
            var minX = Int.max
            var minY = Int.max
            var maxX = Int.min
            var maxY = Int.min

            while let index = stack.popLast() {
                let gx = index % gridWidth
                let gy = index / gridWidth
                let x = rect.x + gx * stride
                let y = rect.y + gy * stride

                count += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                if gx > 0 {
                    let next = index - 1
                    if mask[next], !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if gx + 1 < gridWidth {
                    let next = index + 1
                    if mask[next], !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if gy > 0 {
                    let next = index - gridWidth
                    if mask[next], !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if gy + 1 < gridHeight {
                    let next = index + gridWidth
                    if mask[next], !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }

            components.append(ColorBlob(count: count, minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }

        return components
    }

    private func colorBlob(in image: RGBImage, region: RectConfig, rule: ColorRuleConfig, stride: Int) -> ColorBlob? {
        let rect = pixelRegion(region: region, regionRatio: nil, width: image.width, height: image.height)
        var count = 0
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        let endX = min(image.width, rect.x + rect.width)
        let endY = min(image.height, rect.y + rect.height)
        guard rect.x < endX, rect.y < endY else { return nil }

        var y = rect.y
        while y < endY {
            var x = rect.x
            while x < endX {
                let color = image.rgbAt(x: x, y: y)
                if matchesColor(r: color.r, g: color.g, b: color.b, rule: rule) {
                    count += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
                x += stride
            }
            y += stride
        }

        guard count > 0 else { return nil }
        return ColorBlob(count: count, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func matchesColor(r: UInt8, g: UInt8, b: UInt8, rule: ColorRuleConfig) -> Bool {
        if (rule.mode ?? "hsv").lowercased() == "rgb" {
            let lower = rule.lower ?? [0, 0, 0]
            let upper = rule.upper ?? [255, 255, 255]
            guard lower.count >= 3, upper.count >= 3 else { return false }
            return Int(r) >= lower[0] && Int(r) <= upper[0]
                && Int(g) >= lower[1] && Int(g) <= upper[1]
                && Int(b) >= lower[2] && Int(b) <= upper[2]
        }

        let hsv = rgbToHSV(r: r, g: g, b: b)
        let hueRange = rule.hue ?? [0, 360]
        let saturationRange = rule.saturation ?? [0, 1]
        let brightnessRange = rule.brightness ?? [0, 1]
        guard hueRange.count >= 2, saturationRange.count >= 2, brightnessRange.count >= 2 else {
            return false
        }

        return valueInHueRange(hsv.h, min: hueRange[0], max: hueRange[1])
            && hsv.s >= saturationRange[0] && hsv.s <= saturationRange[1]
            && hsv.v >= brightnessRange[0] && hsv.v <= brightnessRange[1]
    }

    private func rgbToHSV(r: UInt8, g: UInt8, b: UInt8) -> (h: Double, s: Double, v: Double) {
        let red = Double(r) / 255.0
        let green = Double(g) / 255.0
        let blue = Double(b) / 255.0
        let maxValue = max(red, max(green, blue))
        let minValue = min(red, min(green, blue))
        let delta = maxValue - minValue

        var hue = 0.0
        if delta != 0 {
            if maxValue == red {
                hue = 60.0 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxValue == green {
                hue = 60.0 * (((blue - red) / delta) + 2.0)
            } else {
                hue = 60.0 * (((red - green) / delta) + 4.0)
            }
        }
        if hue < 0 {
            hue += 360.0
        }

        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    private func valueInHueRange(_ value: Double, min: Double, max: Double) -> Bool {
        if min <= max {
            return value >= min && value <= max
        }
        return value >= min || value <= max
    }

    private func bestMatch(
        template: GrayImage,
        name: String,
        in source: GrayImage,
        region: RectConfig?,
        regionRatio: RatioRectConfig? = nil,
        matchStride: Int,
        pixelStride: Int
    ) -> MatchResult? {
        guard template.width <= source.width, template.height <= source.height else {
            return nil
        }

        let searchRegion = pixelRegion(region: region, regionRatio: regionRatio, width: source.width, height: source.height)
        let rawX = max(0, searchRegion.x)
        let rawY = max(0, searchRegion.y)
        let rawWidth = max(0, searchRegion.width)
        let rawHeight = max(0, searchRegion.height)

        let startX = min(rawX, source.width - 1)
        let startY = min(rawY, source.height - 1)
        let endX = min(source.width - template.width, rawX + rawWidth - template.width)
        let endY = min(source.height - template.height, rawY + rawHeight - template.height)

        guard endX >= startX, endY >= startY else { return nil }

        var bestScore = -Double.infinity
        var bestX = startX
        var bestY = startY

        var y = startY
        while y <= endY {
            var x = startX
            while x <= endX {
                let score = similarityScore(source: source, template: template, x: x, y: y, pixelStride: pixelStride)
                if score > bestScore {
                    bestScore = score
                    bestX = x
                    bestY = y
                }
                x += matchStride
            }
            y += matchStride
        }

        return MatchResult(name: name, score: bestScore, x: bestX, y: bestY, width: template.width, height: template.height)
    }

    private func similarityScore(source: GrayImage, template: GrayImage, x: Int, y: Int, pixelStride: Int) -> Double {
        var sumAbsDiff = 0
        var count = 0

        var ty = 0
        while ty < template.height {
            let sourceBase = (y + ty) * source.width + x
            let templateBase = ty * template.width
            var tx = 0
            while tx < template.width {
                let sourceValue = Int(source.pixels[sourceBase + tx])
                let templateValue = Int(template.pixels[templateBase + tx])
                sumAbsDiff += abs(sourceValue - templateValue)
                count += 1
                tx += pixelStride
            }
            ty += pixelStride
        }

        guard count > 0 else { return 0 }
        let averageDiff = Double(sumAbsDiff) / Double(count)
        return max(0, 1.0 - averageDiff / 255.0)
    }

    private func perform(actions: [ActionConfig], window: WindowInfo, image: GrayImage, match: MatchResult?, dryRun: Bool) throws {
        for action in actions {
            switch action.type {
            case "keyTap":
                guard let key = action.key else { try throwError("keyTap action requires key") }
                if dryRun {
                    print("  dry-run keyTap \(key)")
                } else {
                    try tapKey(key, durationMs: action.durationMs ?? 40)
                }
            case "mouseClick":
                if dryRun {
                    print("  dry-run mouseClick")
                } else {
                    clickMouse(
                        buttonName: action.button ?? "left",
                        window: window,
                        image: image,
                        match: match,
                        xOffset: action.xOffset ?? 0,
                        yOffset: action.yOffset ?? 0
                    )
                }
            case "delay":
                let delay = Double(action.durationMs ?? 100) / 1000.0
                Thread.sleep(forTimeInterval: delay)
            default:
                try throwError("unsupported action type: \(action.type)")
            }
        }
    }

    private func tapKey(_ keyName: String, durationMs: Int) throws {
        guard let keyCode = keyCode(for: keyName) else {
            try throwError("unsupported key: \(keyName)")
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        postEvent(down)
        Thread.sleep(forTimeInterval: Double(max(10, durationMs)) / 1000.0)
        postEvent(up)
    }

    private func keyDown(_ keyName: String) throws {
        guard let keyCode = keyCode(for: keyName) else {
            try throwError("unsupported key: \(keyName)")
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        postEvent(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true))
    }

    private func keyUp(_ keyName: String) throws {
        guard let keyCode = keyCode(for: keyName) else {
            try throwError("unsupported key: \(keyName)")
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        postEvent(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false))
    }

    private func postEvent(_ event: CGEvent?) {
        guard let event else { return }
        if let inputTargetPID, inputTargetPID > 0 {
            event.postToPid(inputTargetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func clickMouse(
        buttonName: String,
        window: WindowInfo,
        image: GrayImage,
        match: MatchResult?,
        xOffset: Double,
        yOffset: Double
    ) {
        let pixelX = Double(match?.centerX ?? image.width / 2)
        let pixelY = Double(match?.centerY ?? image.height / 2)
        let scaleX = window.bounds.width / CGFloat(image.width)
        let scaleY = window.bounds.height / CGFloat(image.height)
        let point = CGPoint(
            x: window.bounds.minX + CGFloat(pixelX) * scaleX + CGFloat(xOffset),
            y: window.bounds.minY + CGFloat(pixelY) * scaleY + CGFloat(yOffset)
        )

        let normalizedButton = buttonName.lowercased()
        let button: CGMouseButton = normalizedButton == "right" ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        let source = CGEventSource(stateID: .combinedSessionState)

        postEvent(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button))
        postEvent(CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button))
        Thread.sleep(forTimeInterval: 0.04)
        postEvent(CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button))
    }

    private func clickMouseAtRatio(
        buttonName: String,
        window: WindowInfo,
        imageWidth: Int,
        imageHeight: Int,
        xRatio: Double,
        yRatio: Double
    ) {
        let pixelX = Double(imageWidth) * xRatio
        let pixelY = Double(imageHeight) * yRatio
        let scaleX = window.bounds.width / CGFloat(imageWidth)
        let scaleY = window.bounds.height / CGFloat(imageHeight)
        let point = CGPoint(
            x: window.bounds.minX + CGFloat(pixelX) * scaleX,
            y: window.bounds.minY + CGFloat(pixelY) * scaleY
        )

        let normalizedButton = buttonName.lowercased()
        let button: CGMouseButton = normalizedButton == "right" ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        let source = CGEventSource(stateID: .combinedSessionState)

        postEvent(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button))
        postEvent(CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button))
        Thread.sleep(forTimeInterval: 0.04)
        postEvent(CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button))
    }

    private func clickMouseAtPixel(
        buttonName: String,
        window: WindowInfo,
        imageWidth: Int,
        imageHeight: Int,
        pixelX: Double,
        pixelY: Double
    ) {
        let scaleX = window.bounds.width / CGFloat(imageWidth)
        let scaleY = window.bounds.height / CGFloat(imageHeight)
        let point = CGPoint(
            x: window.bounds.minX + CGFloat(pixelX) * scaleX,
            y: window.bounds.minY + CGFloat(pixelY) * scaleY
        )

        let normalizedButton = buttonName.lowercased()
        let button: CGMouseButton = normalizedButton == "right" ? .right : .left
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        let source = CGEventSource(stateID: .combinedSessionState)

        postEvent(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button))
        postEvent(CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button))
        Thread.sleep(forTimeInterval: 0.04)
        postEvent(CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button))
    }

    private func pixelRegion(region: RectConfig?, regionRatio: RatioRectConfig?, width: Int, height: Int) -> RectConfig {
        if let region {
            return clampRegion(region, width: width, height: height)
        }

        if let regionRatio {
            let x = Int((regionRatio.x * Double(width)).rounded())
            let y = Int((regionRatio.y * Double(height)).rounded())
            let w = Int((regionRatio.width * Double(width)).rounded())
            let h = Int((regionRatio.height * Double(height)).rounded())
            return clampRegion(RectConfig(x: x, y: y, width: w, height: h), width: width, height: height)
        }

        return RectConfig(x: 0, y: 0, width: width, height: height)
    }

    private func clampRegion(_ region: RectConfig, width: Int, height: Int) -> RectConfig {
        let x = min(max(0, region.x), max(0, width - 1))
        let y = min(max(0, region.y), max(0, height - 1))
        let endX = min(width, max(x + 1, region.x + region.width))
        let endY = min(height, max(y + 1, region.y + region.height))
        return RectConfig(x: x, y: y, width: max(1, endX - x), height: max(1, endY - y))
    }

    private func scaledDeadzone(fish: FishConfig, width: Int) -> Double {
        let base = fish.deadzonePx ?? 15.0
        return max(1.0, base * Double(width) / 1280.0)
    }

    private func adaptiveDeadzone(fish: FishConfig, width: Int, greenWidth: Int?) -> Double {
        let base = scaledDeadzone(fish: fish, width: width)
        guard let greenWidth, greenWidth > 0 else { return base }

        let factor = min(0.45, max(0.05, fish.adaptiveDeadzoneFactor ?? 0.16))
        let minimum = max(3.0, 4.0 * Double(width) / 1280.0)
        let greenLimited = max(minimum, Double(greenWidth) * factor)
        return min(base, greenLimited)
    }

    private func scaledPxPerSecond(fish: FishConfig, width: Int) -> Double {
        let base = fish.pxPerSecondAt1280 ?? 168.0
        return max(1.0, base * Double(width) / 1280.0)
    }

    private func holdDurationMs(offset: Double, fish: FishConfig, width: Int) -> Int {
        let factor = fish.factor ?? 1.4
        let floorMs = fish.floorMs ?? 80
        let capMs = fish.capMs ?? 700
        let baseMs = abs(offset) / scaledPxPerSecond(fish: fish, width: width) * 1000.0
        return min(capMs, max(floorMs, Int((baseMs * factor).rounded())))
    }

    private func adjustedBarOffset(
        bar: FishingBarDetection,
        previous: FishingBarControlSample?,
        fish: FishConfig,
        width: Int,
        now: Date
    ) -> Double {
        guard let previous else { return bar.offset }

        let dt = now.timeIntervalSince(previous.timestamp)
        guard dt >= 0.006, dt <= 0.25 else { return bar.offset }

        let cursorVelocity = (bar.cursor.centerX - previous.bar.cursor.centerX) / dt
        let greenVelocity = (bar.green.centerX - previous.bar.green.centerX) / dt
        let relativeVelocity = cursorVelocity - greenVelocity
        let leadSeconds = Double(max(0, fish.predictionLeadMs ?? 70)) / 1000.0
        guard leadSeconds > 0 else { return bar.offset }

        let scaledMaxPrediction = max(0.0, (fish.predictionMaxPxAt1280 ?? 70.0) * Double(width) / 1280.0)
        let greenLimitedPrediction = max(4.0, Double(bar.green.width) * 0.45)
        let maxPrediction = min(scaledMaxPrediction, greenLimitedPrediction)
        let prediction = min(max(relativeVelocity * leadSeconds, -maxPrediction), maxPrediction)
        return bar.offset + prediction
    }

    private func barActionName(offset: Double, fish: FishConfig, width: Int, greenWidth: Int? = nil) -> String {
        let deadzone = adaptiveDeadzone(fish: fish, width: width, greenWidth: greenWidth)
        let leftKey = fish.invertControls ?? false ? "D" : "A"
        let rightKey = fish.invertControls ?? false ? "A" : "D"
        if offset > deadzone {
            return leftKey
        }
        if offset < -deadzone {
            return rightKey
        }
        return "-"
    }

    private func holdSwitchKey(offset: Double, fish: FishConfig, width: Int, greenWidth: Int? = nil, heldKey: String?) -> String? {
        let enterDeadzone = adaptiveDeadzone(fish: fish, width: width, greenWidth: greenWidth)
        let factor = min(1.0, max(0.0, fish.releaseDeadzoneFactor ?? 0.60))
        let releaseDeadzone = max(1.0, enterDeadzone * factor)
        let leftKey = fish.invertControls ?? false ? "d" : "a"
        let rightKey = fish.invertControls ?? false ? "a" : "d"

        switch heldKey {
        case leftKey:
            if offset < -enterDeadzone { return rightKey }
            return offset > releaseDeadzone ? leftKey : nil
        case rightKey:
            if offset > enterDeadzone { return leftKey }
            return offset < -releaseDeadzone ? rightKey : nil
        default:
            if offset > enterDeadzone { return leftKey }
            if offset < -enterDeadzone { return rightKey }
            return nil
        }
    }

    private func keyCode(for name: String) -> CGKeyCode? {
        switch name.lowercased() {
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        case "]": return 30
        case "o": return 31
        case "u": return 32
        case "[": return 33
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "'": return 39
        case "k": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "n": return 45
        case "m": return 46
        case ".": return 47
        case "space": return 49
        case "return", "enter": return 36
        case "escape", "esc": return 53
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        default: return nil
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func parseSize(_ rawValue: String) throws -> (width: Int, height: Int) {
        let separators = CharacterSet(charactersIn: "xX*×")
        let parts = rawValue.components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0 else {
            try throwError("invalid size '\(rawValue)'; use <width>x<height>, for example 2560x1440")
        }
        return (width, height)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
