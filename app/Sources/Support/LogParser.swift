import Foundation

enum LogParser {
    static func apply(_ line: String, status: inout BotRunStatus, detection: inout DetectionSnapshot) {
        if line.contains("hook prompt visible") {
            status = .waitingHook
            detection.action = "F"
            return
        }

        if line.contains("start prompt visible") {
            status = .waitingFishing
            detection.action = "F"
            return
        }

        if line.contains("prompt visible") {
            status = .waitingHook
            detection.action = "F"
            return
        }

        if line.contains("bar offset=") {
            status = .pulling
            detection.greenFound = true
            detection.cursorFound = true
            detection.offset = parseDouble(after: "offset=", in: line)
            if let hold = token(after: "hold=", in: line) {
                detection.action = hold.uppercased()
            } else if let pulse = token(after: "pulse=", in: line) {
                detection.action = pulse.uppercased()
            } else if line.contains("release") || line.contains("centered") {
                detection.action = "-"
            }
            return
        }

        if line.contains("result prompt visible") || line.contains("template result") || line.contains("fishing result") {
            status = .result
            detection.caughtCount += 1
            detection.action = "-"
            return
        }

        if line.localizedCaseInsensitiveContains("target window is not frontmost") {
            status = .waitingFishing
            detection.action = "-"
            return
        }

        if line.localizedCaseInsensitiveContains("paused:")
            || line.localizedCaseInsensitiveContains("pause condition") {
            status = .paused
            detection.action = "-"
            return
        }

        if line.contains("no actionable fishing state") || line.contains("fishing scan") {
            status = .waitingFishing
            detection.action = "-"
            return
        }

        if line.contains("stopped by Ctrl-C") {
            status = .stopped
            detection.action = "-"
        }
    }

    static func parseProbe(_ text: String, detection: inout DetectionSnapshot) {
        detection.greenFound = text.contains("PASS green")
        detection.cursorFound = text.contains("PASS cursor")
        if let offset = parseDouble(after: "offset=", in: text) {
            detection.offset = offset
        }
        if let action = token(after: "action=", in: text) {
            detection.action = action
        }
    }

    private static func parseDouble(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker) else { return nil }
        let tail = text[range.upperBound...]
        let number = tail.prefix { char in
            char == "-" || char == "." || char.isNumber
        }
        return Double(String(number))
    }

    private static func token(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let tail = text[range.upperBound...]
        let token = tail.prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }
}
