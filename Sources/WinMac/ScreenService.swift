import AppKit
import CoreGraphics
import WinMacCore

@MainActor
final class ScreenService {
    /// Returns all online screens converted into Accessibility/CoreGraphics global coordinates (origin top-left).
    func allDisplays() -> [DisplayFrame] {
        guard let primaryHeight = primaryScreenHeight() else { return [] }

        return NSScreen.screens.compactMap { screen in
            guard let displayID = screenID(for: screen) else { return nil }
            let axVisible = cocoaToAX(screen.visibleFrame, primaryHeight: primaryHeight)
            return DisplayFrame(id: String(displayID), visibleFrame: axVisible)
        }
    }

    /// Finds the display that contains the largest portion of `windowFrame`,
    /// falling back to the display containing its center or the primary display.
    func display(for windowFrame: CGRect, in displays: [DisplayFrame]) -> DisplayFrame? {
        guard !displays.isEmpty else { return nil }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)

        // Pick display with largest intersection area
        var bestDisplay: DisplayFrame?
        var bestArea: CGFloat = 0

        for display in displays {
            let intersection = display.visibleFrame.intersection(windowFrame)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestDisplay = display
                }
            }
        }

        if let bestDisplay {
            return bestDisplay
        }

        // Fallback: closest display center
        return displays.min { a, b in
            hypot(a.visibleFrame.midX - center.x, a.visibleFrame.midY - center.y) <
            hypot(b.visibleFrame.midX - center.x, b.visibleFrame.midY - center.y)
        }
    }

    private func primaryScreenHeight() -> CGFloat? {
        // In AppKit, screens.first is always the screen with origin (0, 0) (the primary display with menu bar).
        NSScreen.screens.first?.frame.height
    }

    private func cocoaToAX(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        let axY = primaryHeight - rect.origin.y - rect.size.height
        return CGRect(x: rect.origin.x, y: axY, width: rect.size.width, height: rect.size.height)
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
