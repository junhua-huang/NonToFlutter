import Foundation

struct NotoEmoji: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let emoji: String
    let name: String
    let keywords: String
    let category: String
    var animationURL: URL? { NotoEmojiCatalog.asset(id, extension: "json") }
    var previewURL: URL? { NotoEmojiCatalog.asset(id, extension: "png") }
    func matches(_ query: String) -> Bool {
        let searchable = "\(emoji) \(name) \(keywords) \(category)"
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { searchable.localizedStandardContains(String($0)) }
    }
}

enum NotoEmojiCatalog {
    private struct Manifest: Decodable { let items: [NotoEmoji] }
    static let all: [NotoEmoji] = {
        guard let url = asset("catalog", extension: "json"), let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.items
    }()
    static let categories = ["笑脸与情感", "人物与手势", "动物与自然", "食物与饮品", "活动与节日", "旅行与地点", "物品", "符号", "旗帜"]
    private static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let byEmoji = Dictionary(all.map { (canonical($0.emoji), $0) }, uniquingKeysWith: { first, _ in first })
    static func item(id: String) -> NotoEmoji? { byID[id] }
    static func asset(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "NotoEmoji")
    }
    private static func canonical(_ text: String) -> String { text.replacingOccurrences(of: "\u{FE0F}", with: "") }
    /// Keep standard Unicode on the wire for old clients, push previews, copies,
    /// quotes and the durable outbox. Only 1–3 supported emoji-only graphemes animate.
    static func standalone(in text: String) -> [NotoEmoji]? {
        guard text.utf16.count <= 96 else { return nil }
        let characters = text.filter { !$0.isWhitespace }
        guard (1...3).contains(characters.count) else { return nil }
        var result: [NotoEmoji] = []
        for character in characters {
            guard let item = byEmoji[canonical(String(character))] else { return nil }
            result.append(item)
        }
        return result
    }
}

struct NotoEmojiRecents {
    let accountID: Int
    var defaults: UserDefaults = .standard
    private var key: String { "nonto.native.noto-recents.\(accountID)" }
    var items: [NotoEmoji] {
        guard accountID > 0 else { return [] }
        var seen = Set<String>()
        return (defaults.stringArray(forKey: key) ?? []).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return NotoEmojiCatalog.item(id: id)
        }.prefix(24).map { $0 }
    }
    func record(_ item: NotoEmoji) {
        guard accountID > 0, NotoEmojiCatalog.item(id: item.id) != nil else { return }
        defaults.set(Array(([item.id] + items.map(\.id).filter { $0 != item.id }).prefix(24)), forKey: key)
    }
}

struct NotoEmojiFavorites {
    let accountID: Int
    var defaults: UserDefaults = .standard
    private var key: String { "nonto.native.noto-favorites.\(accountID)" }
    var items: [NotoEmoji] {
        guard accountID > 0 else { return [] }
        var seen = Set<String>()
        return (defaults.stringArray(forKey: key) ?? []).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return NotoEmojiCatalog.item(id: id)
        }
    }
    func toggle(_ item: NotoEmoji) {
        guard accountID > 0, NotoEmojiCatalog.item(id: item.id) != nil else { return }
        let existing = items.map(\.id)
        let ids = existing.contains(item.id) ? existing.filter { $0 != item.id } : [item.id] + existing
        defaults.set(ids, forKey: key)
    }
}

extension ChatMessage {
    var notoEmoji: [NotoEmoji]? {
        guard !recalled, kind.isEmpty || kind == "text" else { return nil }
        return NotoEmojiCatalog.standalone(in: content)
    }
}
