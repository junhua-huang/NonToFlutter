import SwiftUI
import Observation

@MainActor @Observable final class ChatStickerSender {
    private(set) var busy = false
    var error: String?
    private let accountID: Int
    private let defaults: UserDefaults
    private var revision = UUID()
    private var acceptedID: UUID?
    private var uploads: [String: String]
    private var cacheKey: String { "nonto.native.noto-sticker-uploads.\(accountID)" }
    init(accountID: Int, defaults: UserDefaults = .standard) {
        self.accountID = accountID; self.defaults = defaults
        uploads = accountID > 0 ? (defaults.dictionary(forKey: "nonto.native.noto-sticker-uploads.\(accountID)") as? [String: String] ?? [:]) : [:]
    }
    func send(_ staged: StagedChatSticker, caption: String, quoteID: Int?, isValid: () -> Bool,
              upload: (Data) async throws -> String, enqueue: (ChatSticker, String, Int?) -> Bool) async -> Bool {
        guard !busy, acceptedID != staged.id, accountID > 0, isValid() else { return false }
        busy = true; error = nil
        let ticket = revision
        defer { if revision == ticket { busy = false } }
        do {
            try Task.checkCancellation()
            let sticker: ChatSticker
            switch staged.source {
            case .saved(let saved): sticker = saved
            case .noto(let item):
                let url: String
                if let cached = uploads[item.id], ChatSticker.validURL(cached) { url = cached }
                else {
                    let poster = await NotoEmojiPosterCache.shared.image(for: item)
                    try Task.checkCancellation()
                    guard revision == ticket, isValid() else { return false }
                    let image = poster ?? ImageRenderer(content: Text(item.emoji).font(.system(size: 156)).frame(width: 192, height: 192)).uiImage
                    guard let image, let data = image.pngData(), NotoEmojiPosterQuality.isVisible(image) else { throw ChatStickerError.invalidImage }
                    url = try await upload(data)
                    try Task.checkCancellation()
                    guard revision == ticket, isValid(), ChatSticker.validURL(url) else { return false }
                    uploads[item.id] = url
                    // Bound the account cache; a discarded entry can safely be uploaded again.
                    if uploads.count > 160 { uploads = [item.id: url] }
                    defaults.set(uploads, forKey: cacheKey)
                    ImageRepository.shared.rememberUploadedPreview(image, at: url)
                }
                sticker = ChatSticker(id: UUID(), url: url, name: item.name, notoID: item.id)
            }
            try Task.checkCancellation()
            guard revision == ticket, isValid() else { return false }
            guard enqueue(sticker, caption, quoteID) else { error = "无法加入发送队列，贴纸和文字已保留，请重试。"; return false }
            acceptedID = staged.id
            switch staged.source {
            case .saved(let item): try? ChatStickerLibrary(accountID: accountID, defaults: defaults).recordUse(item.id)
            case .noto(let item): NotoStickerHistory(accountID: accountID, defaults: defaults).record(item)
            }
            return true
        } catch {
            if revision == ticket, !(error is CancellationError) { self.error = error.localizedDescription }
            return false
        }
    }
    func cancel() { revision = UUID(); busy = false; error = nil }
}
