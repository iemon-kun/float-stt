import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isCapturing: Bool = false
    @State private var draftHotKey: HotKeyConfig = HotKeyConfig(keyCode: 113, keyLabel: "F15", modifiers: [])
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FloatSTT")
                .font(.headline)

            GroupBox("ショートカットキー") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("現在: \(settings.hotKey.displayName)")
                        .font(.subheadline)

                    HStack(spacing: 10) {
                        Button(isCapturing ? "入力待ち…" : "割り当てを記録") {
                            errorText = nil
                            draftHotKey = settings.hotKey
                            isCapturing = true
                        }
                        .disabled(isCapturing)

                        Button("戻す") {
                            errorText = nil
                            draftHotKey = settings.hotKey
                        }
                        .disabled(isCapturing || draftHotKey == settings.hotKey)

                        Spacer()

                        Button("保存") {
                            saveDraft()
                        }
                        .disabled(isCapturing || draftHotKey == settings.hotKey)
                    }
                    .buttonStyle(.bordered)

                    Text("候補: \(draftHotKey.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if isCapturing {
                        Text("割り当てたいキーを押してください（Escでキャンセル）")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        KeyCaptureView { event in
                            handleKeyCapture(event)
                        }
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 6)
            }

            Toggle("手動編集モード", isOn: $settings.manualEditEnabled)
                .toggleStyle(.switch)
                .padding(.top, 4)

            Toggle("ローカル整形", isOn: $settings.localRefineEnabled)
                .toggleStyle(.switch)

            Text("\(settings.hotKey.displayName) で録音開始/終了。確定後はペースト挿入します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 260)
        .onAppear {
            draftHotKey = settings.hotKey
        }
    }

    private func handleKeyCapture(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == 53 { // Esc
            isCapturing = false
            errorText = nil
            draftHotKey = settings.hotKey
            return
        }

        if isModifierKey(keyCode: keyCode) {
            return
        }

        let modifiers = HotKeyModifiers(from: event.modifierFlags)
        let label = keyLabel(for: keyCode, fallback: event.charactersIgnoringModifiers)
        let candidate = HotKeyConfig(keyCode: keyCode, keyLabel: label, modifiers: modifiers)

        if let validationError = validate(candidate) {
            errorText = validationError
            draftHotKey = candidate
            isCapturing = false
            return
        }

        errorText = nil
        draftHotKey = candidate
        isCapturing = false
    }

    private func saveDraft() {
        if let validationError = validate(draftHotKey) {
            errorText = validationError
            return
        }
        if !HotKeyManager.shared.canRegister(config: draftHotKey) {
            errorText = "このキーは登録できません（他アプリと競合/予約キーの可能性）"
            return
        }
        errorText = nil
        settings.hotKey = draftHotKey
    }

    private func validate(_ config: HotKeyConfig) -> String? {
        if HotKeyRules.requiresNonShiftModifier(keyCode: config.keyCode) {
            let ok = config.modifiers.contains(.command) || config.modifiers.contains(.option) || config.modifiers.contains(.control)
            if !ok {
                return "このキーは単体では使えません。⌘/⌥/⌃のいずれかを組み合わせてください。"
            }
        }
        return nil
    }

    private func keyLabel(for keyCode: UInt32, fallback: String?) -> String {
        switch keyCode {
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        default:
            if let fallback, !fallback.isEmpty {
                return fallback.uppercased()
            }
            return "KeyCode(\(keyCode))"
        }
    }

    private func isModifierKey(keyCode: UInt32) -> Bool {
        let modifierCodes: Set<UInt32> = [56, 60, 59, 62, 58, 61, 55, 54, 63]
        return modifierCodes.contains(keyCode)
    }
}
