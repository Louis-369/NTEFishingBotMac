import Foundation
import Combine
import CoreGraphics
import ApplicationServices

final class WindowProvider: ObservableObject {
    @Published var windows: [WindowCandidate] = []

    func refresh() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            windows = []
            return
        }

        windows = list.compactMap { item in
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { return nil }
            guard let id = item[kCGWindowNumber as String] as? UInt32 else { return nil }
            let ownerPID = item[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
            let title = item[kCGWindowName as String] as? String ?? ""
            guard let boundsDict = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            guard bounds.width >= 80, bounds.height >= 80 else { return nil }
            return WindowCandidate(id: id, ownerPID: ownerPID, ownerName: ownerName, title: title, frame: bounds)
        }
    }

    func resize(_ candidate: WindowCandidate, to frame: CGRect) throws {
        guard AXIsProcessTrusted() else {
            throw WindowResizeError.accessibilityPermissionMissing
        }

        let app = AXUIElementCreateApplication(candidate.ownerPID)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let axWindows = value as? [AXUIElement], !axWindows.isEmpty else {
            throw WindowResizeError.windowListUnavailable(result)
        }

        guard let axWindow = bestAXWindow(for: candidate, in: axWindows) else {
            throw WindowResizeError.matchNotFound
        }

        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowResizeError.valueCreationFailed
        }

        let positionResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        guard positionResult == .success else {
            throw WindowResizeError.setPositionFailed(positionResult)
        }

        let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else {
            throw WindowResizeError.setSizeFailed(sizeResult)
        }
    }

    private func bestAXWindow(for candidate: WindowCandidate, in windows: [AXUIElement]) -> AXUIElement? {
        var best: (window: AXUIElement, score: CGFloat)?
        for window in windows {
            let title = stringAttribute(kAXTitleAttribute, from: window)
            let frame = frameAttributes(from: window)

            var score: CGFloat = 0
            if !candidate.title.isEmpty, title == candidate.title {
                score += 1000
            } else if !candidate.title.isEmpty, title.localizedCaseInsensitiveContains(candidate.title) {
                score += 500
            }

            if let frame {
                let distance = abs(frame.minX - candidate.frame.minX)
                    + abs(frame.minY - candidate.frame.minY)
                    + abs(frame.width - candidate.frame.width)
                    + abs(frame.height - candidate.frame.height)
                score += max(0, 400 - distance)
            }

            if best == nil || score > best!.score {
                best = (window, score)
            }
        }
        return best?.window
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func frameAttributes(from element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

enum WindowResizeError: LocalizedError {
    case accessibilityPermissionMissing
    case windowListUnavailable(AXError)
    case matchNotFound
    case valueCreationFailed
    case setPositionFailed(AXError)
    case setSizeFailed(AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "需要先允許輔助使用權限"
        case .windowListUnavailable(let error):
            return "無法取得該 App 的視窗列表：\(error)"
        case .matchNotFound:
            return "找不到可調整的 AX 視窗"
        case .valueCreationFailed:
            return "建立視窗位置/尺寸值失敗"
        case .setPositionFailed(let error):
            return "設定視窗位置失敗：\(error)"
        case .setSizeFailed(let error):
            return "設定視窗尺寸失敗：\(error)。如果遊戲在 macOS 全螢幕 Space，請先切回視窗模式"
        }
    }
}
