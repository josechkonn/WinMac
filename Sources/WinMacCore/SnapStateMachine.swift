import CoreGraphics
import Foundation

public enum SnapStateMachine {
    public static let defaultTolerance: CGFloat = 18.0

    /// Computes exact pixel-aligned target frame for a non-floating snap state inside `visibleFrame`.
    public static func frame(for state: SnapState, in visibleFrame: CGRect) -> CGRect {
        let minX = visibleFrame.origin.x.rounded()
        let minY = visibleFrame.origin.y.rounded()
        let totalW = visibleFrame.size.width.rounded()
        let totalH = visibleFrame.size.height.rounded()

        let leftW = floor(totalW / 2.0)
        let rightW = totalW - leftW
        let topH = floor(totalH / 2.0)
        let bottomH = totalH - topH

        switch state {
        case .floating:
            return visibleFrame
        case .maximized:
            return CGRect(x: minX, y: minY, width: totalW, height: totalH)
        case .leftHalf:
            return CGRect(x: minX, y: minY, width: leftW, height: totalH)
        case .rightHalf:
            return CGRect(x: minX + leftW, y: minY, width: rightW, height: totalH)
        case .topHalf:
            return CGRect(x: minX, y: minY, width: totalW, height: topH)
        case .bottomHalf:
            return CGRect(x: minX, y: minY + topH, width: totalW, height: bottomH)
        case .topLeftQuarter:
            return CGRect(x: minX, y: minY, width: leftW, height: topH)
        case .bottomLeftQuarter:
            return CGRect(x: minX, y: minY + topH, width: leftW, height: bottomH)
        case .topRightQuarter:
            return CGRect(x: minX + leftW, y: minY, width: rightW, height: topH)
        case .bottomRightQuarter:
            return CGRect(x: minX + leftW, y: minY + topH, width: rightW, height: bottomH)
        }
    }

    /// Detects the effective current `SnapState` of a window.
    /// Uses remembered state if the window hasn't been manually moved since our last snap
    /// (handles windows with minimum-size constraints), otherwise falls back to geometric matching.
    public static func detectState(
        windowFrame: CGRect,
        display: DisplayFrame,
        record: WindowSnapRecord?,
        tolerance: CGFloat = defaultTolerance
    ) -> SnapState {
        if let record,
           record.displayID == display.id,
           record.lastState.isSnapped,
           framesMatch(windowFrame, record.lastAppliedFrame, tolerance: tolerance) {
            return record.lastState
        }

        let candidates: [SnapState] = [
            .maximized,
            .leftHalf,
            .rightHalf,
            .topHalf,
            .bottomHalf,
            .topLeftQuarter,
            .bottomLeftQuarter,
            .topRightQuarter,
            .bottomRightQuarter
        ]

        for state in candidates {
            let target = frame(for: state, in: display.visibleFrame)
            if framesMatch(windowFrame, target, tolerance: tolerance) {
                return state
            }
        }

        return .floating
    }

    public static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = defaultTolerance) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }

    /// Finds the nearest adjacent display in the given horizontal direction.
    public static func adjacentDisplay(
        from current: DisplayFrame,
        direction: HorizontalDirection,
        allDisplays: [DisplayFrame]
    ) -> DisplayFrame? {
        let others = allDisplays.filter { $0.id != current.id }
        let candidates = others.filter { other in
            switch direction {
            case .left:
                return other.visibleFrame.midX < current.visibleFrame.midX - 10
            case .right:
                return other.visibleFrame.midX > current.visibleFrame.midX + 10
            }
        }

        return candidates.min { a, b in
            let distA = horizontalDistance(from: current.visibleFrame, to: a.visibleFrame, direction: direction)
            let distB = horizontalDistance(from: current.visibleFrame, to: b.visibleFrame, direction: direction)
            if abs(distA - distB) > 20 {
                return distA < distB
            }
            // Tie-break by vertical alignment with current display center
            return abs(a.visibleFrame.midY - current.visibleFrame.midY) <
                   abs(b.visibleFrame.midY - current.visibleFrame.midY)
        }
    }

    private static func horizontalDistance(from current: CGRect, to other: CGRect, direction: HorizontalDirection) -> CGFloat {
        switch direction {
        case .left:
            return max(0, current.minX - other.maxX) + abs(current.midX - other.midX) * 0.01
        case .right:
            return max(0, other.minX - current.maxX) + abs(other.midX - current.midX) * 0.01
        }
    }

    /// Computes a restored floating frame, clamping it to `visibleFrame` if needed.
    public static func restoredFrame(originalFrame: CGRect?, in visibleFrame: CGRect) -> CGRect {
        guard let original = originalFrame else {
            // Fallback: 70% centered rectangle when no original frame was recorded
            let w = (visibleFrame.width * 0.70).rounded()
            let h = (visibleFrame.height * 0.75).rounded()
            let x = (visibleFrame.minX + (visibleFrame.width - w) / 2.0).rounded()
            let y = (visibleFrame.minY + (visibleFrame.height - h) / 2.0).rounded()
            return CGRect(x: x, y: y, width: w, height: h)
        }

        let w = min(original.width, visibleFrame.width)
        let h = min(original.height, visibleFrame.height)
        let x = min(max(original.origin.x, visibleFrame.minX), visibleFrame.maxX - w)
        let y = min(max(original.origin.y, visibleFrame.minY), visibleFrame.maxY - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }

    /// Computes a centered frame on `visibleFrame`.
    public static func centeredFrame(
        currentFrame: CGRect,
        currentState: SnapState,
        originalFrame: CGRect?,
        in visibleFrame: CGRect
    ) -> CGRect {
        let baseSize: CGSize
        if currentState.isSnapped, let orig = originalFrame {
            baseSize = orig.size
        } else {
            baseSize = currentFrame.size
        }
        let w = min(baseSize.width, visibleFrame.width).rounded()
        let h = min(baseSize.height, visibleFrame.height).rounded()
        let x = (visibleFrame.minX + (visibleFrame.width - w) / 2.0).rounded()
        let y = (visibleFrame.minY + (visibleFrame.height - h) / 2.0).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Core Windows 10/11 Aero Snap state machine transition.
    public static func transition(
        currentState: SnapState,
        action: SnapAction,
        currentFrame: CGRect,
        originalFrame: CGRect?,
        currentDisplay: DisplayFrame,
        allDisplays: [DisplayFrame]
    ) -> SnapOutcome {
        switch action {
        case .restore:
            guard currentState.isSnapped || originalFrame != nil else {
                return .noOp
            }
            let target = restoredFrame(originalFrame: originalFrame, in: currentDisplay.visibleFrame)
            return .move(frame: target, newState: .floating, displayID: currentDisplay.id, shouldSaveOriginal: false)

        case .center:
            let target = centeredFrame(
                currentFrame: currentFrame,
                currentState: currentState,
                originalFrame: originalFrame,
                in: currentDisplay.visibleFrame
            )
            return .move(frame: target, newState: .floating, displayID: currentDisplay.id, shouldSaveOriginal: false)

        case .left:
            return transitionLeft(
                from: currentState,
                originalFrame: originalFrame,
                currentDisplay: currentDisplay,
                allDisplays: allDisplays
            )

        case .right:
            return transitionRight(
                from: currentState,
                originalFrame: originalFrame,
                currentDisplay: currentDisplay,
                allDisplays: allDisplays
            )

        case .up:
            return transitionUp(
                from: currentState,
                currentDisplay: currentDisplay
            )

        case .down:
            return transitionDown(
                from: currentState,
                originalFrame: originalFrame,
                currentDisplay: currentDisplay
            )
        }
    }

    private static func transitionLeft(
        from state: SnapState,
        originalFrame: CGRect?,
        currentDisplay: DisplayFrame,
        allDisplays: [DisplayFrame]
    ) -> SnapOutcome {
        switch state {
        case .floating:
            return .move(
                frame: frame(for: .leftHalf, in: currentDisplay.visibleFrame),
                newState: .leftHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: true
            )

        case .maximized:
            return .move(
                frame: frame(for: .leftHalf, in: currentDisplay.visibleFrame),
                newState: .leftHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topHalf:
            return .move(
                frame: frame(for: .topLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .topLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomHalf:
            return .move(
                frame: frame(for: .bottomLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .rightHalf:
            // Windows behavior: Right Half -> Left restores to Floating first
            let target = restoredFrame(originalFrame: originalFrame, in: currentDisplay.visibleFrame)
            return .move(frame: target, newState: .floating, displayID: currentDisplay.id, shouldSaveOriginal: false)

        case .topRightQuarter:
            return .move(
                frame: frame(for: .topLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .topLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomRightQuarter:
            return .move(
                frame: frame(for: .bottomLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .leftHalf:
            guard let leftDisplay = adjacentDisplay(from: currentDisplay, direction: .left, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .rightHalf, in: leftDisplay.visibleFrame),
                newState: .rightHalf,
                displayID: leftDisplay.id,
                shouldSaveOriginal: false
            )

        case .topLeftQuarter:
            guard let leftDisplay = adjacentDisplay(from: currentDisplay, direction: .left, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .topRightQuarter, in: leftDisplay.visibleFrame),
                newState: .topRightQuarter,
                displayID: leftDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomLeftQuarter:
            guard let leftDisplay = adjacentDisplay(from: currentDisplay, direction: .left, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .bottomRightQuarter, in: leftDisplay.visibleFrame),
                newState: .bottomRightQuarter,
                displayID: leftDisplay.id,
                shouldSaveOriginal: false
            )
        }
    }

    private static func transitionRight(
        from state: SnapState,
        originalFrame: CGRect?,
        currentDisplay: DisplayFrame,
        allDisplays: [DisplayFrame]
    ) -> SnapOutcome {
        switch state {
        case .floating:
            return .move(
                frame: frame(for: .rightHalf, in: currentDisplay.visibleFrame),
                newState: .rightHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: true
            )

        case .maximized:
            return .move(
                frame: frame(for: .rightHalf, in: currentDisplay.visibleFrame),
                newState: .rightHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topHalf:
            return .move(
                frame: frame(for: .topRightQuarter, in: currentDisplay.visibleFrame),
                newState: .topRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomHalf:
            return .move(
                frame: frame(for: .bottomRightQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .leftHalf:
            // Windows behavior: Left Half -> Right restores to Floating first
            let target = restoredFrame(originalFrame: originalFrame, in: currentDisplay.visibleFrame)
            return .move(frame: target, newState: .floating, displayID: currentDisplay.id, shouldSaveOriginal: false)

        case .topLeftQuarter:
            return .move(
                frame: frame(for: .topRightQuarter, in: currentDisplay.visibleFrame),
                newState: .topRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomLeftQuarter:
            return .move(
                frame: frame(for: .bottomRightQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .rightHalf:
            guard let rightDisplay = adjacentDisplay(from: currentDisplay, direction: .right, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .leftHalf, in: rightDisplay.visibleFrame),
                newState: .leftHalf,
                displayID: rightDisplay.id,
                shouldSaveOriginal: false
            )

        case .topRightQuarter:
            guard let rightDisplay = adjacentDisplay(from: currentDisplay, direction: .right, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .topLeftQuarter, in: rightDisplay.visibleFrame),
                newState: .topLeftQuarter,
                displayID: rightDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomRightQuarter:
            guard let rightDisplay = adjacentDisplay(from: currentDisplay, direction: .right, allDisplays: allDisplays) else {
                return .noOp
            }
            return .move(
                frame: frame(for: .bottomLeftQuarter, in: rightDisplay.visibleFrame),
                newState: .bottomLeftQuarter,
                displayID: rightDisplay.id,
                shouldSaveOriginal: false
            )
        }
    }

    private static func transitionUp(
        from state: SnapState,
        currentDisplay: DisplayFrame
    ) -> SnapOutcome {
        switch state {
        case .floating:
            return .move(
                frame: frame(for: .maximized, in: currentDisplay.visibleFrame),
                newState: .maximized,
                displayID: currentDisplay.id,
                shouldSaveOriginal: true
            )

        case .maximized:
            return .move(
                frame: frame(for: .topHalf, in: currentDisplay.visibleFrame),
                newState: .topHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topHalf:
            return .noOp

        case .bottomHalf:
            return .move(
                frame: frame(for: .maximized, in: currentDisplay.visibleFrame),
                newState: .maximized,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .leftHalf:
            return .move(
                frame: frame(for: .topLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .topLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .rightHalf:
            return .move(
                frame: frame(for: .topRightQuarter, in: currentDisplay.visibleFrame),
                newState: .topRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomLeftQuarter:
            return .move(
                frame: frame(for: .leftHalf, in: currentDisplay.visibleFrame),
                newState: .leftHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .bottomRightQuarter:
            return .move(
                frame: frame(for: .rightHalf, in: currentDisplay.visibleFrame),
                newState: .rightHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topLeftQuarter, .topRightQuarter:
            return .move(
                frame: frame(for: .maximized, in: currentDisplay.visibleFrame),
                newState: .maximized,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )
        }
    }

    private static func transitionDown(
        from state: SnapState,
        originalFrame: CGRect?,
        currentDisplay: DisplayFrame
    ) -> SnapOutcome {
        switch state {
        case .floating, .bottomHalf, .bottomLeftQuarter, .bottomRightQuarter:
            return .minimize

        case .topHalf:
            return .move(
                frame: frame(for: .maximized, in: currentDisplay.visibleFrame),
                newState: .maximized,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .maximized:
            let target = restoredFrame(originalFrame: originalFrame, in: currentDisplay.visibleFrame)
            return .move(frame: target, newState: .floating, displayID: currentDisplay.id, shouldSaveOriginal: false)

        case .leftHalf:
            return .move(
                frame: frame(for: .bottomLeftQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomLeftQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .rightHalf:
            return .move(
                frame: frame(for: .bottomRightQuarter, in: currentDisplay.visibleFrame),
                newState: .bottomRightQuarter,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topLeftQuarter:
            return .move(
                frame: frame(for: .leftHalf, in: currentDisplay.visibleFrame),
                newState: .leftHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )

        case .topRightQuarter:
            return .move(
                frame: frame(for: .rightHalf, in: currentDisplay.visibleFrame),
                newState: .rightHalf,
                displayID: currentDisplay.id,
                shouldSaveOriginal: false
            )
        }
    }
}
