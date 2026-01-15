import Combine
import Foundation

final class FloatingOverlayModel: ObservableObject {
    @Published var stateText: String = "待機中"
    @Published var partialText: String = ""
    @Published var committedText: String = ""
    @Published var manualEditText: String = ""
    @Published var audioLevel: Double = 0
    @Published var manualEditEnabled: Bool = false
}
