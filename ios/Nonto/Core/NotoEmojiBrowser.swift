import Foundation
import Observation

enum NotoEmojiScope: Hashable, Identifiable, Sendable {
    case recent, favorites, all, category(String)
    var id: String {
        switch self {
        case .recent: return "recent"
        case .favorites: return "favorites"
        case .all: return "all"
        case .category(let name): return "category/" + name
        }
    }
    var title: String {
        switch self {
        case .recent: return "最近使用"
        case .favorites: return "收藏"
        case .all: return "全部表情"
        case .category(let name): return name
        }
    }
    var symbol: String {
        switch self {
        case .recent: return "clock"
        case .favorites: return "star"
        case .all: return "square.grid.2x2"
        case .category("笑脸与情感"): return "face.smiling"
        case .category("人物与手势"): return "hand.wave"
        case .category("动物与自然"): return "pawprint"
        case .category("食物与饮品"): return "fork.knife"
        case .category("活动与节日"): return "party.popper"
        case .category("旅行与地点"): return "car"
        case .category("物品"): return "lightbulb"
        case .category("符号"): return "heart.circle"
        case .category("旗帜"): return "flag"
        case .category: return "square.grid.2x2"
        }
    }
}

struct NotoEmojiFilter: Equatable {
    let scope: NotoEmojiScope
    let query: String
}

/// Build searchable strings and category buckets once, rather than for every
/// cell, keystroke token, selection highlight and preview redraw.
struct NotoEmojiSearchIndex: Sendable {
    private struct Entry: Sendable {
        let item: NotoEmoji
        let text: String
        let keywords: Set<String>
    }
    static let catalog = NotoEmojiSearchIndex(items: NotoEmojiCatalog.all)
    let all: [NotoEmoji]
    private let categories: [String: [NotoEmoji]]
    private let entries: [Entry]
    private static let aliases = [
        "开心": ["开心", "高兴", "快乐"],
        "难过": ["难过", "伤心", "悲伤"],
        "笑哭": ["笑哭", "喜极而泣", "笑得满地打滚"],
        "爱心": ["爱心", "红心", "heart"],
        "可爱": ["可爱", "cute"]
    ]
    init(items: [NotoEmoji]) {
        all = items
        categories = Dictionary(grouping: items, by: \.category)
        entries = items.map { item in
            Entry(item: item, text: Self.normalize("\(item.emoji) \(item.name) \(item.keywords) \(item.category)"),
                  keywords: Set(Self.normalize("\(item.name) \(item.keywords)").lowercased().split(separator: " ").map(String.init)))
        }
    }
    static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FE0F}", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func items(in category: String) -> [NotoEmoji] { categories[category] ?? [] }
    func search(_ query: String) -> [NotoEmoji] {
        let tokens = Self.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return all }
        let requirements = tokens.map { (query: $0, aliases: Self.aliases[$0]) }
        return entries.compactMap { entry in
            let matches = requirements.allSatisfy { requirement in
                // Expanding 开心 to 高兴 must not also match 不高兴.
                if let aliases = requirement.aliases { return aliases.contains { entry.keywords.contains($0) } }
                return entry.text.localizedStandardContains(requirement.query)
            }
            return matches ? entry.item : nil
        }
    }
}

@MainActor @Observable final class NotoEmojiBrowser {
    var query = "" {
        didSet {
            guard NotoEmojiSearchIndex.normalize(query) != NotoEmojiSearchIndex.normalize(oldValue) else { return }
            selection = nil; error = nil; refresh()
        }
    }
    private(set) var scope: NotoEmojiScope
    private(set) var items: [NotoEmoji]
    private(set) var selection: NotoEmoji?
    private(set) var favoriteIDs: Set<String>
    private(set) var error: String?
    private(set) var hasSent = false
    let scopes: [NotoEmojiScope]
    let canFavorite: Bool
    private let index: NotoEmojiSearchIndex
    private let recents: NotoEmojiRecents
    private let favorites: NotoEmojiFavorites

    init(accountID: Int, defaults: UserDefaults = .standard, index: NotoEmojiSearchIndex = .catalog) {
        self.index = index
        let recentStore = NotoEmojiRecents(accountID: accountID, defaults: defaults)
        let favoriteStore = NotoEmojiFavorites(accountID: accountID, defaults: defaults)
        recents = recentStore; favorites = favoriteStore
        canFavorite = accountID > 0
        let recentItems = recentStore.items, favoriteItems = favoriteStore.items
        favoriteIDs = Set(favoriteItems.map(\.id))
        if !recentItems.isEmpty { scope = .recent; items = recentItems }
        else if !favoriteItems.isEmpty { scope = .favorites; items = favoriteItems }
        else { scope = .all; items = index.all }
        scopes = [.recent, .favorites, .all] + NotoEmojiCatalog.categories
            .filter { !index.items(in: $0).isEmpty }.map(NotoEmojiScope.category)
    }
    var isSearching: Bool { !NotoEmojiSearchIndex.normalize(query).isEmpty }
    var filter: NotoEmojiFilter { NotoEmojiFilter(scope: scope, query: NotoEmojiSearchIndex.normalize(query)) }
    var title: String { isSearching ? "搜索结果" : scope.title }
    func show(_ value: NotoEmojiScope) {
        guard !hasSent, scopes.contains(value), scope != value || isSearching else { return }
        scope = value; selection = nil; error = nil
        if isSearching { query = "" } else { refresh() }
    }
    func select(_ item: NotoEmoji) {
        guard !hasSent else { return }
        if selection != item { selection = item }
        error = nil
    }
    func toggleFavorite(_ item: NotoEmoji) {
        guard canFavorite else { return }
        favorites.toggle(item)
        favoriteIDs = Set(favorites.items.map(\.id))
        if scope == .favorites && !isSearching { refresh() }
    }
    @discardableResult func send(using accept: (NotoEmoji) -> Bool) -> Bool {
        guard let selection, !hasSent else { return false }
        hasSent = true
        guard accept(selection) else {
            hasSent = false; error = "暂时无法发送，请返回聊天检查登录状态"
            return false
        }
        recents.record(selection); error = nil
        return true
    }
    private func refresh() {
        if isSearching { items = index.search(query); return }
        switch scope {
        case .all: items = index.all
        case .recent: items = recents.items
        case .favorites: items = favorites.items
        case .category(let name): items = index.items(in: name)
        }
    }
}
