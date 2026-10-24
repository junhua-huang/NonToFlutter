import XCTest
import SwiftUI
import ImageIO
@testable import Nonto

@MainActor final class ChatStickerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let account = 990170
    private let url = "https://stickers.example.test/transparent.png"
    override func setUp() async throws {
        suite = "chat-stickers-\(UUID())"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }
    private var library: ChatStickerLibrary { ChatStickerLibrary(accountID: account, defaults: defaults) }
    private func browser() -> ChatStickerBrowser { ChatStickerBrowser(accountID: account, defaults: defaults) }
    private func png(size: CGSize = CGSize(width: 1200, height: 600)) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemOrange.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.25, y: 10, width: size.width * 0.5, height: size.height - 20))
        }.pngData())
    }
    func testCollectionPersistsDeduplicatesAndKeepsAccountsSeparate() throws {
        let first = try library.add(url: url, name: "  开心贴纸  ")
        XCTAssertEqual(first.name, "开心贴纸")
        XCTAssertEqual(try library.add(url: url).id, first.id)
        XCTAssertEqual(library.items.count, 1)
        XCTAssertTrue(ChatStickerLibrary(accountID: account + 1, defaults: defaults).items.isEmpty)
        XCTAssertThrowsError(try ChatStickerLibrary(accountID: 0, defaults: defaults).add(url: url))
        XCTAssertThrowsError(try library.add(url: "file:///private/sticker.png"))
        XCTAssertThrowsError(try library.add(url: "https://user:password@example.test/a.png"))
        let model = browser(); model.query = "开心"
        XCTAssertEqual(model.results, [first])
        model.recentOnly = true; XCTAssertTrue(model.results.isEmpty)
        try library.recordUse(first.id, at: Date(timeIntervalSince1970: 100))
        let reopened = browser(); reopened.recentOnly = true
        XCTAssertEqual(reopened.results.first?.id, first.id)
        reopened.select(try XCTUnwrap(reopened.results.first)); reopened.remove(first)
        XCTAssertTrue(library.items.isEmpty); XCTAssertNil(reopened.selection)
    }
    func testCollectionLimitDoesNotEvictExistingStickers() throws {
        for index in 0..<ChatStickerLibrary.limit { try library.add(url: "https://stickers.example.test/\(index).png") }
        XCTAssertThrowsError(try library.add(url: url))
        XCTAssertEqual(library.items.count, ChatStickerLibrary.limit)
        XCTAssertNoThrow(try library.add(url: "https://stickers.example.test/0.png"))
    }
    func testMalformedSavedRowsCannotIntroduceUnsafeOrDuplicateURLs() throws {
        let first = ChatSticker(id: UUID(), url: url, name: "safe")
        let unsafe = ChatSticker(id: UUID(), url: "javascript:alert(1)", name: "unsafe")
        let duplicate = ChatSticker(id: UUID(), url: url, name: "duplicate")
        defaults.set(try JSONEncoder().encode([first, unsafe, duplicate]), forKey: "nonto.native.stickers.\(account)")
        XCTAssertEqual(library.items, [first])
    }
    func testImportedImagesBecomeSmallTransparentPNGAndRejectInvalidData() async throws {
        let value = try await ChatStickerPreparer.shared.prepare(png())
        let image = try XCTUnwrap(value.image.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 512)
        XCTAssertEqual(image.width, image.height * 2)
        XCTAssertTrue([CGImageAlphaInfo.premultipliedFirst, .premultipliedLast, .first, .last].contains(image.alphaInfo))
        XCTAssertEqual(Array(value.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        for invalid in [Data(), Data("not an image".utf8), Data(repeating: 0, count: 20 * 1024 * 1024 + 1)] {
            do { _ = try await ChatStickerPreparer.shared.prepare(invalid); XCTFail("Invalid image must fail") }
            catch { XCTAssertTrue(error is ChatStickerError) }
        }
    }
    func testUploadAndEnqueueFailuresKeepPreviewAndReuseTheSuccessfulUpload() async throws {
        let model = browser(); await model.prepare(try png())
        model.name = "开心"
        var uploads = 0, sends = 0
        let upload: (Data) async throws -> String = { _ in
            uploads += 1
            if uploads == 1 { throw URLError(.notConnectedToInternet) }
            return self.url
        }
        let failedUpload = await model.commit(send: true, upload: upload) { _ in sends += 1; return true }
        XCTAssertFalse(failedUpload); XCTAssertNotNil(model.prepared); XCTAssertTrue(library.items.isEmpty)
        let rejected = await model.commit(send: true, upload: upload) { _ in sends += 1; return false }
        XCTAssertFalse(rejected); XCTAssertNotNil(model.selection); XCTAssertNil(model.prepared)
        XCTAssertEqual(library.items.count, 1); XCTAssertNil(library.items.first?.lastUsed)
        let accepted = await model.commit(send: true, upload: upload) { _ in sends += 1; return true }
        XCTAssertTrue(accepted); XCTAssertTrue(model.hasSent); XCTAssertNotNil(library.items.first?.lastUsed)
        let repeated = await model.commit(send: true, upload: upload) { _ in sends += 1; return true }
        XCTAssertFalse(repeated); XCTAssertEqual(uploads, 2); XCTAssertEqual(sends, 2)
    }
    func testSavingDoesNotSendAndClosingDuringUploadCannotCommit() async throws {
        let model = browser(); await model.prepare(try png())
        var sends = 0
        let saved = await model.commit(send: false, upload: { _ in self.url }) { _ in sends += 1; return true }
        XCTAssertTrue(saved); XCTAssertEqual(sends, 0); XCTAssertFalse(model.hasSent)
        XCTAssertNil(library.items.first?.lastUsed)
        await model.prepare(try png())
        let cancelled = await model.commit(send: true, upload: { _ in
            model.cancel(); return "https://stickers.example.test/cancelled.png"
        }) { _ in sends += 1; return true }
        XCTAssertFalse(cancelled); XCTAssertEqual(sends, 0); XCTAssertEqual(library.items.count, 1)
    }
    func testStickerRenderingClassificationQuotesRecallAndGallery() {
        let sticker = ChatMessage(.object(["id": .id(1), "message_type": .text("image"), "media_url": .text(url), "content": .text(ChatSticker.messageContent)]))
        let photo = ChatMessage(sticker.raw.merging(.object(["id": .id(2), "content": .text("普通图片")])))
        XCTAssertTrue(sticker.isSticker); XCTAssertNil(sticker.notoEmoji)
        XCTAssertFalse(photo.isSticker)
        XCTAssertFalse(ChatMessage(sticker.raw.merging(.object(["message_type": .text("text")]))).isSticker)
        XCTAssertFalse(ChatMessage(sticker.raw.merging(.object(["media_url": .text("file:///a.png")]))).isSticker)
        XCTAssertEqual(ChatQuoteSummary.text(sticker), "[贴纸]")
        XCTAssertEqual(ChatQuoteSummary.preview(sticker), "[贴纸]")
        XCTAssertEqual(ChatMediaTimeline.images([sticker, photo]).map(\.id), [2])
        let recalled = ChatMessage(sticker.raw.merging(.object(["is_recalled": .bool(true)])))
        XCTAssertFalse(recalled.isSticker); XCTAssertEqual(ChatQuoteSummary.preview(recalled), "消息已撤回")
    }
    func testPickerEmptyLibraryPreviewLargeTextAndWideLayouts() async throws {
        let model = browser()
        try await capture(model, size: CGSize(width: 390, height: 844), name: "stickers-empty")
        let image = try XCTUnwrap(UIImage(data: png()))
        for index in 0..<12 {
            let item = try library.add(url: "https://stickers.example.test/\(index).png", name: "开心贴纸 \(index + 1)")
            ImageRepository.shared.rememberUploadedPreview(image, at: item.url)
        }
        let populated = browser(); populated.select(try XCTUnwrap(populated.items.first))
        try await capture(populated, size: CGSize(width: 390, height: 844), name: "stickers-library-preview")
        // Each presentation owns its browser. A previous host's delayed disappearance
        // must not cancel the next presentation's import while the actor is decoding.
        let imported = browser(); await imported.prepare(try png())
        XCTAssertNotNil(imported.prepared); XCTAssertNil(imported.selection)
        try await capture(imported, size: CGSize(width: 320, height: 740), name: "stickers-import-large-text", large: true)
        try await capture(browser(), size: CGSize(width: 820, height: 1100), name: "stickers-wide-dark", dark: true)
    }
    private func capture(_ model: ChatStickerBrowser, size: CGSize, name: String, large: Bool = false, dark: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let view = ChatStickerPickerContent(browser: model, upload: { _ in self.url }, onSend: { _ in false })
            .environment(\.dynamicTypeSize, large ? .accessibility2 : .large).preferredColorScheme(dark ? .dark : .light)
        let host = UIHostingController(rootView: AnyView(view))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded()
        host.view.frame = window.bounds; window.layoutIfNeeded()
        defer {
            window.endEditing(true); host.rootView = AnyView(EmptyView())
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(700))
        let image = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
