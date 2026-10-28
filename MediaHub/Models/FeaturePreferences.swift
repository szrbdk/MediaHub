import Foundation

protocol PreferenceStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

final class FeaturePreferences {
    enum Feature: String {
        case notifications = "notificationsEnabled"
        case touchBar = "touchBarEnabled"
        case autoSkip = "autoSkipEnabled"
    }

    private let store: PreferenceStore

    init(store: PreferenceStore = UserDefaults.standard) { self.store = store }

    func isEnabled(_ feature: Feature) -> Bool {
        // Preserve the current behavior for installations without saved choices.
        store.object(forKey: feature.rawValue) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, for feature: Feature) {
        store.set(enabled, forKey: feature.rawValue)
    }
}
