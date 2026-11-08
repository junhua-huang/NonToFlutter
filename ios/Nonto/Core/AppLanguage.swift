import Foundation

/// A device preference, independent of account data and the system's language setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case french = "fr"
    case russian = "ru"
    case spanish = "es"
    case japanese = "ja"

    static let storageKey = "nonto.native.language"
    static let supported = allCases.filter { $0 != .system }.map(\.rawValue)
    var id: String { rawValue }

    /// Autonyms stay recognizable even when the current language is unfamiliar.
    var nativeName: String {
        switch self {
        case .system: return AppLocalization.string("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .french: return "Français"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        }
    }

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
