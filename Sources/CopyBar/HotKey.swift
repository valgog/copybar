import Carbon
import CopyBarCore

/// A system-wide shortcut registered through Carbon, which needs no
/// Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(_ spec: HotKeySpec, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return nil }

        var modifiers: UInt32 = 0
        if spec.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let id = EventHotKeyID(signature: OSType(0x4350_4252), id: 1) // "CPBR"
        let registered = RegisterEventHotKey(spec.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
