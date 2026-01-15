import SwiftUI

struct MinimalFloatingView: View {
    @ObservedObject var model: FloatingOverlayModel
    var onContentHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                WaveformView(level: model.audioLevel)
                    .frame(width: 80, height: 12)
            }

            if model.manualEditEnabled {
                Text(model.partialText.isEmpty ? "…" : model.partialText)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)

                TextEditor(text: $model.manualEditText)
                    .font(.system(size: 14))
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            } else {
                if !model.committedText.isEmpty {
                    Text(model.committedText)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(model.partialText.isEmpty ? "…" : model.partialText)
                    .font(.system(size: 16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            onContentHeightChange?(height)
        }
    }
}

struct WaveformView: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let barCount = 10
            let barWidth = w / CGFloat(barCount * 2)
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) / Double(barCount)
                    let amp = max(0.1, level * (0.6 + 0.4 * sin(phase * .pi)))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.7))
                        .frame(width: barWidth, height: h * amp)
                }
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
