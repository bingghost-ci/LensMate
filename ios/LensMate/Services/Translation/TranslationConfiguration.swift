import Foundation
import Security

protocol TranslationCredentialStore {
    func read(for region: TranslationRegion) throws -> String?
    func write(_ key: String, for region: TranslationRegion) throws
    func delete(for region: TranslationRegion) throws
}

/// Deliberately separate from SettingsManager's legacy secret/file fallback.
struct TranslationKeychainStore: TranslationCredentialStore {
    let service: String
    var update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate
    var add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd

    init(service: String = (Bundle.main.bundleIdentifier ?? "LensMate") + ".translation") {
        self.service = service
    }

    private func query(_ region: TranslationRegion) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: region.rawValue]
    }

    func read(for region: TranslationRegion) throws -> String? {
        var query = query(region)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw TranslationError.credentialRead }
        return key
    }

    func write(_ key: String, for region: TranslationRegion) throws {
        let query = query(region)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Update atomically: never delete a working credential before a replacement is saved.
        var status = update(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = add(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TranslationError.credentialSave }
    }

    func delete(for region: TranslationRegion) throws {
        let status = SecItemDelete(query(region) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TranslationError.credentialDelete
        }
    }
}

@MainActor
final class TranslationConfiguration: ObservableObject {
    static let shared = TranslationConfiguration()
    static let regionKey = "translation.region"
    static let silenceKey = "translation.silenceDuration"
    @Published private(set) var silenceDuration: TimeInterval
    @Published private(set) var region: TranslationRegion?
    private let defaults: UserDefaults
    private let store: any TranslationCredentialStore

    init(defaults: UserDefaults = .standard, store: any TranslationCredentialStore = TranslationKeychainStore()) {
        self.defaults = defaults
        self.store = store
        let duration = defaults.object(forKey: Self.silenceKey) as? Double ?? 5
        silenceDuration = TranslationSilenceDetector.clampedDuration(duration)
        region = defaults.string(forKey: Self.regionKey).flatMap(TranslationRegion.init(rawValue:))
    }

    func setSilenceDuration(_ duration: TimeInterval) {
        silenceDuration = TranslationSilenceDetector.clampedDuration(duration)
        defaults.set(silenceDuration, forKey: Self.silenceKey)
    }

    nonisolated static func validateKey(_ key: String) throws {
        guard !key.isEmpty, key.count <= 4_096,
              key.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw TranslationError.invalidCredential }
    }

    func hasKey(for region: TranslationRegion) throws -> Bool {
        guard let key = try store.read(for: region) else { return false }
        return !key.isEmpty
    }

    /// Empty draft preserves this region's saved key. Metadata changes only after secure save succeeds.
    func save(region: TranslationRegion, key draft: String) throws {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            guard try hasKey(for: region) else { throw TranslationError.notConfigured }
        } else {
            try Self.validateKey(key)
            do { try store.write(key, for: region) }
            catch { throw TranslationError.credentialSave }
        }
        defaults.set(region.rawValue, forKey: Self.regionKey)
        self.region = region
    }

    func removeKey(for region: TranslationRegion) throws {
        do { try store.delete(for: region) }
        catch { throw TranslationError.credentialDelete }
    }

    func credentials() throws -> TranslationCredentials {
        guard let region else { throw TranslationError.notConfigured }
        guard let key = try store.read(for: region), !key.isEmpty else { throw TranslationError.notConfigured }
        try Self.validateKey(key)
        return TranslationCredentials(region: region, apiKey: key)
    }
}
