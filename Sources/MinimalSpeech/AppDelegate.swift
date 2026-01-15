import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum SessionState {
        case idle
        case listening
        case stopping

        var displayText: String {
            switch self {
            case .idle: return "待機中"
            case .listening: return "聴取中"
            case .stopping: return "確定中"
            }
        }
    }

    private let transcriber = SpeechTranscriber()
    private let panelController = FloatingPanelController()
    private let overlayModel = FloatingOverlayModel()
    private let settings = AppSettings.shared
    private let settingsWindowController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var state: SessionState = .idle {
        didSet { updateOverlayState() }
    }
    private var committedText: String = ""
    private var latestUncommitted: String = ""
    private var targetAppPID: pid_t?
    private let appPID = ProcessInfo.processInfo.processIdentifier
    private var pendingPasteText: String?
    private var pasteRetryWorkItem: DispatchWorkItem?
    private let terminationToken = "KeepMenuBarAlive"
    private var appActivity: NSObjectProtocol?
    private let terminationLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Dev/voice-input/z-minimal-pj/tmp/termination.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(terminationToken)
        appActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Keep menu bar app running"
        )
        Task { await transcriber.requestAuthorization() }
        setupStatusBar()
        setupHotKey()
        bindTranscriber()
        updateOverlayState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appendTerminationLog("applicationWillTerminate")
        HotKeyManager.shared.unregister()
        transcriber.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(terminationToken)
        if let activity = appActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appActivity = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func appendTerminationLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let data = Data(line.utf8)
        let dir = terminationLogURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: terminationLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: terminationLogURL) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            }
        } else {
            try? data.write(to: terminationLogURL, options: .atomic)
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = loadStatusIcon() {
            item.button?.image = icon
        } else {
            item.button?.title = "🎙️"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "開始/終了", action: #selector(toggleListeningMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "設定を開く", action: #selector(openSettingsMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quitMenu), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
        updateMenuTitle()
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.toggleListening()
        }
        if !HotKeyManager.shared.register(config: settings.hotKey) {
            let fallback = HotKeyConfig(keyCode: 113, keyLabel: "F15", modifiers: [])
            settings.hotKey = fallback
            _ = HotKeyManager.shared.register(config: fallback)
        }

        settings.$hotKey
            .removeDuplicates()
            .sink { [weak self] config in
                _ = HotKeyManager.shared.register(config: config)
                self?.updateMenuTitle()
            }
            .store(in: &cancellables)
    }

    private func bindTranscriber() {
        transcriber.onSegmentFinal = { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if self.settings.manualEditEnabled {
                self.appendManualEditSegment(trimmed)
            } else {
                let merged = self.mergeText(base: self.committedText, addition: trimmed)
                if merged != self.committedText {
                    self.committedText = merged
                    self.overlayModel.committedText = merged
                }
            }
        }

        transcriber.onStopped = { [weak self] reason in
            Task { @MainActor in
                self?.handleStop(reason: reason)
            }
        }

        transcriber.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.overlayModel.audioLevel = level
                if self?.state == .listening {
                    self?.panelController.ensureVisible()
                }
            }
            .store(in: &cancellables)

        transcriber.$uncommittedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.latestUncommitted = text
                }
                self?.overlayModel.partialText = text
            }
            .store(in: &cancellables)
    }

    @objc private func toggleListeningMenu() {
        toggleListening()
    }

    @objc private func quitMenu() {
        NSApp.terminate(nil)
    }

    @objc private func openSettingsMenu() {
        settingsWindowController.show()
    }

    private func updateMenuTitle() {
        guard let menu = statusItem?.menu else { return }
        let title = "開始/終了 (\(settings.hotKey.displayName))"
        menu.items.first?.title = title
    }

    private func toggleListening() {
        guard transcriber.isAuthorized else {
            Task { await transcriber.requestAuthorization() }
            return
        }

        switch state {
        case .idle:
            startListening()
        case .listening:
            requestStop()
        case .stopping:
            finalizePaste()
        }
    }

    private func startListening() {
        committedText = ""
        latestUncommitted = ""
        prepareOverlayForSession()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetAppPID = (frontmost == appPID) ? nil : frontmost
        state = .listening

        panelController.show(
            rootView: MinimalFloatingView(model: overlayModel, onContentHeightChange: { [weak self] height in
                self?.panelController.updateContentHeight(height)
            }),
            acceptsKey: settings.manualEditEnabled
        )

        do {
            try transcriber.start(
                segmentationEnabled: true,
                silenceDurationMs: 800,
                silenceLevelThreshold: 0.02,
                addsPunctuationEnabled: true
            )
        } catch {
            state = .idle
        }
    }

    private func requestStop() {
        state = .stopping
        transcriber.requestStopAfterFinal()
    }

    private func handleStop(reason: SpeechTranscriber.StopReason) {
        switch reason {
        case .requested:
            finalizePaste()
        case .error:
            resetSession()
        }
    }

    private func finalizePaste() {
        guard state == .stopping else {
            resetSession()
            return
        }
        let combined: String
        if settings.manualEditEnabled {
            combined = mergeText(
                base: overlayModel.manualEditText,
                addition: overlayModel.partialText
            )
        } else {
            combined = mergeFinalText()
        }
        let refined = settings.localRefineEnabled ? LocalRefiner.refine(combined) : combined
        let trimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetSession()
            return
        }
        pendingPasteText = trimmed

        activateTargetApp()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if TextInserter.paste(trimmed) {
                resetSession()
            } else {
                overlayModel.stateText = "権限が必要"
                schedulePasteRetry()
            }
        }
    }

    private func schedulePasteRetry() {
        pasteRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .stopping else { return }
            guard let text = self.pendingPasteText, !text.isEmpty else { return }
            if !TextInserter.hasAccessibilityPermission() {
                self.schedulePasteRetry()
                return
            }
            self.activateTargetApp()
            if TextInserter.paste(text) {
                self.resetSession()
            } else {
                self.schedulePasteRetry()
            }
        }
        pasteRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func activateTargetApp() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pidToActivate = targetAppPID ?? ((frontmostPID == appPID) ? nil : frontmostPID)
        if let pid = pidToActivate {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    private func mergeFinalText() -> String {
        let tail = latestUncommitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return committedText }
        return mergeText(base: committedText, addition: tail)
    }

    private func appendManualEditSegment(_ segment: String) {
        let separator = overlayModel.manualEditText.isEmpty ? "" : "\n"
        overlayModel.manualEditText += "\(separator)\(segment)"
    }

    private func mergeText(base: String, addition: String) -> String {
        let baseTrimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let addTrimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseTrimmed.isEmpty else { return addTrimmed }
        guard !addTrimmed.isEmpty else { return baseTrimmed }

        let normalizedBase = normalizeForMerge(baseTrimmed)
        let normalizedAdd = normalizeForMerge(addTrimmed)
        if normalizedAdd.contains(normalizedBase) {
            return addTrimmed
        }
        if normalizedBase.contains(normalizedAdd) {
            return baseTrimmed
        }

        let baseChars = Array(baseTrimmed)
        let addChars = Array(addTrimmed)
        let maxOverlap = min(baseChars.count, addChars.count)
        var overlap = 0
        if maxOverlap > 0 {
            for k in stride(from: maxOverlap, through: 1, by: -1) {
                if baseChars.suffix(k) == addChars.prefix(k) {
                    overlap = k
                    break
                }
            }
        }

        if overlap > 0 {
            let suffix = addChars.dropFirst(overlap)
            return baseTrimmed + String(suffix)
        }
        return baseTrimmed + " " + addTrimmed
    }

    private func normalizeForMerge(_ text: String) -> String {
        let removeSet = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
        return text.unicodeScalars.filter { !removeSet.contains($0) }.map(String.init).joined()
    }

    private func resetSession() {
        state = .idle
        committedText = ""
        latestUncommitted = ""
        resetOverlayAfterSession()
        targetAppPID = nil
        pendingPasteText = nil
        pasteRetryWorkItem?.cancel()
        pasteRetryWorkItem = nil
        panelController.hide()
    }

    private func prepareOverlayForSession() {
        overlayModel.committedText = ""
        overlayModel.manualEditText = ""
        overlayModel.partialText = ""
        overlayModel.manualEditEnabled = settings.manualEditEnabled
    }

    private func resetOverlayAfterSession() {
        overlayModel.committedText = ""
        overlayModel.partialText = ""
        overlayModel.manualEditText = ""
        overlayModel.audioLevel = 0
    }

    private func updateOverlayState() {
        overlayModel.stateText = state.displayText
    }

    private func loadStatusIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png") else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
