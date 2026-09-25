import Carbon.HIToolbox
import PanefulCore

/// Ctrl+Option + the arrow keys. Carbon hotkeys need no extra permission, and apps never see the keystrokes.
final class HotKeys {
    private static let keys: [(code: Int, edge: Edge)] = [
        (kVK_LeftArrow, .left), (kVK_RightArrow, .right), (kVK_UpArrow, .top), (kVK_DownArrow, .bottom),
    ]
    /// Tags Paneful's hotkeys ("Pnfl").
    private static let signature: OSType = 0x506E_666C

    private let onPress: (Edge) -> Void
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(onPress: @escaping (Edge) -> Void) {
        self.onPress = onPress
    }

    func start() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let context, id.signature == HotKeys.signature, HotKeys.keys.indices.contains(Int(id.id)) else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().onPress(HotKeys.keys[Int(id.id)].edge)
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (index, key) in Self.keys.enumerated() {
            var hotKey: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key.code), UInt32(controlKey | optionKey),
                                EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                                GetApplicationEventTarget(), 0, &hotKey)
            if let hotKey { hotKeys.append(hotKey) }
        }
    }

    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
