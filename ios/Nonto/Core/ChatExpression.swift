import Foundation

enum ChatAttachmentAction: String, CaseIterable, Identifiable {
    case camera, photos, stickers, emoji
    var id: String { rawValue }
    var title: String {
        switch self {
        case .camera: return "相机"
        case .photos: return "照片"
        case .emoji: return "表情"
        case .stickers: return "贴纸"
        }
    }
}

struct ChatAttachmentRequest: Identifiable {
    let id = UUID()
    let action: ChatAttachmentAction
}

enum ChatExpressionTab: String, CaseIterable, Identifiable, Hashable {
    case recent, stickers, emoji, noto
    var id: String { rawValue }
    var title: String {
        switch self { case .recent: return "最近"; case .stickers: return "贴纸"; case .emoji: return "表情"; case .noto: return "动态贴纸" }
    }
    var symbol: String {
        switch self { case .recent: return "clock"; case .stickers: return "square.on.circle"; case .emoji: return "face.smiling"; case .noto: return "sparkles" }
    }
}

/// Choosing a sticker creates an attachment. Choosing an emoji edits the text instead.
struct StagedChatSticker: Identifiable, Equatable {
    enum Source: Equatable { case saved(ChatSticker), noto(NotoEmoji) }
    let id = UUID()
    let source: Source
    var name: String { switch source { case .saved(let item): return item.name; case .noto(let item): return item.name } }
    var notoEmoji: NotoEmoji? { switch source { case .saved(let item): return item.notoEmoji; case .noto(let item): return item } }
    var imageURL: String? { if case .saved(let item) = source { return item.url }; return nil }
    var sourceID: String { switch source { case .saved(let item): return "saved:" + item.id.uuidString; case .noto(let item): return "noto:" + item.id } }
}

struct NotoStickerHistory {
    struct Use: Codable { let id: String; let date: Date }
    let accountID: Int
    var defaults: UserDefaults = .standard
    private var key: String { "nonto.native.noto-sticker-history.\(accountID)" }
    var items: [Use] {
        guard accountID > 0, let data = defaults.data(forKey: key),
              let rows = try? JSONDecoder().decode([Use].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(rows.filter { NotoEmojiCatalog.item(id: $0.id) != nil && seen.insert($0.id).inserted }.prefix(24))
    }
    func record(_ item: NotoEmoji) {
        guard accountID > 0 else { return }
        let rows = [Use(id: item.id, date: Date())] + items.filter { $0.id != item.id }
        if let data = try? JSONEncoder().encode(Array(rows.prefix(24))) { defaults.set(data, forKey: key) }
    }
}

enum ChatEmojiInsertion {
    static func insert(_ emoji: String, into text: String, selection: NSRange?) -> ComposerReferenceInsertion.Result {
        let safe = ComposerReferenceInsertion.safeSelection(selection, in: text)
        let range = Range(safe, in: text) ?? text.endIndex..<text.endIndex
        var result = text; result.replaceSubrange(range, with: emoji)
        return .init(text: result, caretUTF16: safe.location + emoji.utf16.count)
    }
}
