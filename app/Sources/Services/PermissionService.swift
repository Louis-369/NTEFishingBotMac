import Foundation
import Combine
import CoreGraphics
import ApplicationServices

final class PermissionService: ObservableObject {
    @Published var screenRecordingGranted = false
    @Published var accessibilityGranted = false

    func refresh() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }
}
