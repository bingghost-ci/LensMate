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

struct TranslationRecordingOptions: Equatable {
    static let durationRange: ClosedRange<TimeInterval> = 30...300
    let silenceDuration: TimeInterval
    let maximumDuration: TimeInterval
    let automaticallyEndsMyTurn: Bool

    init(silenceDuration: TimeInterval = 5, maximumDuration: TimeInterval = 60,
         automaticallyEndsMyTurn: Bool = false) {
        self.silenceDuration = TranslationSilenceDetector.clampedDuration(silenceDuration)
        self.maximumDuration = Self.clampedMaximumDuration(maximumDuration)
        self.automaticallyEndsMyTurn = automaticallyEndsMyTurn
    }

    static func clampedMaximumDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? min(durationRange.upperBound, max(durationRange.lowerBound, duration)) : 60
    }
}

/// Acoustic silence, not time since the last transcript. A brief click cannot start an utterance.
struct TranslationSilenceDetector {
    static let noSpeechTimeout: TimeInterval = 20
    let options: TranslationRecordingOptions
    private(set) var hasSpeech = false
    private(set) var lastVoiceTime: TimeInterval = 0
    private var voicedDuration: TimeInterval = 0
    private var previousTime: TimeInterval = 0

    init(options: TranslationRecordingOptions) { self.options = options }

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
        guard speaker == .me, options.automaticallyEndsMyTurn else { return false }
        return elapsed >= options.maximumDuration || hasSpeech && elapsed - lastVoiceTime >= options.silenceDuration
    }

    func remainingSilence(at elapsed: TimeInterval) -> TimeInterval? {
        hasSpeech ? max(0, options.silenceDuration - (elapsed - lastVoiceTime)) : nil
    }
}

/// Split long transcripts without discarding text or sending previous turns as context.
enum TranslationTranscript {
    static func chunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var remaining = text[...]
        while remaining.unicodeScalars.count > TranslationInput.maximumLength {
            // Stay on Character boundaries, including Thai marks and emoji sequences.
            var end = remaining.startIndex
            var length = 0
            var boundary: String.Index?
            while end < remaining.endIndex {
                let character = remaining[end]
                let nextLength = length + character.unicodeScalars.count
                guard nextLength <= TranslationInput.maximumLength else { break }
                length = nextLength
                end = remaining.index(after: end)
                if character.isWhitespace || ".!?。！？".contains(character) { boundary = end }
            }
            // An unusually large single grapheme is left for the existing validation to reject.
            guard end != remaining.startIndex else { break }
            let split = boundary ?? end
            chunks.append(String(remaining[..<split]))
            remaining = remaining[split...]
        }
        if !remaining.isEmpty { chunks.append(String(remaining)) }
        return chunks
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
