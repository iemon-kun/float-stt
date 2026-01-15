import AppKit
import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotKey: HotKeyConfig {
        didSet { saveHotKey() }
    }

    @Published var manualEditEnabled: Bool {
        didSet { saveManualEditEnabled() }
    }

    @Published var localRefineEnabled: Bool {
        didSet { saveLocalRefineEnabled() }
    }

    private let defaults = UserDefaults.standard
    private let hotKeyKey = "minimal.hotkey"
    private let panelOriginXKey = "minimal.panel.origin.x"
    private let panelOriginYKey = "minimal.panel.origin.y"
    private let panelWidthKey = "minimal.panel.size.width"
    private let panelHeightKey = "minimal.panel.size.height"
    private let manualEditKey = "minimal.manualEditEnabled"
    private let localRefineKey = "minimal.localRefineEnabled"

    private init() {
        if let data = defaults.data(forKey: hotKeyKey),
           let decoded = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            hotKey = decoded
        } else {
            hotKey = HotKeyConfig(keyCode: 113, keyLabel: "F15", modifiers: [])
        }
        manualEditEnabled = defaults.bool(forKey: manualEditKey)
        if defaults.object(forKey: localRefineKey) == nil {
            localRefineEnabled = true
        } else {
            localRefineEnabled = defaults.bool(forKey: localRefineKey)
        }
    }

    func savedPanelOrigin() -> CGPoint? {
        guard defaults.object(forKey: panelOriginXKey) != nil,
              defaults.object(forKey: panelOriginYKey) != nil
        else {
            return nil
        }
        let x = defaults.double(forKey: panelOriginXKey)
        let y = defaults.double(forKey: panelOriginYKey)
        return CGPoint(x: x, y: y)
    }

    func savePanelOrigin(_ origin: CGPoint) {
        defaults.set(origin.x, forKey: panelOriginXKey)
        defaults.set(origin.y, forKey: panelOriginYKey)
    }

    func savedPanelSize() -> CGSize? {
        guard defaults.object(forKey: panelWidthKey) != nil,
              defaults.object(forKey: panelHeightKey) != nil
        else {
            return nil
        }
        let w = defaults.double(forKey: panelWidthKey)
        let h = defaults.double(forKey: panelHeightKey)
        return CGSize(width: w, height: h)
    }

    func savePanelSize(_ size: CGSize) {
        defaults.set(size.width, forKey: panelWidthKey)
        defaults.set(size.height, forKey: panelHeightKey)
    }

    private func saveHotKey() {
        if let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: hotKeyKey)
        }
    }

    private func saveManualEditEnabled() {
        defaults.set(manualEditEnabled, forKey: manualEditKey)
    }

    private func saveLocalRefineEnabled() {
        defaults.set(localRefineEnabled, forKey: localRefineKey)
    }
}
