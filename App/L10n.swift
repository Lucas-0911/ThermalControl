import Foundation
import SwiftUI

final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    static let storageKey = AppSettings.Key.appLanguage

    @Published var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: Self.storageKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey) ?? "system"
        selection = ["system", "en", "vi"].contains(saved) ? saved : "system"
    }

    var code: String {
        if selection == "en" || selection == "vi" { return selection }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("vi") ? "vi" : "en"
    }

    var locale: Locale { Locale(identifier: code) }

    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}

enum L10n {
    static func t(_ key: String) -> String {
        let bundle = LanguageSettings.shared.bundle
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if value != key { return value }
        return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: LanguageSettings.shared.locale, arguments: args)
    }
}
