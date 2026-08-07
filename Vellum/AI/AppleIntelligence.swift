import FoundationModels
import VellumCore

@available(iOS 26.0, *)
enum AppleIntelligence {
    /// Maps the system model's availability to the app's availability model.
    static func availability() -> NoteAskAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .fallback(reason: "This device does not support Apple Intelligence")
            case .appleIntelligenceNotEnabled:
                return .fallback(reason: "Apple Intelligence is not enabled")
            case .modelNotReady:
                return .fallback(reason: "Apple Intelligence model is still downloading")
            @unknown default:
                return .fallback(reason: "Apple Intelligence is unavailable")
            }
        }
    }
}
