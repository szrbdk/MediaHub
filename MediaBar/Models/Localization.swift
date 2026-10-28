import Foundation

enum AppLanguage: String, CaseIterable {
    case en, tr

    static func initial(preferredLanguages: [String]) -> AppLanguage {
        let primary = preferredLanguages.first?.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first?.lowercased()
        return primary == "tr" ? .tr : .en
    }
}

final class Localization {
    static let shared = Localization()
    private let store: PreferenceStore
    private let tables: [AppLanguage: [String: String]]
    private static let preferenceKey = "appLanguage"

    init(store: PreferenceStore = UserDefaults.standard,
         preferredLanguages: [String] = Locale.preferredLanguages,
         resourcesURL: URL? = Bundle.main.resourceURL) {
        self.store = store
        // Resolve once, including migration from the former "system" choice.
        if AppLanguage(rawValue: store.object(forKey: Self.preferenceKey) as? String ?? "") == nil {
            store.set(AppLanguage.initial(preferredLanguages: preferredLanguages).rawValue,
                      forKey: Self.preferenceKey)
        }
        var tables: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases {
            guard let url = resourcesURL?.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings"),
                  let data = try? Data(contentsOf: url),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            else { continue }
            tables[language] = table
        }
        self.tables = tables
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: store.object(forKey: Self.preferenceKey) as? String ?? "") ?? .en }
        set { store.set(newValue.rawValue, forKey: Self.preferenceKey) }
    }

    func text(_ key: String) -> String {
        // Read the selected table directly: Bundle's implicit language selection
        // and cached preferred localizations must not override an in-app choice.
        tables[language]?[key] ?? tables[.en]?[key] ?? key
    }
}

func L(_ key: String) -> String { Localization.shared.text(key) }
