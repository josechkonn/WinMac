import CoreGraphics
import Foundation

public enum SnapAction: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
    case restore
    case center
}

public enum SnapState: String, CaseIterable, Equatable, Sendable {
    case floating
    case maximized
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case bottomLeftQuarter
    case topRightQuarter
    case bottomRightQuarter

    public var isSnapped: Bool {
        self != .floating
    }
}

public enum HorizontalDirection: Sendable {
    case left
    case right
}

/// Display geometry expressed in Accessibility / CoreGraphics global coordinates (origin top-left).
public struct DisplayFrame: Equatable, Sendable {
    public let id: String
    public let visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

public enum SnapOutcome: Equatable, Sendable {
    case move(frame: CGRect, newState: SnapState, displayID: String, shouldSaveOriginal: Bool)
    case minimize
    case noOp
}

/// Tracks a window's pre-snap frame and last snapped state so we can restore accurately
/// and handle apps with minimum window sizes.
public struct WindowSnapRecord: Equatable, Sendable {
    public var originalFrame: CGRect
    public var lastState: SnapState
    public var lastAppliedFrame: CGRect
    public var displayID: String

    public init(originalFrame: CGRect, lastState: SnapState, lastAppliedFrame: CGRect, displayID: String) {
        self.originalFrame = originalFrame
        self.lastState = lastState
        self.lastAppliedFrame = lastAppliedFrame
        self.displayID = displayID
    }
}
