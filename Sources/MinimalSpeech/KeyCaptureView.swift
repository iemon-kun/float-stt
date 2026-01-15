import AppKit
import SwiftUI

struct KeyCaptureView: NSViewRepresentable {
    final class Coordinator: NSObject {
        let onKeyDown: (NSEvent) -> Void
        init(onKeyDown: @escaping (NSEvent) -> Void) { self.onKeyDown = onKeyDown }
    }

    let onKeyDown: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = context.coordinator.onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCaptureNSView else { return }
        view.onKeyDown = context.coordinator.onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}

final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
