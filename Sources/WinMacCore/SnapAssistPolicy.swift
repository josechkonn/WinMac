import CoreGraphics
import Foundation

public struct SnapAssistOffer: Equatable, Sendable {
    public let targetState: SnapState
    public let targetFrame: CGRect
    public let display: DisplayFrame

    public init(targetState: SnapState, targetFrame: CGRect, display: DisplayFrame) {
        self.targetState = targetState
        self.targetFrame = targetFrame
        self.display = display
    }
}

public enum SnapAssistPolicy {
    /// Determines the best remaining empty zone to offer Snap Assist after snapping a window to `snappedState`.
    /// Checks `occupiedFrames` (other visible windows on the same display) so we don't offer a zone
    /// that is already neatly filled by another window.
    public static func offer(
        afterSnapping snappedState: SnapState,
        on display: DisplayFrame,
        otherWindowFrames: [CGRect],
        tolerance: CGFloat = SnapStateMachine.defaultTolerance
    ) -> SnapAssistOffer? {
        let candidateStates: [SnapState]
        switch snappedState {
        case .leftHalf:
            candidateStates = [.rightHalf]
        case .rightHalf:
            candidateStates = [.leftHalf]
        case .topLeftQuarter:
            candidateStates = [.bottomLeftQuarter, .rightHalf, .topRightQuarter, .bottomRightQuarter]
        case .bottomLeftQuarter:
            candidateStates = [.topLeftQuarter, .rightHalf, .bottomRightQuarter, .topRightQuarter]
        case .topRightQuarter:
            candidateStates = [.bottomRightQuarter, .leftHalf, .topLeftQuarter, .bottomLeftQuarter]
        case .bottomRightQuarter:
            candidateStates = [.topRightQuarter, .leftHalf, .bottomLeftQuarter, .topLeftQuarter]
        case .floating, .maximized:
            return nil
        }

        for state in candidateStates {
            let zoneFrame = SnapStateMachine.frame(for: state, in: display.visibleFrame)
            let isAlreadyOccupied = otherWindowFrames.contains { frame in
                SnapStateMachine.framesMatch(frame, zoneFrame, tolerance: tolerance)
            }
            if !isAlreadyOccupied {
                return SnapAssistOffer(targetState: state, targetFrame: zoneFrame, display: display)
            }
        }

        return nil
    }
}
