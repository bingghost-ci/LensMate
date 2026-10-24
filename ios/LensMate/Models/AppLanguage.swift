import Foundation

/// UI language only; independent of speech recognition, voices and model prompts.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    static let defaultsKey = "appLanguage"
    var id: String { rawValue }

    static var current: AppLanguage {
        load(from: .standard)
    }

    static func load(from defaults: UserDefaults) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Respect the primary OS language. An unsupported primary language falls back
    /// to English even when Chinese appears later in the OS preference list.
    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .english: return "en"
        case .chinese: return "zh-Hans"
        case .system:
            let primary = preferredLanguages.first ?? "en"
            let code = primary.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first?.lowercased()
            return code == "zh" ? "zh-Hans" : "en"
        }
    }
}

/// For app-owned messages created outside SwiftUI. Selecting the language bundle
/// explicitly also enforces English fallback when the OS language is unsupported.
enum L10n {
    static func text(_ value: String.LocalizationValue,
                     language: AppLanguage = .current,
                     preferredLanguages: [String] = Locale.preferredLanguages,
                     bundle: Bundle = .main) -> String {
        let identifier = language.resolvedIdentifier(preferredLanguages: preferredLanguages)
        return text(value, locale: Locale(identifier: identifier), bundle: bundle)
    }

    static func text(_ value: String.LocalizationValue, locale: Locale, bundle: Bundle = .main) -> String {
        let identifier = AppLanguage.system.resolvedIdentifier(preferredLanguages: [locale.identifier])
        let localizedBundle = bundle.path(forResource: identifier, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? bundle
        return String(localized: value, bundle: localizedBundle, locale: locale)
    }
}
