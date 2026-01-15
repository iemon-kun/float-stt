import AppKit
import ApplicationServices
import Foundation

enum TextInserter {
    static func paste(_ text: String) -> Bool {
        guard ensureAccessibilityPermission() else { return false }
        let pasteboard = NSPasteboard.general
        let previousItems = snapshotPasteboardItems(pasteboard)
        let previousString = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let expectedChangeCount = previousChangeCount + 1

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        guard !previousItems.isEmpty || previousString != nil else { return true }

        let delays: [TimeInterval] = [0.5, 1.0, 1.6]

        func scheduleRestore(at index: Int) {
            guard index < delays.count else {
                restorePasteboard(pasteboard, items: previousItems, fallbackString: previousString)
                return
            }
            let delay = delays[index]
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if pasteboard.changeCount != expectedChangeCount { return }
                scheduleRestore(at: index + 1)
            }
        }

        scheduleRestore(at: 0)
        return true
    }

    private static func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }
        var copied: [NSPasteboardItem] = []
        for item in items {
            let newItem = NSPasteboardItem()
            var hasData = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                    hasData = true
                }
            }
            if hasData {
                copied.append(newItem)
            }
        }
        return copied
    }

    private static func restorePasteboard(
        _ pasteboard: NSPasteboard,
        items: [NSPasteboardItem],
        fallbackString: String?
    ) {
        pasteboard.clearContents()
        if !items.isEmpty {
            _ = pasteboard.writeObjects(items)
        } else if let fallbackString {
            pasteboard.setString(fallbackString, forType: .string)
        }
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private static func ensureAccessibilityPermission() -> Bool {
        if hasAccessibilityPermission() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
