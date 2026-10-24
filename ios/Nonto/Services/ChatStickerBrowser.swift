import Foundation
import Observation
import UIKit
import Vision
import CoreImage

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
    func liftSubject(_ prepared: PreparedChatSticker) throws -> PreparedChatSticker? {
        try Task.checkCancellation()
        // Preserve existing cutouts rather than segmenting them a second time.
        guard NotoEmojiPosterQuality.alphaCoverage(prepared.image) >= 0.98 else { return nil }
        guard let cg = prepared.image.cgImage else { throw ChatStickerError.invalidImage }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ChatStickerError.invalidImage
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let source = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(source, from: source.extent) else {
            throw ChatStickerError.invalidImage
        }
        let image = UIImage(cgImage: result)
        guard let data = image.pngData(), NotoEmojiPosterQuality.isVisible(image) else { throw ChatStickerError.invalidImage }
        return PreparedChatSticker(data: data, image: image)
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
    private(set) var usingCutout = false
    private(set) var preparationNotice: String?
    private var original: PreparedChatSticker?
    private var cutout: PreparedChatSticker?
    var canToggleBackground: Bool { original != nil && cutout != nil }
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
        original = nil; cutout = nil; usingCutout = false; preparationNotice = nil
    }
    func reload() { items = library.items }
    func toggleBackground() {
        guard !busy, canToggleBackground else { return }
        usingCutout.toggle(); prepared = usingCutout ? cutout : original; uploadedURL = nil
    }
    func prepare(_ data: Data, liftSubject: Bool = false) async {
        guard !busy, !hasSent else { return }
        busy = true; error = nil
        let ticket = revision
        defer { if revision == ticket { busy = false } }
        do {
            let value = try await ChatStickerPreparer.shared.prepare(data)
            var foreground: PreparedChatSticker?
            var notice: String?
            if liftSubject {
                do { foreground = try await ChatStickerPreparer.shared.liftSubject(value) }
                catch {
                    if error is CancellationError { throw error }
                    notice = "暂时未能提取主体，已保留原图。你仍然可以添加这张贴纸。"
                }
            }
            try Task.checkCancellation()
            guard revision == ticket else { return }
            selection = nil; original = value; cutout = foreground; usingCutout = foreground != nil
            prepared = foreground ?? value; preparationNotice = notice; uploadedURL = nil; name = ""
        } catch {
            if revision == ticket, !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
    /// Reuse a successful upload after enqueue failure; never enqueue twice after acceptance.
    func commit(send: Bool, isValid: () -> Bool = { true }, upload: (Data) async throws -> String, enqueue: (ChatSticker) -> Bool) async -> Bool {
        guard canCommit, isValid() else { return false }
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
                    guard revision == ticket, isValid() else { return false }
                    uploadedURL = url
                }
                guard isValid() else { throw ChatStickerError.signedOut }
                sticker = try library.add(url: uploadedURL ?? "", name: name)
                if let sticker { ImageRepository.shared.rememberUploadedPreview(prepared.image, at: sticker.url) }
                selection = sticker; self.prepared = nil; items = library.items
            }
            try Task.checkCancellation()
            guard revision == ticket, isValid(), let sticker else { return false }
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
