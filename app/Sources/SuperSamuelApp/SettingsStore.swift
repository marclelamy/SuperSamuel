import Foundation

@MainActor
final class SettingsStore {
    private enum Keys {
        static let brokerURL = "brokerURL"
        static let autoPaste = "autoPaste"
        static let restoreClipboard = "restoreClipboard"
        static let apiKey = "apiKey"
        static let transcriptionContext = "transcriptionContext"
        static let customVocabulary = "customVocabulary"
        static let openRouterAPIKey = "openRouterAPIKey"
        static let openRouterModel = "openRouterModel"
        static let openRouterCleanupPrompt = "openRouterCleanupPrompt"
        static let aiCleanupEnabledByDefault = "aiCleanupEnabledByDefault"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaultsIfNeeded()
    }

    var brokerURL: URL {
        get {
            let raw = defaults.string(forKey: Keys.brokerURL) ?? "http://127.0.0.1:8787/token"
            return URL(string: raw) ?? URL(string: "http://127.0.0.1:8787/token")!
        }
        set {
            defaults.set(newValue.absoluteString, forKey: Keys.brokerURL)
        }
    }

    var autoPaste: Bool {
        get { defaults.bool(forKey: Keys.autoPaste) }
        set { defaults.set(newValue, forKey: Keys.autoPaste) }
    }

    var apiKey: String {
        get { defaults.string(forKey: Keys.apiKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.apiKey) }
    }

    var openRouterAPIKey: String {
        get { defaults.string(forKey: Keys.openRouterAPIKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.openRouterAPIKey) }
    }

    var openRouterModel: String {
        get {
            let value = defaults.string(forKey: Keys.openRouterModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? OpenRouterService.defaultModel : value
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? OpenRouterService.defaultModel : trimmed, forKey: Keys.openRouterModel)
        }
    }

    var openRouterCleanupPrompt: String {
        get { defaults.string(forKey: Keys.openRouterCleanupPrompt) ?? OpenRouterService.defaultCleanupInstruction }
        set { defaults.set(newValue, forKey: Keys.openRouterCleanupPrompt) }
    }

    var aiCleanupEnabledByDefault: Bool {
        get { defaults.bool(forKey: Keys.aiCleanupEnabledByDefault) }
        set { defaults.set(newValue, forKey: Keys.aiCleanupEnabledByDefault) }
    }

    var transcriptionContext: String {
        get { defaults.string(forKey: Keys.transcriptionContext) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.transcriptionContext) }
    }

    var customVocabulary: String {
        get { defaults.string(forKey: Keys.customVocabulary) ?? "" }
        set { defaults.set(newValue, forKey: Keys.customVocabulary) }
    }

    var customVocabularyTerms: [String] {
        customVocabulary
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var restoreClipboard: Bool {
        get { defaults.bool(forKey: Keys.restoreClipboard) }
        set { defaults.set(newValue, forKey: Keys.restoreClipboard) }
    }

    var hasOpenRouterCleanupConfiguration: Bool {
        !openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func registerDefaultsIfNeeded() {
        defaults.register(defaults: [
            Keys.brokerURL: "http://127.0.0.1:8787/token",
            Keys.autoPaste: true,
            Keys.restoreClipboard: true,
            Keys.apiKey: "",
            Keys.transcriptionContext: "",
            Keys.customVocabulary: "",
            Keys.openRouterAPIKey: "",
            Keys.openRouterModel: OpenRouterService.defaultModel,
            Keys.openRouterCleanupPrompt: OpenRouterService.defaultCleanupInstruction,
            Keys.aiCleanupEnabledByDefault: true
        ])
    }
}
