import CoreGraphics
import Testing
@testable import WinMacCore

@Suite("WinMac SnapStateMachine")
struct SnapStateMachineTests {
    let primary = DisplayFrame(id: "primary", visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
    let secondaryRight = DisplayFrame(id: "right", visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    let secondaryLeft = DisplayFrame(id: "left", visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let original = CGRect(x: 200, y: 150, width: 900, height: 600)

    @Test("User flow: Left -> Up (Top-Left) -> Down (Left) -> Down (Bottom-Left) -> Up (Left)")
    func userExactVerticalFlowOnLeft() {
        let displays = [primary]

        // 1. Floating + Left -> Left Half (saves original)
        let s1 = SnapStateMachine.transition(
            currentState: .floating,
            action: .left,
            currentFrame: original,
            originalFrame: nil,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(s1 == .move(
            frame: CGRect(x: 0, y: 25, width: 720, height: 875),
            newState: .leftHalf,
            displayID: "primary",
            shouldSaveOriginal: true
        ))

        // 2. Left Half + Up -> Top-Left Quarter
        let s2 = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .up,
            currentFrame: CGRect(x: 0, y: 25, width: 720, height: 875),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(s2 == .move(
            frame: CGRect(x: 0, y: 25, width: 720, height: 437),
            newState: .topLeftQuarter,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        // 3. Top-Left Quarter + Down -> Back to Left Half (2 spaces)
        let s3 = SnapStateMachine.transition(
            currentState: .topLeftQuarter,
            action: .down,
            currentFrame: CGRect(x: 0, y: 25, width: 720, height: 437),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(s3 == .move(
            frame: CGRect(x: 0, y: 25, width: 720, height: 875),
            newState: .leftHalf,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        // 4. Left Half + Down -> Bottom-Left Quarter
        let s4 = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .down,
            currentFrame: CGRect(x: 0, y: 25, width: 720, height: 875),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(s4 == .move(
            frame: CGRect(x: 0, y: 462, width: 720, height: 438),
            newState: .bottomLeftQuarter,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        // 5. Bottom-Left Quarter + Up -> Back to Left Half
        let s5 = SnapStateMachine.transition(
            currentState: .bottomLeftQuarter,
            action: .up,
            currentFrame: CGRect(x: 0, y: 462, width: 720, height: 438),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(s5 == .move(
            frame: CGRect(x: 0, y: 25, width: 720, height: 875),
            newState: .leftHalf,
            displayID: "primary",
            shouldSaveOriginal: false
        ))
    }

    @Test("Windows horizontal flow: Left Half -> Right restores to Floating -> Right goes to Right Half")
    func horizontalRestoreBeforeOppositeHalf() {
        let displays = [primary]

        let toFloating = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .right,
            currentFrame: SnapStateMachine.frame(for: .leftHalf, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(toFloating == .move(
            frame: original,
            newState: .floating,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        let toRightHalf = SnapStateMachine.transition(
            currentState: .floating,
            action: .right,
            currentFrame: original,
            originalFrame: nil,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(toRightHalf == .move(
            frame: CGRect(x: 720, y: 25, width: 720, height: 875),
            newState: .rightHalf,
            displayID: "primary",
            shouldSaveOriginal: true
        ))
    }

    @Test("Maximize and Minimize flows match Windows 10/11")
    func maximizeAndMinimizeFlows() {
        let displays = [primary]

        let maxOutcome = SnapStateMachine.transition(
            currentState: .floating,
            action: .up,
            currentFrame: original,
            originalFrame: nil,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(maxOutcome == .move(
            frame: primary.visibleFrame,
            newState: .maximized,
            displayID: "primary",
            shouldSaveOriginal: true
        ))

        let restoreFromMax = SnapStateMachine.transition(
            currentState: .maximized,
            action: .down,
            currentFrame: primary.visibleFrame,
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(restoreFromMax == .move(
            frame: original,
            newState: .floating,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        let minFromFloating = SnapStateMachine.transition(
            currentState: .floating,
            action: .down,
            currentFrame: original,
            originalFrame: nil,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(minFromFloating == .minimize)

        let minFromBottomQuarter = SnapStateMachine.transition(
            currentState: .bottomRightQuarter,
            action: .down,
            currentFrame: SnapStateMachine.frame(for: .bottomRightQuarter, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(minFromBottomQuarter == .minimize)

        let maxFromTopQuarter = SnapStateMachine.transition(
            currentState: .topLeftQuarter,
            action: .up,
            currentFrame: SnapStateMachine.frame(for: .topLeftQuarter, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(maxFromTopQuarter == .move(
            frame: primary.visibleFrame,
            newState: .maximized,
            displayID: "primary",
            shouldSaveOriginal: false
        ))
    }

    @Test("Multi-monitor jumping from screen edges")
    func multiMonitorTransitions() {
        let displays = [secondaryLeft, primary, secondaryRight]

        // Right Half on primary + Right -> Left Half on right monitor
        let jumpRight = SnapStateMachine.transition(
            currentState: .rightHalf,
            action: .right,
            currentFrame: SnapStateMachine.frame(for: .rightHalf, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(jumpRight == .move(
            frame: CGRect(x: 1440, y: 0, width: 960, height: 1080),
            newState: .leftHalf,
            displayID: "right",
            shouldSaveOriginal: false
        ))

        // Left Half on primary + Left -> Right Half on left monitor
        let jumpLeft = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .left,
            currentFrame: SnapStateMachine.frame(for: .leftHalf, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(jumpLeft == .move(
            frame: CGRect(x: -960, y: 0, width: 960, height: 1080),
            newState: .rightHalf,
            displayID: "left",
            shouldSaveOriginal: false
        ))

        // Leftmost display + Left -> noOp
        let edgeStop = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .left,
            currentFrame: SnapStateMachine.frame(for: .leftHalf, in: secondaryLeft.visibleFrame),
            originalFrame: original,
            currentDisplay: secondaryLeft,
            allDisplays: displays
        )
        #expect(edgeStop == .noOp)
    }

    @Test("Restore and Center extra shortcuts")
    func restoreAndCenter() {
        let displays = [primary]

        let restored = SnapStateMachine.transition(
            currentState: .topRightQuarter,
            action: .restore,
            currentFrame: SnapStateMachine.frame(for: .topRightQuarter, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(restored == .move(
            frame: original,
            newState: .floating,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        let centered = SnapStateMachine.transition(
            currentState: .leftHalf,
            action: .center,
            currentFrame: SnapStateMachine.frame(for: .leftHalf, in: primary.visibleFrame),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        // Original size 900x600 centered in (0, 25, 1440, 875) -> x=270, y=25+137.5=163
        #expect(centered == .move(
            frame: CGRect(x: 270, y: 163, width: 900, height: 600),
            newState: .floating,
            displayID: "primary",
            shouldSaveOriginal: false
        ))
    }

    @Test("Manual drag resets remembered snapped state to floating")
    func manualDragDetection() {
        let record = WindowSnapRecord(
            originalFrame: original,
            lastState: .leftHalf,
            lastAppliedFrame: CGRect(x: 0, y: 25, width: 720, height: 875),
            displayID: "primary"
        )
        // User manually dragged window away from left half
        let draggedFrame = CGRect(x: 350, y: 200, width: 720, height: 600)
        let detected = SnapStateMachine.detectState(
            windowFrame: draggedFrame,
            display: primary,
            record: record
        )
        #expect(detected == .floating)
    }

    @Test("SnapAssistPolicy offers opposite half or all remaining empty quarters")
    func snapAssistOffers() {
        // After snapping Left Half with no window in Right Half -> offers Right Half
        let rightOffers = SnapAssistPolicy.offers(
            afterSnapping: .leftHalf,
            on: primary,
            otherWindowFrames: [original]
        )
        #expect(rightOffers.map(\.targetState) == [.rightHalf])
        #expect(rightOffers.first?.targetFrame == SnapStateMachine.frame(for: .rightHalf, in: primary.visibleFrame))

        // If Right Half is already occupied -> returns empty
        let rightOccupied = SnapAssistPolicy.offers(
            afterSnapping: .leftHalf,
            on: primary,
            otherWindowFrames: [SnapStateMachine.frame(for: .rightHalf, in: primary.visibleFrame)]
        )
        #expect(rightOccupied.isEmpty)

        // After snapping Top-Left Quarter -> offers all 3 remaining empty quarters
        let quarterOffers = SnapAssistPolicy.offers(
            afterSnapping: .topLeftQuarter,
            on: primary,
            otherWindowFrames: [original]
        )
        #expect(quarterOffers.map(\.targetState) == [.topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter])

        // If Bottom-Left is already occupied -> offers only the other 2 empty quarters
        let remainingTwo = SnapAssistPolicy.offers(
            afterSnapping: .topLeftQuarter,
            on: primary,
            otherWindowFrames: [SnapStateMachine.frame(for: .bottomLeftQuarter, in: primary.visibleFrame)]
        )
        #expect(remainingTwo.map(\.targetState) == [.topRightQuarter, .bottomRightQuarter])

        // Maximized never triggers Snap Assist
        #expect(SnapAssistPolicy.offers(afterSnapping: .maximized, on: primary, otherWindowFrames: [original]).isEmpty)

        // Top Half offers Bottom Half
        let bottomOffer = SnapAssistPolicy.offers(afterSnapping: .topHalf, on: primary, otherWindowFrames: [original])
        #expect(bottomOffer.map(\.targetState) == [.bottomHalf])
    }

    @Test("Double Up: Floating -> Maximized -> Top Half -> Down returns to Maximized")
    func doubleUpToTopHalf() {
        let displays = [primary]

        // 1st Up: Maximized
        let firstUp = SnapStateMachine.transition(
            currentState: .floating,
            action: .up,
            currentFrame: original,
            originalFrame: nil,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(firstUp == .move(
            frame: primary.visibleFrame,
            newState: .maximized,
            displayID: "primary",
            shouldSaveOriginal: true
        ))

        // 2nd Up: Top Half
        let secondUp = SnapStateMachine.transition(
            currentState: .maximized,
            action: .up,
            currentFrame: primary.visibleFrame,
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(secondUp == .move(
            frame: CGRect(x: 0, y: 25, width: 1440, height: 437),
            newState: .topHalf,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        // Down from Top Half: back to Maximized
        let downToMax = SnapStateMachine.transition(
            currentState: .topHalf,
            action: .down,
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 437),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(downToMax == .move(
            frame: primary.visibleFrame,
            newState: .maximized,
            displayID: "primary",
            shouldSaveOriginal: false
        ))

        // Left from Top Half: Top-Left Quarter
        let leftFromTop = SnapStateMachine.transition(
            currentState: .topHalf,
            action: .left,
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 437),
            originalFrame: original,
            currentDisplay: primary,
            allDisplays: displays
        )
        #expect(leftFromTop == .move(
            frame: CGRect(x: 0, y: 25, width: 720, height: 437),
            newState: .topLeftQuarter,
            displayID: "primary",
            shouldSaveOriginal: false
        ))
    }
}
