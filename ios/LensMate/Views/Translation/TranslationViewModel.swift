import Foundation

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var inputText = "" {
        didSet { if oldValue != inputText { invalidate(clearResult: true) } }
    }
    @Published private(set) var source: TranslationLanguage = .chinese
    @Published private(set) var target: TranslationLanguage = .english
    @Published private(set) var result: TranslationResult?
    @Published private(set) var isTranslating = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var error: TranslationError?
    @Published var automaticallySpeak = true

    private let client: any TextTranslating
    private let credentials: @MainActor () throws -> TranslationCredentials
    private let speech: any TranslationSpeaking
    private let audio: TranslationAudioCoordinator
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var isActive = false

    init(client: any TextTranslating = AliyunTranslationClient(),
         credentials: (@MainActor () throws -> TranslationCredentials)? = nil,
         speech: (any TranslationSpeaking)? = nil,
         audio: TranslationAudioCoordinator? = nil) {
        self.client = client
        self.credentials = credentials ?? { try TranslationConfiguration.shared.credentials() }
        self.speech = speech ?? TranslationSpeechService()
        self.audio = audio ?? .shared
        self.speech.onSpeakingChanged = { [weak self] speaking in self?.isSpeaking = speaking }
    }

    func activate() {
        audio.enterTranslation()
        isActive = true
    }

    func suspend() {
        isActive = false
        stop()
    }

    func leave() {
        suspend()
        audio.leaveTranslation()
    }

    func selectSource(_ language: TranslationLanguage) {
        guard source != language else { return }
        let previous = source
        source = language
        if target == language { target = previous }
        invalidate(clearResult: true)
    }

    func selectTarget(_ language: TranslationLanguage) {
        guard target != language else { return }
        let previous = target
        target = language
        if source == language { source = previous }
        invalidate(clearResult: true)
    }

    func swapDirection() {
        let previous = source
        source = target
        target = previous
        invalidate(clearResult: true)
    }

    func translate() {
        invalidate(clearResult: true)
        guard isActive else { return }
        let input = TranslationInput(text: inputText, source: source, target: target)
        let credential: TranslationCredentials
        do {
            try input.validate()
            credential = try credentials()
        } catch {
            self.error = (error as? TranslationError) ?? .notConfigured
            return
        }
        isTranslating = true
        let id = generation
        let client = client
        task = Task { [weak self] in
            do {
                let text = try await client.translate(input, credentials: credential)
                // Do not trust a transport/provider to honor cancellation. The identity check is mandatory.
                guard let self, self.isActive, self.generation == id, !Task.isCancelled else { return }
                self.result = TranslationResult(input: input, text: text)
                self.isTranslating = false
                self.task = nil
                if self.automaticallySpeak { self.replay() }
            } catch {
                guard let self, self.isActive, self.generation == id, !Task.isCancelled else { return }
                self.isTranslating = false
                self.task = nil
                if !(error is CancellationError) {
                    self.error = (error as? TranslationError) ?? .network
                }
            }
        }
    }

    func replay() {
        guard isActive, !isTranslating, let result else { return }
        error = nil
        do { try speech.speak(result.text, language: result.input.target) }
        catch { self.error = (error as? TranslationError) ?? .audioUnavailable }
    }

    /// Stops both upload and speech; keeps a finished translation available for explicit replay.
    func stop() { invalidate(clearResult: false) }

    private func invalidate(clearResult: Bool) {
        generation = UUID()
        task?.cancel()
        task = nil
        isTranslating = false
        speech.stop()
        isSpeaking = false
        error = nil
        if clearResult { result = nil }
    }
}
