import Foundation

enum TranslationSpeaker: String, Equatable, Sendable {
    case me, partner
    var title: String.LocalizationValue { self == .me ? "You" : "Partner" }
}

enum ConversationTranslationPhase: Equatable {
    case idle, paused, waitingForPartner
    case preparing(TranslationSpeaker), recording(TranslationSpeaker)
    case recognizing(TranslationSpeaker), translating(TranslationSpeaker)
    case speaking(UUID)

    var isProcessing: Bool {
        switch self {
        case .preparing, .recognizing, .translating: return true
        default: return false
        }
    }
}

struct ConversationTranslationTurn: Identifiable, Equatable {
    enum Status: Equatable {
        case recognizing, translating, complete, cancelled, failed(TranslationError)
    }
    let id: UUID
    let speaker: TranslationSpeaker
    let source: TranslationLanguage
    let target: TranslationLanguage
    var original: String = ""
    var translation: String = ""
    var status: Status = .recognizing
}

struct RecordedTranslationSpeech: Sendable {
    let wav: Data
    let duration: TimeInterval
}

struct TranslationRecordingProgress: Equatable {
    let elapsed: TimeInterval
    let hasSpeech: Bool
    let silenceRemaining: TimeInterval?
}

/// Acoustic silence, not time since the last transcript. A brief click cannot start an utterance.
struct TranslationSilenceDetector {
    static let maximumRecordingDuration: TimeInterval = 60
    static let noSpeechTimeout: TimeInterval = 20
    let silenceDuration: TimeInterval
    private(set) var hasSpeech = false
    private(set) var lastVoiceTime: TimeInterval = 0
    private var voicedDuration: TimeInterval = 0
    private var previousTime: TimeInterval = 0

    init(silenceDuration: TimeInterval) {
        self.silenceDuration = Self.clampedDuration(silenceDuration)
    }

    static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? min(10, max(1, duration)) : 5
    }

    mutating func observe(decibels: Float, elapsed: TimeInterval) {
        let delta = min(0.25, max(0, elapsed - previousTime))
        previousTime = elapsed
        if decibels.isFinite && decibels > -45 {
            voicedDuration += delta
            if voicedDuration >= 0.15 { hasSpeech = true }
            lastVoiceTime = elapsed
        } else {
            voicedDuration = 0
        }
    }

    func shouldFinish(speaker: TranslationSpeaker, elapsed: TimeInterval) -> Bool {
        if elapsed >= Self.maximumRecordingDuration { return speaker == .me }
        // The partner's microphone is always push-to-start / tap-to-finish.
        return speaker == .me && hasSpeech && elapsed - lastVoiceTime >= silenceDuration
    }

    func remainingSilence(at elapsed: TimeInterval) -> TimeInterval? {
        hasSpeech ? max(0, silenceDuration - (elapsed - lastVoiceTime)) : nil
    }
}

extension TranslationLanguage {
    var recognitionCode: String {
        switch self {
        case .chinese: return "zh"
        case .english: return "en"
        case .thai: return "th"
        }
    }
}
