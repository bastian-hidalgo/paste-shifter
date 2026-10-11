import Carbon

final class HotKeys {
    var onPress: ((UInt32) -> Void)?
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private(set) var failures: [String] = []

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().onPress?(id.id)
            return noErr
        }, 1, &spec, context, &handler)
        for (id, modifiers, key, label) in [
            (UInt32(1), UInt32(optionKey), UInt32(kVK_ANSI_V), "⌥V"),
            (UInt32(2), UInt32(optionKey | shiftKey), UInt32(kVK_ANSI_V), "⌥⇧V"),
            (UInt32(3), UInt32(optionKey | shiftKey), UInt32(kVK_ANSI_C), "⌥⇧C")
        ] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x50534846, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { failures.append(label) }
        }
    }
    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
