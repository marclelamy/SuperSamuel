import Foundation
import Security

@MainActor
final class SettingsStore {
    private enum Keys {
        static let autoPaste = "autoPaste"
        static let restoreClipboard = "restoreClipboard"
        static let legacyOpenRouterAPIKey = "openRouterAPIKey"
        static let cleanupModel = "openRouterModel"
        static let cleanupPrompt = "openRouterCleanupPrompt"
        static let cleanupEnabledByDefault = "aiCleanupEnabledByDefault"
    }

    private let defaults: UserDefaults
    private let credentials: CredentialStore

    init(
        defaults: UserDefaults = .standard,
        credentials: CredentialStore = CredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
        registerDefaults()
        migrateLegacyAPIKey()
    }

    var autoPaste: Bool {
        get { defaults.bool(forKey: Keys.autoPaste) }
        set { defaults.set(newValue, forKey: Keys.autoPaste) }
    }

    var restoreClipboard: Bool {
        get { defaults.bool(forKey: Keys.restoreClipboard) }
        set { defaults.set(newValue, forKey: Keys.restoreClipboard) }
    }

    var openRouterAPIKey: String {
        get { credentials.readAPIKey() ?? "" }
        set {
            do {
                try credentials.writeAPIKey(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                print("Could not save OpenRouter API key: \(error.localizedDescription)")
            }
        }
    }

    var cleanupModel: String {
        get {
            let value = defaults.string(forKey: Keys.cleanupModel)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? OpenRouterService.defaultCleanupModel : value
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(
                value.isEmpty ? OpenRouterService.defaultCleanupModel : value,
                forKey: Keys.cleanupModel
            )
        }
    }

    var cleanupPrompt: String {
        get {
            defaults.string(forKey: Keys.cleanupPrompt)
                ?? OpenRouterService.defaultCleanupInstruction
        }
        set { defaults.set(newValue, forKey: Keys.cleanupPrompt) }
    }

    var cleanupEnabledByDefault: Bool {
        get { defaults.bool(forKey: Keys.cleanupEnabledByDefault) }
        set { defaults.set(newValue, forKey: Keys.cleanupEnabledByDefault) }
    }

    var hasOpenRouterAPIKey: Bool {
        !openRouterAPIKey.isEmpty
    }

    var hasCleanupConfiguration: Bool {
        hasOpenRouterAPIKey && !cleanupModel.isEmpty
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.autoPaste: true,
            Keys.restoreClipboard: true,
            Keys.cleanupModel: OpenRouterService.defaultCleanupModel,
            Keys.cleanupPrompt: OpenRouterService.defaultCleanupInstruction,
            Keys.cleanupEnabledByDefault: true
        ])
    }

    private func migrateLegacyAPIKey() {
        guard credentials.readAPIKey() == nil else {
            defaults.removeObject(forKey: Keys.legacyOpenRouterAPIKey)
            return
        }

        let legacyKey = defaults.string(forKey: Keys.legacyOpenRouterAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !legacyKey.isEmpty else {
            return
        }

        do {
            try credentials.writeAPIKey(legacyKey)
            defaults.removeObject(forKey: Keys.legacyOpenRouterAPIKey)
        } catch {
            print("Could not migrate OpenRouter API key to Keychain: \(error.localizedDescription)")
        }
    }
}

final class CredentialStore {
    private let service: String
    private let account = "openrouter-api-key"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.supersamuel.app") {
        self.service = service
    }

    func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func writeAPIKey(_ apiKey: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if apiKey.isEmpty {
            let status = SecItemDelete(lookup as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychain(status)
            }
            return
        }

        let data = Data(apiKey.utf8)
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var item = lookup
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }
}

private enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain error \(status)"
        }
    }
}
