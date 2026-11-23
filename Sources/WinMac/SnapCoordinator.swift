import CoreGraphics
import Foundation
import WinMacCore

@MainActor
final class SnapCoordinator {
    private let windowController = AXWindowController()
    private let screenService = ScreenService()
    private var records: [WindowKey: WindowSnapRecord] = [:]

    var isEnabled: Bool = true

    func perform(_ action: SnapAction) {
        guard isEnabled else { return }
        guard let window = windowController.focusedWindow() else { return }
        guard !window.isFullScreen() else { return }
        guard let currentFrame = window.currentFrame() else { return }

        let displays = screenService.allDisplays()
        guard let currentDisplay = screenService.display(for: currentFrame, in: displays) else { return }

        let existingRecord = records[window.key]
        let currentState = SnapStateMachine.detectState(
            windowFrame: currentFrame,
            display: currentDisplay,
            record: existingRecord
        )

        let outcome = SnapStateMachine.transition(
            currentState: currentState,
            action: action,
            currentFrame: currentFrame,
            originalFrame: existingRecord?.originalFrame,
            currentDisplay: currentDisplay,
            allDisplays: displays
        )

        switch outcome {
        case .noOp:
            return

        case .minimize:
            _ = window.minimize()

        case let .move(targetFrame, newState, targetDisplayID, shouldSaveOriginal):
            let appliedFrame = window.setFrame(targetFrame) ?? targetFrame

            if newState == .floating {
                records.removeValue(forKey: window.key)
            } else {
                let originalFrame: CGRect
                if shouldSaveOriginal || existingRecord == nil {
                    originalFrame = currentFrame
                } else {
                    originalFrame = existingRecord!.originalFrame
                }
                records[window.key] = WindowSnapRecord(
                    originalFrame: originalFrame,
                    lastState: newState,
                    lastAppliedFrame: appliedFrame,
                    displayID: targetDisplayID
                )
            }
        }
    }
}
