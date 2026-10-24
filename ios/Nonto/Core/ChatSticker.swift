import Foundation

struct ChatSticker: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let url: String
    var name: String
    var lastUsed: Date? = nil
    var notoID: String? = nil
    var notoEmoji: NotoEmoji? { notoID.flatMap(NotoEmojiCatalog.item(id:)) }
    var content: String { notoEmoji.map { Self.messageContent + " " + $0.emoji } ?? Self.messageContent }

    static let messageContent = "[贴纸]"
    static func validURL(_ text: String) -> Bool {
        guard text.count <= 4096, let url = URL(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }
}

enum ChatStickerError: LocalizedError {
    case invalidImage, invalidURL, signedOut, full, saveFailed
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取这张图片，请选择不超过 20 MB 的图片。"
        case .invalidURL: return "这张图片的链接不可用，请重新添加。"
        case .signedOut: return "请登录后添加贴纸。"
        case .full: return "最多保存 120 张贴纸，请先删除不需要的贴纸。"
        case .saveFailed: return "贴纸保存失败，请重试。"
        }
    }
}

/// Keep URLs rather than image bytes in preferences. Existing image uploads are reusable.
struct ChatStickerLibrary {
    static let limit = 120
    let accountID: Int
    var defaults: UserDefaults = .standard
    private var key: String { "nonto.native.stickers.\(accountID)" }
    var items: [ChatSticker] {
        guard accountID > 0, let data = defaults.data(forKey: key),
              let rows = try? JSONDecoder().decode([ChatSticker].self, from: data) else { return [] }
        var ids = Set<UUID>(), urls = Set<String>()
        return rows.filter { ChatSticker.validURL($0.url) && ids.insert($0.id).inserted && urls.insert($0.url).inserted }
            .prefix(Self.limit).map { $0 }
    }
    @discardableResult func add(url: String, name: String = "贴纸", notoID: String? = nil) throws -> ChatSticker {
        guard accountID > 0 else { throw ChatStickerError.signedOut }
        guard ChatSticker.validURL(url) else { throw ChatStickerError.invalidURL }
        var rows = items
        if let existing = rows.first(where: { $0.url == url }) { return existing }
        guard rows.count < Self.limit else { throw ChatStickerError.full }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sticker = ChatSticker(id: UUID(), url: url, name: title.isEmpty ? "贴纸" : String(title.prefix(40)),
                                  notoID: notoID.flatMap { NotoEmojiCatalog.item(id: $0)?.id })
        rows.insert(sticker, at: 0); try save(rows)
        return sticker
    }
    func remove(_ id: UUID) throws { try save(items.filter { $0.id != id }) }
    func recordUse(_ id: UUID, at date: Date = Date()) throws {
        var rows = items
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].lastUsed = date; try save(rows)
    }
    private func save(_ rows: [ChatSticker]) throws {
        guard accountID > 0 else { throw ChatStickerError.signedOut }
        let data = try JSONEncoder().encode(rows)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else { throw ChatStickerError.saveFailed }
    }
}

extension ChatMessage {
    /// Use the established image wire type so older clients still display the attachment.
    var isSticker: Bool {
        guard !recalled, kind == "image", ChatSticker.validURL(media) else { return false }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) == ChatSticker.messageContent || notoSticker != nil
    }
    var notoSticker: NotoEmoji? {
        guard !recalled, kind == "image", ChatSticker.validURL(media),
              content.hasPrefix(ChatSticker.messageContent + " ") else { return nil }
        let value = String(content.dropFirst((ChatSticker.messageContent + " ").count))
        guard let items = NotoEmojiCatalog.standalone(in: value), items.count == 1 else { return nil }
        return items[0]
    }
}
