import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    var acceptsKey: Bool = false

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

private final class HostingContainerView: NSView {
    private let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateRootView(_ rootView: AnyView) {
        hostingView.rootView = rootView
        needsLayout = true
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }
}

final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var lastOrigin: CGPoint?
    private let settings = AppSettings.shared
    private var lastManualSize: CGSize?
    private var resizeWorkItem: DispatchWorkItem?
    private var isAutoResizing: Bool = false
    private var lastAppliedHeight: CGFloat = 0
    private var logAutoResize: Bool = false
    private var anchorTopLeft: CGPoint?
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Dev/voice-input/z-minimal-pj/tmp/auto-resize.log")

    func show(rootView: some View, acceptsKey: Bool) {
        ensureWindow(acceptsKey: acceptsKey)
        guard let window else { return }

        if let container = window.contentView as? HostingContainerView {
            container.updateRootView(AnyView(rootView))
        } else {
            window.contentView = HostingContainerView(rootView: AnyView(rootView))
        }

        if acceptsKey {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func ensureVisible() {
        guard let window else { return }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if isAutoResizing { return }
        if let event = NSApp.currentEvent {
            if event.type != .leftMouseDragged && event.type != .leftMouseUp {
                return
            }
        }
        lastOrigin = win.frame.origin
        settings.savePanelOrigin(win.frame.origin)
        anchorTopLeft = CGPoint(x: win.frame.origin.x, y: win.frame.origin.y + win.frame.height)
    }

    func windowDidResize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if isAutoResizing { return }
        if !win.inLiveResize { return }
        lastManualSize = win.frame.size
        settings.savePanelSize(win.frame.size)
        lastAppliedHeight = win.frame.height
        anchorTopLeft = CGPoint(x: win.frame.origin.x, y: win.frame.origin.y + win.frame.height)
    }

    func updateContentHeight(_ contentHeight: CGFloat) {
        guard window != nil else { return }

        resizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let window = self.window else { return }
            guard !window.inLiveResize else { return }
            guard !self.isAutoResizing else { return }
            let chrome: CGFloat = 40
            let minHeight = self.lastManualSize?.height ?? window.frame.height
            let maxAllowedHeight: CGFloat = {
                let screen = window.screen ?? NSScreen.main
                let visible = screen?.visibleFrame.height ?? 800
                return floor(visible * 0.7)
            }()
            let desired = min(maxAllowedHeight, max(minHeight, contentHeight + chrome))
            if desired <= max(window.frame.height, self.lastAppliedHeight) + 2 { return }
            if self.logAutoResize {
                let screenDesc = window.screen?.localizedName ?? "nil"
                let visible = window.screen?.visibleFrame ?? .zero
                self.appendLog("[auto-resize] content=\(contentHeight) desired=\(desired) frame=\(window.frame) screen=\(screenDesc) visible=\(visible)")
            }
            self.resizeWindowKeepingTop(desiredHeight: desired)
            self.lastAppliedHeight = desired
        }
        resizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    private func ensureWindow(acceptsKey: Bool) {
        if let window = window as? FloatingPanel, window.acceptsKey == acceptsKey { return }
        if window != nil {
            window?.orderOut(nil)
            window = nil
        }

        let baseStyle: NSWindow.StyleMask = [
            .titled,
            .fullSizeContentView,
            .resizable
        ]
        let style: NSWindow.StyleMask = acceptsKey
            ? baseStyle
            : baseStyle.union(.nonactivatingPanel)
        let defaultSize = CGSize(width: 420, height: 160)
        let size = settings.savedPanelSize() ?? defaultSize
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.delegate = self
        panel.acceptsKey = acceptsKey

        positionPanel(panel)
        window = panel
        lastManualSize = panel.frame.size
        anchorTopLeft = CGPoint(x: panel.frame.origin.x, y: panel.frame.origin.y + panel.frame.height)
    }

    private func positionPanel(_ panel: NSPanel) {
        if lastOrigin == nil {
            lastOrigin = settings.savedPanelOrigin()
        }
        if let lastOrigin {
            panel.setFrameOrigin(lastOrigin)
            return
        }
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.maxY - panel.frame.height - 24
            )
            panel.setFrameOrigin(origin)
        }
    }

    private func resizeWindowKeepingTop(desiredHeight: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        if abs(desiredHeight - frame.height) <= 0.5 { return }

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let baseX = anchorTopLeft?.x ?? frame.origin.x
        let baseTop = anchorTopLeft?.y ?? (frame.origin.y + frame.height)
        let top = min(baseTop, visible.maxY)
        let height = min(desiredHeight, visible.height)
        var originY = top - height
        if originY < visible.minY {
            originY = visible.minY
        }
        if originY + height > visible.maxY {
            originY = visible.maxY - height
        }

        frame.origin.x = baseX
        frame.origin.y = originY
        frame.size.height = height
        if logAutoResize {
            let screenDesc = window.screen?.localizedName ?? "nil"
            appendLog("[auto-resize] apply frame=\(frame) screen=\(screenDesc) visible=\(visible)")
        }
        isAutoResizing = true
        window.setFrame(frame, display: true)
        isAutoResizing = false
    }

    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let data = Data(line.utf8)
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            }
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
