import SwiftUI

struct ContentView: View {
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var segments: [String] = []

    var body: some View {
        VStack {
            Text("FloatSTT")
                .font(.headline)
                .padding(.top)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(segments.indices, id: \.self) { index in
                            Text(segments[index])
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        if !transcriber.uncommittedText.isEmpty {
                            Text(transcriber.uncommittedText)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .onChange(of: segments.count) { _ in
                   withAnimation {
                       proxy.scrollTo(segments.count - 1, anchor: .bottom)
                   }
                }
                .onChange(of: transcriber.uncommittedText) { _ in
                   // Auto scroll could be added here
                }
            }

            Divider()

            HStack {
                if transcriber.isAudioRunning {
                    Button(action: {
                        transcriber.stop()
                    }) {
                        Text("Stop Recording")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                } else {
                    Button(action: {
                        startRecording()
                    }) {
                        Text("Start Recording")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(transcriber.isAuthorized ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!transcriber.isAuthorized)
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            Task {
                await transcriber.requestAuthorization()
            }
            transcriber.onSegmentFinal = { text in
                segments.append(text)
            }
        }
    }

    private func startRecording() {
        do {
            try transcriber.start(
                segmentationEnabled: true,
                silenceDurationMs: 800,
                silenceLevelThreshold: 0.02,
                addsPunctuationEnabled: true
            )
        } catch {
            print("Error starting: \(error)")
        }
    }
}
