import Security
import XCTest
@testable import LensMate

@MainActor
final class TranslationConfigurationTests: XCTestCase {
    func testRegionKeysStaySeparateAndOnlyRegionIsPersisted() throws {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryTranslationCredentials()
        let configuration = TranslationConfiguration(defaults: defaults, store: store)
        XCTAssertNil(configuration.region)
        XCTAssertThrowsError(try configuration.credentials())
        try configuration.save(region: .beijing, key: "beijing-secret")
        try configuration.save(region: .singapore, key: "singapore-secret")
        XCTAssertEqual(try configuration.credentials().apiKey, "singapore-secret")
        try configuration.save(region: .beijing, key: "")
        XCTAssertEqual(try configuration.credentials().apiKey, "beijing-secret")
        let persisted = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertEqual(Set(persisted.keys), [TranslationConfiguration.regionKey])
        XCTAssertEqual(persisted[TranslationConfiguration.regionKey] as? String, "beijing")
        let reopened = TranslationConfiguration(defaults: defaults, store: store)
        XCTAssertEqual(try reopened.credentials().apiKey, "beijing-secret")
    }

    func testSaveFailureDoesNotCommitRegionOrFallbackToPreferences() throws {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryTranslationCredentials()
        let configuration = TranslationConfiguration(defaults: defaults, store: store)
        try configuration.save(region: .beijing, key: "old-secret")
        store.failWrite = true
        XCTAssertThrowsError(try configuration.save(region: .singapore, key: "new-secret")) {
            XCTAssertEqual($0 as? TranslationError, .credentialSave)
        }
        XCTAssertEqual(configuration.region, .beijing)
        XCTAssertEqual(try configuration.credentials().apiKey, "old-secret")
        XCTAssertNil(store.keys[.singapore])
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as? [String: String], [TranslationConfiguration.regionKey: "beijing"])
    }

    func testMissingKeyReadFailureAndDeleteFailureRemainExplicit() throws {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryTranslationCredentials()
        let configuration = TranslationConfiguration(defaults: defaults, store: store)
        XCTAssertThrowsError(try configuration.save(region: .singapore, key: ""))
        XCTAssertNil(configuration.region)
        try configuration.save(region: .singapore, key: "test-secret")
        store.failRead = true
        XCTAssertThrowsError(try configuration.credentials()) { XCTAssertEqual($0 as? TranslationError, .credentialRead) }
        store.failRead = false
        store.failDelete = true
        XCTAssertThrowsError(try configuration.removeKey(for: .singapore)) { XCTAssertEqual($0 as? TranslationError, .credentialDelete) }
        XCTAssertTrue(try configuration.hasKey(for: .singapore))
        store.failDelete = false
        try configuration.removeKey(for: .singapore)
        XCTAssertThrowsError(try configuration.credentials()) { XCTAssertEqual($0 as? TranslationError, .notConfigured) }
    }

    func testRealKeychainRoundTripAndFailedUpdatePreserveOldValue() throws {
        var store = TranslationKeychainStore(service: "LensMate.TranslationTests.\(UUID().uuidString)")
        defer { try? store.delete(for: .beijing); try? store.delete(for: .singapore) }
        XCTAssertNil(try store.read(for: .beijing))
        try store.write("first-test-key", for: .beijing)
        try store.write("second-test-key", for: .beijing)
        XCTAssertEqual(try store.read(for: .beijing), "second-test-key")
        XCTAssertNil(try store.read(for: .singapore))
        var attemptedAdd = false
        store.update = { _, _ in errSecInteractionNotAllowed }
        store.add = { _, _ in attemptedAdd = true; return errSecSuccess }
        XCTAssertThrowsError(try store.write("replacement", for: .beijing)) { XCTAssertEqual($0 as? TranslationError, .credentialSave) }
        XCTAssertFalse(attemptedAdd)
        XCTAssertEqual(try store.read(for: .beijing), "second-test-key")
    }

    func testFailedKeychainAddDoesNotCreateConfiguration() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = TranslationKeychainStore(service: "LensMate.TranslationTests.\(UUID().uuidString)")
        store.update = { _, _ in errSecItemNotFound }
        store.add = { _, _ in errSecInteractionNotAllowed }
        let configuration = TranslationConfiguration(defaults: defaults, store: store)
        XCTAssertThrowsError(try configuration.save(region: .singapore, key: "never-persist-this")) {
            XCTAssertEqual($0 as? TranslationError, .credentialSave)
        }
        XCTAssertNil(configuration.region)
        XCTAssertNil(defaults.string(forKey: TranslationConfiguration.regionKey))
        XCTAssertFalse((defaults.persistentDomain(forName: suite) ?? [:]).values.contains { String(describing: $0).contains("never-persist-this") })
    }

    private func isolatedDefaults() -> (String, UserDefaults) {
        let suite = "LensMate.TranslationTests.\(UUID().uuidString)"
        return (suite, UserDefaults(suiteName: suite)!)
    }
}

private final class MemoryTranslationCredentials: TranslationCredentialStore {
    var keys: [TranslationRegion: String] = [:]
    var failRead = false, failWrite = false, failDelete = false
    func read(for region: TranslationRegion) throws -> String? {
        if failRead { throw TranslationError.credentialRead }
        return keys[region]
    }
    func write(_ key: String, for region: TranslationRegion) throws {
        if failWrite { throw TranslationError.credentialSave }
        keys[region] = key
    }
    func delete(for region: TranslationRegion) throws {
        if failDelete { throw TranslationError.credentialDelete }
        keys.removeValue(forKey: region)
    }
}
