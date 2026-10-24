import AVFoundation
import Foundation

@MainActor
protocol TranslationSpeaking: AnyObject {
    var onSpeakingChanged: ((Bool) -> Void)? { get set }
    func speak(_ text: String, language: TranslationLanguage) throws
    func stop()
}

@MainActor
protocol ConversationTranslationSpeaking: TranslationSpeaking {
    var onCompletion: ((Bool) -> Void)? { get set }
}

/// No recording, assistant TTS selection, cloud fallback, or translation history.
@MainActor
final class TranslationSpeechService: NSObject, ConversationTranslationSpeaking, AVSpeechSynthesizerDelegate {
    var onSpeakingChanged: ((Bool) -> Void)?
    var onCompletion: ((Bool) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var ownsAudioSession = false
    private let voices: () -> [AVSpeechSynthesisVoice]
    private let configureAudio: () throws -> Void
    private let releaseAudio: () -> Void

    init(voices: @escaping () -> [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices,
         configureAudio: @escaping () throws -> Void = {
             let session = AVAudioSession.sharedInstance()
             try session.setCategory(.playback, mode: .spokenAudio, options: [])
             try session.setActive(true)
         },
         releaseAudio: @escaping () -> Void = {
             try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
         }) {
        self.voices = voices
        self.configureAudio = configureAudio
        self.releaseAudio = releaseAudio
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    /// Prefer exact locale; allow another installed voice of the same language, never English fallback.
    static func voiceIdentifier(for language: TranslationLanguage,
                                available: [(identifier: String, language: String)]) -> String? {
        if let exact = available.first(where: { $0.language == language.voiceLanguage }) { return exact.identifier }
        let prefix = language.voiceLanguage.split(separator: "-")[0]
        return available.first { voice in
            let parts = voice.language.split(separator: "-")
            // Mandarin only: do not silently pick a Cantonese voice for Chinese text.
            if language == .chinese { return ["zh-CN", "zh-TW", "zh-SG"].contains(voice.language) }
            return parts.first == prefix
        }?.identifier
    }

    func speak(_ text: String, language: TranslationLanguage) throws {
        stop()
        // Third-party synthesis extensions may use their own services. Only Apple system voices
        // belong in this local translation path; personal voices require separate user consent.
        let available = voices().filter {
            $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        guard let identifier = Self.voiceIdentifier(for: language, available: available.map { ($0.identifier, $0.language) }),
              let voice = available.first(where: { $0.identifier == identifier }) else { throw TranslationError.voiceUnavailable }
        do { try configureAudio() }
        catch {
            releaseAudio()
            throw TranslationError.audioUnavailable
        }
        ownsAudioSession = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance
        onSpeakingChanged?(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        if ownsAudioSession { releaseAudio(); ownsAudioSession = false }
        onSpeakingChanged?(false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance, completed: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance, completed: false) }
    }

    private func finished(_ utterance: AVSpeechUtterance, completed: Bool) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        if ownsAudioSession { releaseAudio(); ownsAudioSession = false }
        onSpeakingChanged?(false)
        onCompletion?(completed)
    }
}
