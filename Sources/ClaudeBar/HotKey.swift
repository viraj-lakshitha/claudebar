import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's RegisterEventHotKey, which does not
/// need Accessibility permission.
final class HotKey {
    static let keyC = UInt32(kVK_ANSI_C)
    static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPointer, &handlerRef) == noErr else {
            return nil
        }

        let id = EventHotKeyID(signature: OSType(0x434C_4252), id: 1) // "CLBR"
        // On failure, deinit removes the handler installed above.
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
