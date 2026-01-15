import AppKit
import Carbon.HIToolbox
import Foundation

struct HotKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let control = HotKeyModifiers(rawValue: 1 << 2)
    static let shift = HotKeyModifiers(rawValue: 1 << 3)

    var displayPrefix: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

extension HotKeyModifiers {
    init(from flags: NSEvent.ModifierFlags) {
        var mods: HotKeyModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        self = mods
    }
}

struct HotKeyConfig: Codable, Hashable {
    var keyCode: UInt32
    var keyLabel: String
    var modifiers: HotKeyModifiers

    var displayName: String {
        "\(modifiers.displayPrefix)\(keyLabel)"
    }
}

enum HotKeyRules {
    static let allowedBareKeyCodes: Set<UInt32> = [105, 107, 113, 106, 64, 79, 80] // F13..F19

    static func isBareAllowed(keyCode: UInt32) -> Bool {
        allowedBareKeyCodes.contains(keyCode)
    }

    static func requiresNonShiftModifier(keyCode: UInt32) -> Bool {
        !isBareAllowed(keyCode: keyCode)
    }
}
