import AVFoundation
import Combine
import Foundation
import Speech

final class SpeechTranscriber: NSObject, ObservableObject {
    @Published var partialText: String = ""
    @Published var finalText: String = ""
    @Published var uncommittedText: String = ""
    @Published var audioLevel: Double = 0
    @Published var isAuthorized: Bool = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))

    private let audioQueue = DispatchQueue(label: "minimal.speech.queue")
    private var vad: VoiceActivityDetector?
    private var segmentationEnabled: Bool = false
    private var stoppingAfterFinal: Bool = false
    private var requestID: UUID = UUID()
    private var pendingStartNewAfterFinal: Bool = false
    private var segmentSerial: Int = 0
    private var addsPunctuationEnabled: Bool = false

    private struct TranscriptionBuffer {
        var lastText: String = ""
        var version: Int = 0
        var committedPrefix: String = ""

        mutating func reset() {
            lastText = ""
            version = 0
            committedPrefix = ""
        }

        mutating func update(_ text: String) {
            lastText = text
            version &+= 1
        }

        mutating func resetCommittedPrefixIfNeeded(for fullText: String) {
            if !committedPrefix.isEmpty, !fullText.hasPrefix(committedPrefix) {
                committedPrefix = ""
            }
        }
    }

    private var buffer = TranscriptionBuffer()
    private var lastEmittedSegmentForDisplay: String = ""
    private var stopReasonEmitted: StopReason?

    enum StopReason {
        case requested
        case error
    }

    var onSegmentFinal: ((String) -> Void)?
    var onStopped: ((StopReason) -> Void)?

    var isAudioRunning: Bool {
        audioEngine.isRunning
    }

    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        await MainActor.run {
            self.isAuthorized = (speechStatus == .authorized && micGranted)
        }
    }

    func start(segmentationEnabled: Bool, silenceDurationMs: Int, silenceLevelThreshold: Double, addsPunctuationEnabled: Bool) throws {
        stop()
        partialText = ""
        finalText = ""
        uncommittedText = ""
        buffer.reset()
        lastEmittedSegmentForDisplay = ""
        stopReasonEmitted = nil
        stoppingAfterFinal = false
        pendingStartNewAfterFinal = false
        self.segmentationEnabled = segmentationEnabled
        self.addsPunctuationEnabled = addsPunctuationEnabled
        self.vad = VoiceActivityDetector(config: VADConfig(silenceDurationMs: silenceDurationMs, levelThreshold: silenceLevelThreshold))

        try installTapIfNeeded()
        audioEngine.prepare()
        try audioEngine.start()
        startNewRequest()
    }

    func requestStopAfterFinal() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.stoppingAfterFinal = true
            self.segmentationEnabled = false
            self.vad?.reset()
            self.pendingStartNewAfterFinal = false
            if self.recognitionRequest == nil {
                self.stop()
                self.emitStopped(.requested)
                return
            }
            self.recognitionTask?.finish()
            self.recognitionRequest?.endAudio()
            self.stopAudioInput()

            let capturedID = self.requestID
            self.audioQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                guard self.stoppingAfterFinal else { return }
                guard self.requestID == capturedID else { return }
                self.stop()
                self.emitStopped(.requested)
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        stopReasonEmitted = nil
        stoppingAfterFinal = false
        pendingStartNewAfterFinal = false
        segmentSerial += 1
        DispatchQueue.main.async {
            self.audioLevel = 0
            self.uncommittedText = ""
        }
        lastEmittedSegmentForDisplay = ""
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        audioQueue.async {
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            let level = min(max(Double(rms) * 20.0, 0), 1)
            DispatchQueue.main.async {
                self.audioLevel = level
            }

            if self.segmentationEnabled, let vad = self.vad, vad.ingest(level: level) {
                self.scheduleFlush(trigger: .silence)
            }
        }
    }

    private func installTapIfNeeded() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            self.updateAudioLevel(buffer: buffer)
        }
    }

    private func startNewRequest() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = addsPunctuationEnabled
        }
        recognitionRequest = request

        let localID = UUID()
        requestID = localID
        buffer.reset()
        vad?.reset()

        recognitionTask = speechRecognizer?.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            guard let self else { return }
            if self.requestID != localID { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.audioQueue.async { [weak self] in
                    guard let self else { return }
                    if self.requestID != localID { return }
                    self.buffer.update(text)
                    let uncommitted = self.computeUncommittedTextBestEffort(fullText: text)
                    self.scheduleFlush(trigger: .punctuation)
                    if result.isFinal {
                        self.flushRemainderAsFinal()
                        if self.stoppingAfterFinal {
                            self.segmentSerial += 1
                            self.stop()
                            self.emitStopped(.requested)
                            return
                        }
                        if self.pendingStartNewAfterFinal {
                            self.pendingStartNewAfterFinal = false
                            self.segmentSerial += 1
                            self.startNewRequest()
                            return
                        }
                    }
                    DispatchQueue.main.async {
                        self.uncommittedText = uncommitted
                    }
                }
                DispatchQueue.main.async {
                    self.partialText = text
                    if result.isFinal {
                        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.finalText = final
                    }
                }
            }

            if let error {
                _ = error
                if self.stoppingAfterFinal {
                    self.stop()
                    self.emitStopped(.error)
                    return
                }
                if self.pendingStartNewAfterFinal {
                    self.pendingStartNewAfterFinal = false
                    self.segmentSerial += 1
                    self.startNewRequest()
                    return
                }
                // Instead of stopping completely, try to restart if it was an error during continuous recognition
                // But for simplicity, we just stop.
                self.stop()
                self.emitStopped(.error)
            }
        })
    }

    private enum FlushTrigger {
        case punctuation
        case silence
    }

    private func scheduleFlush(trigger: FlushTrigger) {
        guard segmentationEnabled else { return }
        guard !stoppingAfterFinal else { return }
        guard recognitionRequest != nil else { return }

        let capturedID = requestID
        let capturedSerial = segmentSerial
        let capturedVersion = buffer.version
        let stableDelay: TimeInterval = {
            switch trigger {
            case .punctuation:
                return 0.45
            case .silence:
                return addsPunctuationEnabled ? 0.75 : 0.25
            }
        }()

        audioQueue.asyncAfter(deadline: .now() + stableDelay) { [weak self] in
            guard let self else { return }
            guard self.requestID == capturedID else { return }
            guard self.segmentSerial == capturedSerial else { return }
            guard self.buffer.version == capturedVersion else { return }
            guard self.recognitionRequest != nil else { return }
            guard self.segmentationEnabled else { return }
            guard !self.stoppingAfterFinal else { return }
            self.flushIfPossible(trigger: trigger)
        }
    }

    private func flushIfPossible(trigger: FlushTrigger) {
        var full = buffer.lastText
        full = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return }

        buffer.resetCommittedPrefixIfNeeded(for: full)

        let remainderStart: String.Index = {
            guard !buffer.committedPrefix.isEmpty else { return full.startIndex }
            return full.index(full.startIndex, offsetBy: buffer.committedPrefix.count)
        }()
        let remainder = String(full[remainderStart...])
        let trimmedRemainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemainder.isEmpty else { return }

        let flushEndInRemainder: String.Index? = {
            if let end = lastSentenceBoundaryEndIndex(in: remainder) {
                return end
            }
            if trigger == .silence {
                return remainder.endIndex
            }
            return nil
        }()
        guard let flushEndInRemainder else { return }

        let flushEndInFull = full.index(remainderStart, offsetBy: remainder.distance(from: remainder.startIndex, to: flushEndInRemainder))
        let flushed = String(full[remainderStart..<flushEndInFull])
        let sentences = splitIntoSentences(flushed)
        for s in sentences {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            lastEmittedSegmentForDisplay = t
            DispatchQueue.main.async { [weak self] in
                self?.onSegmentFinal?(t)
            }
        }

        buffer.committedPrefix = String(full[..<flushEndInFull])
        let uncommitted = computeUncommittedTextBestEffort(fullText: full)
        DispatchQueue.main.async { [weak self] in
            self?.uncommittedText = uncommitted
        }
    }

    private func flushRemainderAsFinal() {
        flushIfPossible(trigger: .silence)
    }

    private func computeUncommittedTextBestEffort(fullText: String) -> String {
        let full = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard segmentationEnabled else { return full }

        if !buffer.committedPrefix.isEmpty, full.hasPrefix(buffer.committedPrefix) {
            let start = full.index(full.startIndex, offsetBy: buffer.committedPrefix.count)
            return String(full[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !lastEmittedSegmentForDisplay.isEmpty,
           let range = full.range(of: lastEmittedSegmentForDisplay, options: [.backwards])
        {
            let tail = String(full[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return tail }
            return ""
        }

        return full
    }

    private func lastSentenceBoundaryEndIndex(in text: String) -> String.Index? {
        var lastEnd: String.Index?
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if isSentencePunctuation(ch) {
                var end = text.index(after: idx)
                while end < text.endIndex, text[end].isWhitespaceOrNewline {
                    end = text.index(after: end)
                }
                lastEnd = end
            }
            idx = text.index(after: idx)
        }
        return lastEnd
    }

    private func isSentencePunctuation(_ ch: Character) -> Bool {
        switch ch {
        case "。", "！", "？", "!", "?":
            return true
        default:
            return false
        }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if isSentencePunctuation(ch) {
                out.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(current)
        }
        return out
    }

    private func emitStopped(_ reason: StopReason) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            if self.stopReasonEmitted != nil { return }
            self.stopReasonEmitted = reason
            DispatchQueue.main.async { [weak self] in
                self?.onStopped?(reason)
            }
        }
    }
}

private extension Character {
    var isWhitespaceOrNewline: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
