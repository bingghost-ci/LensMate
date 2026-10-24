import XCTest
@testable import LensMate

final class AppLanguageTests: XCTestCase {
    func testChineseSystemVariantsUseSimplifiedChinese() {
        for language in ["zh", "zh-CN", "zh-Hans-CN", "zh-Hant-TW", "zh-HK", "zh_SG", "ZH-cn"] {
            XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: [language]), "zh-Hans")
        }
    }

    func testUnsupportedPrimaryLanguageFallsBackToEnglish() {
        for languages in [["th-TH"], ["fr-FR", "zh-Hans"], ["ja-JP", "en-US"], [""], []] {
            XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: languages), "en")
        }
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB"]), "en")
    }

    func testExplicitChoiceOverridesSystemLanguage() {
        XCTAssertEqual(AppLanguage.chinese.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hant"]), "en")
    }

    func testPreferencePersistenceAndOldInstallDefaults() {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppLanguage.load(from: defaults), .system)
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            XCTAssertEqual(AppLanguage.load(from: UserDefaults(suiteName: suite)!), language)
        }
        defaults.set("obsolete", forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(AppLanguage.load(from: defaults), .system)
    }

    func testBundledTranslationsAndFormattedMessages() {
        XCTAssertEqual(L10n.text("Settings", language: .english), "Settings")
        XCTAssertEqual(L10n.text("Settings", language: .chinese), "设置")
        XCTAssertEqual(L10n.text("Follow System", language: .chinese), "跟随系统")
        XCTAssertEqual(L10n.text("Settings", language: .system, preferredLanguages: ["th-TH", "zh-Hans"]), "Settings")
        XCTAssertEqual(L10n.text("Settings", language: .system, preferredLanguages: ["zh-TW"]), "设置")
        let name = "OpenAI"
        XCTAssertEqual(L10n.text("Please configure \(name) in Settings", language: .chinese), "请在设置中配置 OpenAI")
        let count = 3
        XCTAssertEqual(L10n.text("\(count) memories", language: .chinese), "3 条记忆")
    }
}
