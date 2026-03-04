import Foundation

@MainActor
final class SettingsStore {
    private enum Keys {
        static let brokerURL = "brokerURL"
        static let autoPaste = "autoPaste"
        static let restoreClipboard = "restoreClipboard"
        static let finalizationTailMs = "finalizationTailMs"
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

    var restoreClipboard: Bool {
        get { defaults.bool(forKey: Keys.restoreClipboard) }
        set { defaults.set(newValue, forKey: Keys.restoreClipboard) }
    }

    var finalizationTailMs: Int {
        get {
            let value = defaults.integer(forKey: Keys.finalizationTailMs)
            return value > 0 ? value : 1800
        }
        set {
            defaults.set(max(300, newValue), forKey: Keys.finalizationTailMs)
        }
    }

    private func registerDefaultsIfNeeded() {
        defaults.register(defaults: [
            Keys.brokerURL: "http://127.0.0.1:8787/token",
            Keys.autoPaste: true,
            Keys.restoreClipboard: true,
            Keys.finalizationTailMs: 1800
        ])
    }
}
