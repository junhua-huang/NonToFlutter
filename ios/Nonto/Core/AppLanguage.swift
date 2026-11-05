import Foundation

/// A device preference, independent of account data and the system's language setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    static let storageKey = "nonto.native.language"
    static let supported = ["zh-Hans", "zh-Hant", "en"]
    var id: String { rawValue }

    func resolvedLanguage(preferences: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(from: Self.supported, forPreferences: preferences).first ?? "zh-Hans"
    }

    func locale(base: Locale = .current) -> Locale {
        guard self != .system else { return base }
        var components = Locale.Components(locale: base)
        let language = Locale.Language.Components(identifier: rawValue)
        components.languageComponents.languageCode = language.languageCode
        components.languageComponents.script = language.script
        return Locale(components: components)
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .system
    }
}
