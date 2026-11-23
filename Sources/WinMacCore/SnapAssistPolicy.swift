import CoreGraphics
import Foundation

public struct SnapAssistOffer: Equatable, Hashable, Sendable {
    public let targetState: SnapState
    public let targetFrame: CGRect
    public let display: DisplayFrame

    public init(targetState: SnapState, targetFrame: CGRect, display: DisplayFrame) {
        self.targetState = targetState
        self.targetFrame = targetFrame
        self.display = display
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(targetState)
        hasher.combine(display.id)
    }
}

public enum SnapAssistPolicy {
    /// Returns all remaining empty zones to offer Snap Assist after snapping a window to `snappedState`.
    /// - For halves: returns the opposite half (if unoccupied).
    /// - For quarters: returns up to all 3 remaining unoccupied quarters so the user can fill all 4 corners.
    public static func offers(
        afterSnapping snappedState: SnapState,
        on display: DisplayFrame,
        otherWindowFrames: [CGRect],
        tolerance: CGFloat = SnapStateMachine.defaultTolerance
    ) -> [SnapAssistOffer] {
        let candidateStates: [SnapState]
        switch snappedState {
        case .leftHalf:
            candidateStates = [.rightHalf]
        case .rightHalf:
            candidateStates = [.leftHalf]
        case .topHalf:
            candidateStates = [.bottomHalf]
        case .bottomHalf:
            candidateStates = [.topHalf]
        case .topLeftQuarter:
            candidateStates = [.topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        case .bottomLeftQuarter:
            candidateStates = [.bottomRightQuarter, .topLeftQuarter, .topRightQuarter]
        case .topRightQuarter:
            candidateStates = [.topLeftQuarter, .bottomRightQuarter, .bottomLeftQuarter]
        case .bottomRightQuarter:
            candidateStates = [.bottomLeftQuarter, .topRightQuarter, .topLeftQuarter]
        case .floating, .maximized:
            return []
        }

        return candidateStates.compactMap { state in
            let zoneFrame = SnapStateMachine.frame(for: state, in: display.visibleFrame)
            let isAlreadyOccupied = otherWindowFrames.contains { frame in
                SnapStateMachine.framesMatch(frame, zoneFrame, tolerance: tolerance)
            }
            guard !isAlreadyOccupied else { return nil }
            return SnapAssistOffer(targetState: state, targetFrame: zoneFrame, display: display)
        }
    }
}
