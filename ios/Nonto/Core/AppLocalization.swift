import Foundation

/// In-app language selection is shared by SwiftUI and imperative UI strings.
/// Protocol markers, identifiers and user-authored content never pass through this type.
enum AppLocalization {
    static var language: String { AppLanguage.stored().resolvedLanguage() }
    static var locale: Locale { AppLanguage.stored().locale() }

    private static let languageBundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.supported.compactMap { language in
        guard let url = Bundle.main.url(forResource: language, withExtension: "lproj"), let bundle = Bundle(url: url) else { return nil }
        return (language, bundle)
    })

    static func resourceBundle(in bundle: Bundle = .main) -> Bundle {
        guard bundle == .main else { return bundle }
        return languageBundles[language] ?? bundle
    }

    /// Selecting the resource bundle is necessary: String's locale argument only formats values.
    static func string(_ value: String.LocalizationValue, table: String? = nil, comment: StaticString? = nil) -> String {
        String(localized: value, table: table, bundle: resourceBundle(), locale: locale, comment: comment)
    }

    static func lookup(_ key: String, table: String? = nil, bundle: Bundle = .main) -> String {
        resourceBundle(in: bundle).localizedString(forKey: key, value: key, table: table)
    }

    private struct MessageKey: Hashable { let key: String; let table: String }
    // These are read from the compiled catalogs, so cached status/error copy can
    // change language without touching the stored value or user-authored text.
    private static let storedMessageKeys: [String: Set<MessageKey>] = {
        var result: [String: Set<MessageKey>] = [:]
        for bundle in languageBundles.values {
            for table in ["Localizable", "ServerErrors"] {
                guard let url = bundle.url(forResource: table, withExtension: "strings"),
                      let data = try? Data(contentsOf: url),
                      let values = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String] else { continue }
                for (key, value) in values where !key.contains("%") {
                    let message = MessageKey(key: key, table: table)
                    result[key, default: []].insert(message)
                    result[value, default: []].insert(message)
                }
            }
        }
        return result
    }()

    /// Use only for app-owned status and error strings, never posts, names or messages.
    static func relocalizedUI(_ value: String) -> String {
        guard let keys = storedMessageKeys[value] else { return value }
        let translations = Set(keys.map { lookup($0.key, table: $0.table) })
        guard translations.count == 1, let translation = translations.first else { return value }
        return translation
    }


    static func emojiCategory(_ category: String) -> String {
        switch category {
        case "笑脸与情感": return string("笑脸与情感")
        case "人物与手势": return string("人物与手势")
        case "动物与自然": return string("动物与自然")
        case "食物与饮品": return string("食物与饮品")
        case "活动与节日": return string("活动与节日")
        case "旅行与地点": return string("旅行与地点")
        case "物品": return string("物品")
        case "符号": return string("符号")
        case "旗帜": return string("旗帜")
        default: return category
        }
    }

    private static let emojiNames: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "EmojiNames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return names
    }()
    static func emojiSearchNames(_ item: NotoEmoji) -> String {
        ([item.name] + Array(emojiNames[item.id, default: [:]].values)).joined(separator: " ")
    }
    static func emojiName(_ item: NotoEmoji) -> String {
        emojiNames[item.id]?[language] ?? item.name
    }

    /// Exact catalog keys keep unknown future disclosures intact instead of showing stale translations.
    static func configText(_ text: String, key: String) -> String {
        guard ["storageSummary", "retentionSummary", "processorSummary", "minorProtectionSummary",
               "realNameVerificationSummary", "rightsResponseSummary"].contains(key), !text.isEmpty else { return text }
        return lookup(text, table: "PolicyDetails")
    }

    /// Only fixed service error messages have entries. Account names and submitted content are untouched.
    static func serverError(_ text: String, bundle: Bundle = .main) -> String {
        lookup(text, table: "ServerErrors", bundle: bundle)
    }
}
