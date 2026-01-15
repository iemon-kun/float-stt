import Foundation

struct VADConfig: Hashable {
    var silenceDurationMs: Int
    var levelThreshold: Double
}

final class VoiceActivityDetector {
    private let config: VADConfig
    private var silenceStart: CFAbsoluteTime?
    private var sawSpeechSinceLastBoundary: Bool = false
    private var boundaryFiredInCurrentSilence: Bool = false

    init(config: VADConfig) {
        self.config = config
    }

    func reset() {
        silenceStart = nil
        sawSpeechSinceLastBoundary = false
        boundaryFiredInCurrentSilence = false
    }

    /// Returns true when a boundary should be created.
    func ingest(level: Double) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let isSilent = level < config.levelThreshold

        if !isSilent {
            sawSpeechSinceLastBoundary = true
            silenceStart = nil
            boundaryFiredInCurrentSilence = false
            return false
        }

        guard sawSpeechSinceLastBoundary else { return false }

        if silenceStart == nil {
            silenceStart = now
            boundaryFiredInCurrentSilence = false
            return false
        }

        if boundaryFiredInCurrentSilence { return false }

        let elapsedMs = Int((now - (silenceStart ?? now)) * 1000)
        if elapsedMs >= config.silenceDurationMs {
            boundaryFiredInCurrentSilence = true
            sawSpeechSinceLastBoundary = false
            return true
        }

        return false
    }
}
