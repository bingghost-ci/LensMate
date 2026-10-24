import Foundation

/// Translation owns foreground audio exclusively. Assistant engines also check this gate so
/// late callbacks cannot restart audio while translation is open (including its settings sheet).
@MainActor
final class TranslationAudioCoordinator {
    static let shared = TranslationAudioCoordinator()
    private(set) var isTranslationActive = false
    private(set) var assistantGeneration = UUID()
    var suspendAssistant: (() -> Void)?
    private let stopAssistantSpeech: () -> Void

    init(stopAssistantSpeech: (() -> Void)? = nil) {
        self.stopAssistantSpeech = stopAssistantSpeech ?? {
            TTSService.shared.stop()
            NeuralSpeech.stopAll()
        }
    }

    func enterTranslation() {
        guard !isTranslationActive else { return }
        isTranslationActive = true
        assistantGeneration = UUID()
        suspendAssistant?()
        stopAssistantSpeech()
    }

    func acceptsAssistantWork(from generation: UUID) -> Bool {
        !isTranslationActive && assistantGeneration == generation
    }

    func leaveTranslation() {
        isTranslationActive = false
        // Assistant listening resumes only when its own page appears, never from this callback.
    }
}
