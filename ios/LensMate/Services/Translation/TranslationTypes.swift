import Foundation

/// Translation languages are independent of the app's interface language.
enum TranslationLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese, english, thai
    var id: String { rawValue }

    var title: String.LocalizationValue {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .thai: return "Thai"
        }
    }

    var apiName: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .thai: return "Thai"
        }
    }

    var voiceLanguage: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .thai: return "th-TH"
        }
    }
}

enum TranslationRegion: String, CaseIterable, Identifiable, Sendable {
    case beijing, singapore
    var id: String { rawValue }
    var title: String.LocalizationValue {
        self == .beijing ? "China (Beijing)" : "Singapore"
    }

    // These official shared domains remain supported. Never accept a user-supplied host.
    var endpoint: URL {
        let host = self == .beijing ? "dashscope.aliyuncs.com" : "dashscope-intl.aliyuncs.com"
        return URL(string: "https://\(host)/compatible-mode/v1/chat/completions")!
    }
}

struct TranslationCredentials: Sendable {
    let region: TranslationRegion
    let apiKey: String
}

struct TranslationInput: Equatable, Sendable {
    static let maximumLength = 2_000
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage

    func validate() throws {
        guard source != target else { throw TranslationError.sameLanguage }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyInput
        }
        guard text.unicodeScalars.count <= Self.maximumLength else { throw TranslationError.inputTooLong }
    }
}

struct TranslationResult: Equatable {
    let input: TranslationInput
    let text: String
}

enum TranslationError: Error, Equatable {
    case notConfigured, emptyInput, inputTooLong, sameLanguage, invalidCredential
    case credentialRead, credentialSave, credentialDelete
    case authentication, rateLimited, modelUnavailable, rejected, serviceUnavailable
    case invalidResponse, incompleteResponse, timedOut, network
    case voiceUnavailable, audioUnavailable

    var message: String.LocalizationValue {
        switch self {
        case .notConfigured: return "Choose an Aliyun region and save its API key in Translation Settings."
        case .emptyInput: return "Enter text to translate."
        case .inputTooLong: return "Use at most 2,000 characters per translation."
        case .sameLanguage: return "Choose different source and target languages."
        case .invalidCredential: return "Enter a valid API key without spaces or line breaks."
        case .credentialRead: return "The translation API key could not be read from Keychain. Unlock your iPhone and try again."
        case .credentialSave: return "The API key could not be saved to Keychain. Your previous configuration is unchanged."
        case .credentialDelete: return "The API key could not be removed from Keychain. Try again."
        case .authentication: return "Aliyun rejected this API key. Check its region, permissions and account status."
        case .rateLimited: return "Aliyun is limiting requests. Please try again later."
        case .modelUnavailable: return "The translation model is unavailable. Check access to qwen-mt-flash in your selected region."
        case .rejected: return "Aliyun rejected this translation. Check the text and your model access."
        case .serviceUnavailable: return "The translation service is unavailable. Please try again later."
        case .invalidResponse: return "The translation service returned an invalid or empty result. Please try again."
        case .incompleteResponse: return "The translation was incomplete. Try a shorter text."
        case .timedOut: return "Translation timed out. Check your connection and try again."
        case .network: return "Could not connect to Aliyun. Check your connection and try again."
        case .voiceUnavailable: return "No installed system voice is available for the target language. Download a voice in iPhone Settings > Accessibility > Read & Speak (or Spoken Content) > Voices, then replay."
        case .audioUnavailable: return "Could not start iPhone speech. Stop other audio and try replaying."
        }
    }
}
