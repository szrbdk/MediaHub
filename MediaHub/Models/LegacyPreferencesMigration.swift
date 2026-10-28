import Foundation

enum LegacyPreferencesMigration {
    static let legacyDomain = "com.sezerbudak.MediaBar"
    private static let marker = "didMigrateMediaBarPreferences"

    static func migrate(store: PreferenceStore, legacyValues: [String: Any]) {
        guard store.object(forKey: marker) as? Bool != true else { return }
        for key in ["notificationsEnabled", "touchBarEnabled", "autoSkipEnabled", "appLanguage"] {
            if store.object(forKey: key) == nil, let value = legacyValues[key] {
                store.set(value, forKey: key)
            }
        }
        store.set(true, forKey: marker)
    }
}
