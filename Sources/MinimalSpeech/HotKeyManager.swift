import AppKit
import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D4E4C53), id: 1) // 'MNLS'
    private var currentConfig: HotKeyConfig?

    var onHotKey: (() -> Void)?

    private init() {}

    @discardableResult
    func register(config: HotKeyConfig) -> Bool {
        unregister()

        installEventHandlerIfNeeded()

        let modifierFlags: UInt32 = config.modifiers.carbonFlags
        let keyCode: UInt32 = config.keyCode

        let status = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            currentConfig = config
            return true
        }
        hotKeyRef = nil
        return false
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentConfig = nil
    }

    func canRegister(config: HotKeyConfig) -> Bool {
        let old = currentConfig
        _ = register(config: config)
        let ok = (hotKeyRef != nil)
        unregister()
        if let old {
            _ = register(config: old)
        }
        return ok
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.id == manager.hotKeyID.id {
                    DispatchQueue.main.async {
                        manager.onHotKey?()
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
