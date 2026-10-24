import Foundation
import Observation
import UIKit

struct PreparedChatSticker: Sendable {
    let data: Data
    let image: UIImage
}

actor ChatStickerPreparer {
    static let shared = ChatStickerPreparer()
    func prepare(_ data: Data) throws -> PreparedChatSticker {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw ChatStickerError.invalidImage }
        let image: UIImage
        do { image = try ImageRepository.decode(data, maxPixelSize: 512) }
        catch { throw ChatStickerError.invalidImage }
        guard let png = image.pngData() else { throw ChatStickerError.invalidImage }
        try Task.checkCancellation()
        return PreparedChatSticker(data: png, image: image)
    }
}

@MainActor @Observable
final class ChatStickerBrowser {
    private let library: ChatStickerLibrary
    private(set) var items: [ChatSticker]
    private(set) var selection: ChatSticker?
    private(set) var prepared: PreparedChatSticker?
    private(set) var busy = false
    private(set) var hasSent = false
    var name = ""
    var error: String?
    var query = ""
    var recentOnly = false
    private var uploadedURL: String?
    private var revision = UUID()
    var results: [ChatSticker] {
        let filtered = items.filter { (!recentOnly || $0.lastUsed != nil) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
        return recentOnly ? filtered.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) } : filtered
    }
    var canCommit: Bool { !busy && !hasSent && (selection != nil || prepared != nil) }
    init(accountID: Int, defaults: UserDefaults = .standard) {
        library = ChatStickerLibrary(accountID: accountID, defaults: defaults)
        items = library.items
    }
    func select(_ sticker: ChatSticker) {
        guard !busy, !hasSent, items.contains(where: { $0.id == sticker.id }) else { return }
        clearSelection(); selection = sticker
    }
    func clearSelection() {
        guard !busy else { return }
        selection = nil; prepared = nil; uploadedURL = nil; name = ""; error = nil
    }
    func prepare(_ data: Data) async {
        guard !busy, !hasSent else { return }
        busy = true; error = nil
        let ticket = revision
        defer { if revision == ticket { busy = false } }
        do {
            let value = try await ChatStickerPreparer.shared.prepare(data)
            try Task.checkCancellation()
            guard revision == ticket else { return }
            selection = nil; prepared = value; uploadedURL = nil; name = ""
        } catch {
            if revision == ticket, !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
    /// Reuse a successful upload after enqueue failure; never enqueue twice after acceptance.
    func commit(send: Bool, upload: (Data) async throws -> String, enqueue: (ChatSticker) -> Bool) async -> Bool {
        guard canCommit else { return false }
        busy = true; error = nil
        let ticket = revision
        defer { if revision == ticket { busy = false } }
        do {
            var sticker = selection
            try Task.checkCancellation()
            if let prepared {
                if uploadedURL == nil {
                    let url = try await upload(prepared.data)
                    try Task.checkCancellation()
                    guard revision == ticket else { return false }
                    uploadedURL = url
                }
                sticker = try library.add(url: uploadedURL ?? "", name: name)
                if let sticker { ImageRepository.shared.rememberUploadedPreview(prepared.image, at: sticker.url) }
                selection = sticker; self.prepared = nil; items = library.items
            }
            try Task.checkCancellation()
            guard revision == ticket, let sticker else { return false }
            if send {
                guard enqueue(sticker) else { error = "无法加入发送队列，贴纸已保留，请重试。"; return false }
                hasSent = true
                // The outbox has accepted the message even if preferences cannot update.
                try? library.recordUse(sticker.id); items = library.items
            }
            return true
        } catch {
            if revision == ticket, !(error is CancellationError) { self.error = error.localizedDescription }
            return false
        }
    }
    func remove(_ sticker: ChatSticker) {
        guard !busy else { return }
        do {
            try library.remove(sticker.id); items = library.items
            if selection?.id == sticker.id { clearSelection() }
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { revision = UUID(); busy = false }
}
