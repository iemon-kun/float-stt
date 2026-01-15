# FloatSTT

FloatSTT is a macOS utility that captures speech from the microphone, transcribes it locally, and lets you paste the generated text via a floating overlay window. It combines SwiftUI, AVFoundation, a custom VAD implementation, and the native speech framework so you stay in control without relying on cloud services.

## Key Features
- Always-on-top compact panel plus a transparent capture view that listens for hotkeys and microphone input.
- Hotkey management handled by `FloatingPanelController` and `HotKeyManager`, with configurable key bindings.
- Real-time voice activity detection (VAD) and transcription pipeline from `VAD.swift` to `SpeechTranscriber.swift` and `TextInserter`.
- All icons under `nano-banana/` were produced with AI generation assistance and curated/adjusted by いえもんくんの錬処 (@iemon_kun).

## Getting Started
1. Install Xcode 15+ or ensure Swift 5.9 is available on macOS 13+.
2. Run `swift build` from the repository root and then `swift run FloatSTT` to test locally.
3. Alternatively, launch the prebuilt bundle at `dist/FloatSTT.app` (note that `dist/` is ignored by Git).
4. Document asset usage in the README and credit the custom icons when distributing the app.

## Docs
- See the Japanese README for context and instructions: [README.md](README.md).
- License details are in the [LICENSE](LICENSE) file.

## Credits
- Icons and artwork: AI-generated assets selected and refined by いえもんくんの錬処 (@iemon_kun).
- Licensed under MIT (see [LICENSE](LICENSE)).
