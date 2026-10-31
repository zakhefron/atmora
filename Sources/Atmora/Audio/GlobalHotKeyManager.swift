import Carbon.HIToolbox
import Foundation
import AtmoraCore

/// A process-wide Carbon hot key. Carbon's registration API is still the
/// lightest way to provide a global shortcut without requesting Accessibility
/// permission. The registration is always balanced by an unregistration.
@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredCombo: KeyCombo?
    private var trigger: (() -> Void)?

    private(set) var lastError: String?

    init() {
        installHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func setHandler(_ handler: @escaping () -> Void) {
        trigger = handler
    }

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        guard combo.isValid else {
            lastError = "Choose a shortcut with Command, Option, or Control."
            return false
        }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x51544445), id: 1) // 'QTDE'
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers(combo.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            lastError = "That shortcut is already used by another app."
            return false
        }

        hotKeyRef = reference
        registeredCombo = combo
        lastError = nil
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredCombo = nil
    }

    var isRegistered: Bool { hotKeyRef != nil }

    fileprivate func fire() {
        trigger?()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.fire()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    private func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
