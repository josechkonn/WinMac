import AppKit
import ApplicationServices
import Foundation

// Standard macOS Accessibility bridge to get the exact CGWindowID of an AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowKey: Hashable, Sendable {
    let pid: pid_t
    let windowID: CGWindowID
}

final class FocusedWindow {
    let element: AXUIElement
    let appElement: AXUIElement
    let pid: pid_t
    let appName: String
    let key: WindowKey

    init(element: AXUIElement, appElement: AXUIElement, pid: pid_t, appName: String, windowID: CGWindowID) {
        self.element = element
        self.appElement = appElement
        self.pid = pid
        self.appName = appName
        self.key = WindowKey(pid: pid, windowID: windowID)
    }

    func currentFrame() -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    func isFullScreen() -> Bool {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value)
        if status == .success, let boolVal = value as? Bool {
            return boolVal
        }
        return false
    }

    /// Sets the window frame safely:
    /// 1. Temporarily disables AXEnhancedUserInterface (fixes Electron/Chromium/Safari resize bugs).
    /// 2. Shrinks size FIRST when target is smaller than current (prevents screen-edge clamping on move).
    /// 3. Moves to target origin, then sets target size.
    /// 4. Verifies readback and applies one corrective pass only if needed.
    @discardableResult
    func setFrame(_ target: CGRect) -> CGRect? {
        let wasEnhancedUI = getEnhancedUI()
        if wasEnhancedUI {
            setEnhancedUI(false)
        }
        defer {
            if wasEnhancedUI {
                setEnhancedUI(true)
            }
        }

        let before = currentFrame()
        let isShrinking = before.map {
            target.width < $0.width - 1 || target.height < $0.height - 1
        } ?? true

        if isShrinking {
            writeSize(target.size)
            writePosition(target.origin)
            writeSize(target.size)
        } else {
            writePosition(target.origin)
            writeSize(target.size)
        }

        // Verify and do one corrective pass if origin or size is still off
        if let after = currentFrame() {
            let originOff = abs(after.origin.x - target.origin.x) > 2 || abs(after.origin.y - target.origin.y) > 2
            let sizeOff = abs(after.size.width - target.size.width) > 2 || abs(after.size.height - target.size.height) > 2
            if originOff {
                writePosition(target.origin)
            }
            if sizeOff {
                writeSize(target.size)
            }
            if originOff || sizeOff {
                return currentFrame() ?? after
            }
            return after
        }

        return currentFrame()
    }

    func minimize() -> Bool {
        let status = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return status == .success
    }

    @discardableResult
    private func writePosition(_ point: CGPoint) -> AXError {
        var pt = point
        guard let axVal = AXValueCreate(.cgPoint, &pt) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axVal)
    }

    @discardableResult
    private func writeSize(_ size: CGSize) -> AXError {
        var sz = size
        guard let axVal = AXValueCreate(.cgSize, &sz) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axVal)
    }

    private func getEnhancedUI() -> Bool {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &value)
        if status == .success, let boolVal = value as? Bool {
            return boolVal
        }
        return false
    }

    private func setEnhancedUI(_ enabled: Bool) {
        AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            enabled ? kCFBooleanTrue : kCFBooleanFalse
        )
    }
}

@MainActor
final class AXWindowController {
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    func focusedWindow() -> FocusedWindow? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        let appElement: AXUIElement
        var pid: pid_t = 0

        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
           let ref = appRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            appElement = ref as! AXUIElement
            AXUIElementGetPid(appElement, &pid)
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            pid = frontApp.processIdentifier
            appElement = AXUIElementCreateApplication(pid)
        } else {
            return nil
        }

        if pid == ProcessInfo.processInfo.processIdentifier {
            return nil
        }

        var winRef: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRef)
        if status != .success || winRef == nil {
            status = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &winRef)
        }

        guard status == .success, let ref = winRef, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowElement = ref as! AXUIElement

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role != (kAXWindowRole as String) {
            return nil
        }

        var cgWindowID: CGWindowID = 0
        let idStatus = _AXUIElementGetWindow(windowElement, &cgWindowID)
        if idStatus != .success || cgWindowID == 0 {
            cgWindowID = CGWindowID(truncatingIfNeeded: CFHash(windowElement))
        }

        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid:\(pid)"
        return FocusedWindow(
            element: windowElement,
            appElement: appElement,
            pid: pid,
            appName: appName,
            windowID: cgWindowID
        )
    }
}
