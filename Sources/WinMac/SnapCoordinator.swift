import AppKit
import CoreGraphics
import Foundation
import WinMacCore

@MainActor
final class SnapCoordinator {
    private let windowController = AXWindowController()
    private let screenService = ScreenService()
    private let windowEnumerator = WindowEnumerator()
    private let snapAssist = SnapAssistController()
    private var records: [WindowKey: WindowSnapRecord] = [:]
    private var pendingAssistTask: Task<Void, Never>?
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?

    var isEnabled: Bool = true
    var isSnapAssistEnabled: Bool = true {
        didSet {
            if !isSnapAssistEnabled {
                cancelSnapAssist()
            }
        }
    }

    func perform(_ action: SnapAction) {
        cancelSnapAssist()

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

                if isSnapAssistEnabled,
                   newState != .maximized,
                   let targetDisplay = displays.first(where: { $0.id == targetDisplayID }) {
                    scheduleSnapAssistOnModifierRelease(
                        afterSnapping: newState,
                        snappedKey: window.key,
                        on: targetDisplay
                    )
                }
            }
        }
    }

    private func cancelSnapAssist() {
        pendingAssistTask?.cancel()
        pendingAssistTask = nil
        removeFlagsMonitors()
        snapAssist.dismiss()
    }

    private func modifiersStillHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskControl) || flags.contains(.maskAlternate)
    }

    private func scheduleSnapAssistOnModifierRelease(
        afterSnapping snappedState: SnapState,
        snappedKey: WindowKey,
        on display: DisplayFrame
    ) {
        removeFlagsMonitors()
        pendingAssistTask?.cancel()

        // If user already released Control + Option, present right away
        if !modifiersStillHeld() {
            presentSnapAssist(afterSnapping: snappedState, snappedKey: snappedKey, on: display)
            return
        }

        let triggerIfReleased: @MainActor () -> Void = { [weak self] in
            guard let self, !self.modifiersStillHeld() else { return }
            self.removeFlagsMonitors()
            self.pendingAssistTask?.cancel()
            self.pendingAssistTask = nil
            self.presentSnapAssist(afterSnapping: snappedState, snappedKey: snappedKey, on: display)
        }

        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { _ in
            Task { @MainActor in
                triggerIfReleased()
            }
        }
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in
                triggerIfReleased()
            }
            return event
        }

        // Lightweight safety poll in case macOS swallows a flagsChanged event (e.g. secure input)
        pendingAssistTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(45))
                guard let self, !Task.isCancelled else { return }
                if !self.modifiersStillHeld() {
                    triggerIfReleased()
                    return
                }
            }
        }
    }

    private func presentSnapAssist(
        afterSnapping snappedState: SnapState,
        snappedKey: WindowKey,
        on display: DisplayFrame
    ) {
        guard isEnabled, isSnapAssistEnabled else { return }

        let candidates = windowEnumerator.visibleCandidates(excluding: snappedKey)
        guard !candidates.isEmpty else { return }

        let otherFrames = candidates.map(\.frame)
        let offers = SnapAssistPolicy.offers(
            afterSnapping: snappedState,
            on: display,
            otherWindowFrames: otherFrames
        )
        guard !offers.isEmpty else { return }

        snapAssist.present(
            offers: offers,
            candidates: candidates,
            screenService: screenService,
            enumerator: windowEnumerator
        ) { [weak self] candidate, chosenOffer in
            self?.placeCandidate(candidate, into: chosenOffer)
        }
    }

    private func removeFlagsMonitors() {
        if let m = flagsGlobalMonitor {
            NSEvent.removeMonitor(m)
            flagsGlobalMonitor = nil
        }
        if let m = flagsLocalMonitor {
            NSEvent.removeMonitor(m)
            flagsLocalMonitor = nil
        }
    }

    private func placeCandidate(_ candidate: WindowCandidate, into offer: SnapAssistOffer) {
        guard let targetWindow = windowController.window(for: candidate.key) else { return }
        let beforeFrame = targetWindow.currentFrame() ?? candidate.frame
        let appliedFrame = targetWindow.setFrame(offer.targetFrame) ?? offer.targetFrame
        targetWindow.raiseAndActivate()

        let existing = records[candidate.key]
        records[candidate.key] = WindowSnapRecord(
            originalFrame: existing?.originalFrame ?? beforeFrame,
            lastState: offer.targetState,
            lastAppliedFrame: appliedFrame,
            displayID: offer.display.id
        )
    }
}
