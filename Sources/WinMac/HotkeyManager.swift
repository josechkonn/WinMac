import Carbon
import Foundation
import WinMacCore

@MainActor
final class HotkeyManager {
    private static let signature: OSType = 0x574D4143 // 'WMAC'

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByID: [UInt32: SnapAction] = [:]
    private var onAction: ((SnapAction) -> Void)?
    private var isRegistered = false

    func start(onAction: @escaping (SnapAction) -> Void) {
        self.onAction = onAction
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            NSLog("WinMac: Failed to install Carbon event handler: %d", installStatus)
            return
        }

        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let bindings: [(UInt32, UInt32, SnapAction)] = [
            (1, UInt32(kVK_LeftArrow), .left),
            (2, UInt32(kVK_RightArrow), .right),
            (3, UInt32(kVK_UpArrow), .up),
            (4, UInt32(kVK_DownArrow), .down),
            (5, UInt32(kVK_Delete), .restore),
            (6, UInt32(kVK_ANSI_C), .center)
        ]

        for (id, keyCode, action) in bindings {
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionByID[id] = action
            } else {
                NSLog("WinMac: Failed to register hotkey %@ (keyCode=%d): %d", action.rawValue, keyCode, status)
            }
        }

        isRegistered = true
    }

    func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        isRegistered = false
    }

    private func handleHotKey(id: UInt32) {
        guard let action = actionByID[id] else { return }
        onAction?(action)
    }
}
