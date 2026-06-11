import Foundation
import Combine
import CoreGraphics

final class BotProcessController: ObservableObject {
    @Published var status: BotRunStatus = .stopped
    @Published var detection = DetectionSnapshot()
    @Published var logs = ""
    @Published var isRunning = false
    @Published var lastError: String?

    private var outputBuffer = ""
    private var pendingLogText = ""
    private var logFlushScheduled = false
    private var shouldMarkPaused = false
    private var maxFishCount = 0
    private var engineRunning = false
    private var captureRestore: StdIORestore?

    func start(configURL: URL, dryRun: Bool, maxFishCount: Int) {
        stopCurrentIfNeeded()
        logs = ""
        pendingLogText = ""
        detection = DetectionSnapshot()
        lastError = nil
        status = .waitingFishing
        isRunning = true
        shouldMarkPaused = false
        self.maxFishCount = maxFishCount

        let arguments = ["fish-run", configURL.path, dryRun ? "--dry-run" : "--live"]
        runEngineStreaming(arguments: arguments) { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.engineRunning = false
            self.captureRestore = nil
            self.flushPendingLog()
            if self.shouldMarkPaused {
                self.status = .paused
            } else if self.status != .paused {
                self.status = .stopped
            }
        }
    }

    func runProbe(configURL: URL, completion: @escaping (String) -> Void) {
        guard !engineRunning else {
            completion("engine running")
            return
        }
        runEngineBuffered(arguments: ["fish-probe", configURL.path]) { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                var snapshot = self.detection
                LogParser.parseProbe(text, detection: &snapshot)
                self.detection = snapshot
                self.appendLog(text)
                completion(text)
            }
        }
    }

    func pause() {
        requestStop(markPaused: true, reason: nil)
    }

    func stop() {
        requestStop(markPaused: false, reason: nil)
    }

    func emergencyStop(reason: String) {
        guard engineRunning || isRunning else { return }
        requestStop(markPaused: false, reason: reason)
    }

    private func consume(_ text: String) {
        appendLog(text)
        outputBuffer += text
        let parts = outputBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard outputBuffer.last == "\n" else {
            outputBuffer = String(parts.last ?? "")
            for line in parts.dropLast() {
                consumeLine(String(line))
            }
            return
        }
        outputBuffer = ""
        for line in parts where !line.isEmpty {
            consumeLine(String(line))
        }
    }

    private func consumeLine(_ line: String) {
        var nextStatus = status
        var nextDetection = detection
        let beforeCaught = nextDetection.caughtCount
        LogParser.apply(line, status: &nextStatus, detection: &nextDetection)

        status = nextStatus
        detection = nextDetection

        if maxFishCount > 0,
           nextDetection.caughtCount > beforeCaught,
           nextDetection.caughtCount >= maxFishCount {
            appendLog("\n[UI] 已達本次釣魚數量 \(maxFishCount)，暫停。\n")
            pause()
        }
    }

    private func appendLog(_ text: String) {
        pendingLogText += text
        scheduleLogFlush()
    }

    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.flushPendingLog()
        }
    }

    private func flushPendingLog() {
        guard !pendingLogText.isEmpty else {
            logFlushScheduled = false
            return
        }
        logs += pendingLogText
        pendingLogText = ""
        if logs.count > 40_000 {
            logs.removeFirst(logs.count - 40_000)
        }
        logFlushScheduled = false
    }

    private func stopCurrentIfNeeded() {
        if engineRunning {
            requestStop(markPaused: false, reason: nil)
        }
        outputBuffer = ""
    }

    private func fail(_ message: String) {
        lastError = message
        appendLog("[UI] \(message)\n")
        status = .stopped
        isRunning = false
    }

    private func requestStop(markPaused: Bool, reason: String?) {
        if let reason {
            appendLog("\n[UI] \(reason)，已送出安全停止。\n")
        }
        releaseSafetyInputs()
        guard engineRunning else {
            status = markPaused ? .paused : .stopped
            isRunning = false
            return
        }
        shouldMarkPaused = markPaused
        requestMacFishingBotInterrupt()
        status = markPaused ? .paused : .stopped
    }

    private func runEngineStreaming(arguments: [String], onFinish: @escaping () -> Void) {
        guard !engineRunning else {
            fail("engine already running")
            return
        }
        engineRunning = true
        let pipe = Pipe()
        captureRestore = redirectStdIO(to: pipe)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consume(text)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MacFishingBot().run(arguments: arguments)
            } catch {
                print("error: \(error)")
            }
            fflush(stdout)
            fflush(stderr)
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self.captureRestore?.restore()
                onFinish()
            }
        }
    }

    private func runEngineBuffered(arguments: [String], completion: @escaping (String) -> Void) {
        engineRunning = true
        let pipe = Pipe()
        let restore = redirectStdIO(to: pipe)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MacFishingBot().run(arguments: arguments)
            } catch {
                print("error: \(error)")
            }
            fflush(stdout)
            fflush(stderr)
            restore.restore()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.engineRunning = false
                completion(text)
            }
        }
    }

    private func redirectStdIO(to pipe: Pipe) -> StdIORestore {
        fflush(stdout)
        fflush(stderr)
        let oldStdout = dup(STDOUT_FILENO)
        let oldStderr = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        return StdIORestore(
            oldStdout: oldStdout,
            oldStderr: oldStderr,
            writeHandle: pipe.fileHandleForWriting
        )
    }

    private func releaseSafetyInputs() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyCode in [UInt16(0), UInt16(2), UInt16(3), UInt16(53)] {
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
        }

        let point = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)
    }
}

private struct StdIORestore {
    let oldStdout: Int32
    let oldStderr: Int32
    let writeHandle: FileHandle

    func restore() {
        fflush(stdout)
        fflush(stderr)
        dup2(oldStdout, STDOUT_FILENO)
        dup2(oldStderr, STDERR_FILENO)
        close(oldStdout)
        close(oldStderr)
        try? writeHandle.close()
    }
}
