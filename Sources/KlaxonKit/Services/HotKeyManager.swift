import AppKit
import Carbon.HIToolbox

/// Global ⌃⌥P hotkey via Carbon `RegisterEventHotKey` — works without the
/// Accessibility permission an event tap would demand.
@MainActor
public final class HotKeyManager {

    public var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init() {}

    public func register() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        // C callback can't capture; smuggle `self` through userData.
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon dispatches on the main thread.
                MainActor.assumeIsolated { manager.onToggle?() }
                return noErr
            },
            1, &eventType, userData, &handlerRef)
        guard handlerStatus == noErr else {
            NSLog("Klaxon: failed to install hotkey handler (OSStatus \(handlerStatus)); ⌃⌥P disabled")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4C_584E), id: 1) // 'KLXN'
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef)
        if registerStatus != noErr {
            NSLog("Klaxon: failed to register ⌃⌥P hotkey (OSStatus \(registerStatus))")
        }
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
