import Foundation

/// System and per-app language choices share the same bundle localization.
/// Protocol markers, identifiers and user-authored content never pass through this type.
enum AppLocalization {
    static var language: String { Bundle.main.preferredLocalizations.first ?? "zh-Hans" }

    static func emojiCategory(_ category: String) -> String {
        switch category {
        case "笑脸与情感": return String(localized: "笑脸与情感")
        case "人物与手势": return String(localized: "人物与手势")
        case "动物与自然": return String(localized: "动物与自然")
        case "食物与饮品": return String(localized: "食物与饮品")
        case "活动与节日": return String(localized: "活动与节日")
        case "旅行与地点": return String(localized: "旅行与地点")
        case "物品": return String(localized: "物品")
        case "符号": return String(localized: "符号")
        case "旗帜": return String(localized: "旗帜")
        default: return category
        }
    }

    private static let emojiNames: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "EmojiNames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return names
    }()
    static func emojiName(_ item: NotoEmoji) -> String {
        emojiNames[item.id]?[language] ?? item.name
    }

    /// Exact catalog keys keep unknown future disclosures intact instead of showing stale translations.
    static func configText(_ text: String, key: String) -> String {
        guard ["storageSummary", "retentionSummary", "processorSummary", "minorProtectionSummary",
               "realNameVerificationSummary", "rightsResponseSummary"].contains(key), !text.isEmpty else { return text }
        return Bundle.main.localizedString(forKey: text, value: text, table: "PolicyDetails")
    }

    /// Only fixed service error messages have entries. Account names and submitted content are untouched.
    static func serverError(_ text: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: text, value: text, table: "ServerErrors")
    }
}
