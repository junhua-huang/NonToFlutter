import XCTest
import SwiftUI
import PhotosUI
@testable import Nonto

@MainActor final class ChatExpressionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let account = 990182
    override func setUp() async throws {
        suite = "chat-expressions-\(UUID())"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }
    private func dragon() throws -> NotoEmoji { try XCTUnwrap(NotoEmojiCatalog.item(id: "1f409")) }
    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 180, height: 220), format: format).image { context in
            UIColor.systemOrange.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 35, y: 15, width: 110, height: 180))
        }
    }
    func testTransparentPostersFallBackToVisibleEmojiAtTileAndMessageSizes() async throws {
        let cache = NotoEmojiPosterCache()
        for id in ["1f409", "2763_fe0f", "1f64c", "1f485"] {
            let item = try XCTUnwrap(NotoEmojiCatalog.item(id: id))
            let bundled = try XCTUnwrap(UIImage(contentsOfFile: try XCTUnwrap(item.previewURL).path))
            XCTAssertFalse(NotoEmojiPosterQuality.isVisible(bundled), id)
            let result = await cache.image(for: item)
            XCTAssertNil(result, "Transparent source frames must not cover the visible fallback")
            for size in [CGFloat(44), CGFloat(136)] {
                let fallback = try XCTUnwrap(ImageRenderer(content: NotoEmojiPoster(item: item).frame(width: size, height: size)).uiImage)
                XCTAssertTrue(NotoEmojiPosterQuality.isVisible(fallback), id)
            }
        }
        let smile = try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600"))
        let cached = await cache.image(for: smile)
        let valid = try XCTUnwrap(cached)
        XCTAssertTrue(NotoEmojiPosterQuality.isVisible(valid))
    }
    func testTextEmojiHasNoSecondCaptionAndMediaKeepsItsActualCaption() throws {
        for emoji in ["🤤", "❣️", "🐉", "👋🏽"] {
            let text = ChatMessage(.object(["message_type": .text("text"), "content": .text(emoji)]))
            XCTAssertNotNil(text.notoEmoji); XCTAssertEqual(text.attachmentCaption, "")
            XCTAssertEqual(ChatQuoteSummary.text(text), emoji)
        }
        let photo = ChatMessage(.object(["message_type": .text("image"), "media_url": .text("https://media.example.test/cat.png"),
                                        "content": .text("猫 https://media.example.test/cat.png")]))
        XCTAssertEqual(photo.attachmentCaption, "猫")
        XCTAssertEqual(ChatMessage(photo.raw.merging(.object(["is_recalled": .bool(true)]))).attachmentCaption, "")
    }
    func testEmojiInsertionReplacesTheSelectionAndProtectsJoinedUnicode() {
        let text = "晚上 见面"
        let point = NSRange(location: 3, length: 0)
        let first = ChatEmojiInsertion.insert("😀", into: text, selection: point)
        let second = ChatEmojiInsertion.insert("😮", into: first.text, selection: NSRange(location: first.caretUTF16, length: 0))
        XCTAssertEqual(second.text, "晚上 😀😮见面")
        let replace = ChatEmojiInsertion.insert("🐉", into: "旧表情", selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(replace.text, "🐉")
        for original in ["👨‍👩‍👧‍👦", "👍🏽", "🇨🇳"] {
            XCTAssertEqual(ChatEmojiInsertion.insert("😀", into: original, selection: NSRange(location: 1, length: 0)).text, original + "😀")
        }
    }
    func testNotoStickerRemainsAnImageAttachmentOnTheWire() throws {
        let item = try dragon()
        let sticker = ChatSticker(id: UUID(), url: "https://media.example.test/dragon.png", name: item.name, notoID: item.id)
        XCTAssertEqual(sticker.content, "[贴纸] 🐉")
        let message = ChatMessage(.object(["message_type": .text("image"), "media_url": .text(sticker.url), "content": .text(sticker.content)]))
        XCTAssertTrue(message.isSticker); XCTAssertEqual(message.notoSticker, item)
        XCTAssertNil(message.notoEmoji); XCTAssertEqual(message.attachmentCaption, "")
        XCTAssertEqual(ChatQuoteSummary.preview(message), "[贴纸]")
        XCTAssertTrue(ChatMediaTimeline.images([message]).isEmpty)
        XCTAssertNil(ChatMessage(message.raw.merging(.object(["is_recalled": .bool(true)]))).notoSticker)
        let legacy = Data("{\"id\":\"\(UUID().uuidString)\",\"url\":\"https://media.example.test/a.png\",\"name\":\"贴纸\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(ChatSticker.self, from: legacy).notoID)
    }
    func testStickerRetryReusesUploadAndKeepsEmojiAndStickerHistoriesSeparate() async throws {
        let item = try dragon(), sender = ChatStickerSender(accountID: account, defaults: defaults)
        let staged = StagedChatSticker(source: .noto(item))
        var uploads = 0, accepted = 0
        let upload: (Data) async throws -> String = { data in
            uploads += 1
            XCTAssertTrue(NotoEmojiPosterQuality.isVisible(try XCTUnwrap(UIImage(data: data))))
            return "https://media.example.test/dragon.png"
        }
        let failed = await sender.send(staged, caption: "文字", quoteID: 9, isValid: { true }, upload: upload) { _, _, _ in false }
        XCTAssertFalse(failed); XCTAssertEqual(uploads, 1)
        XCTAssertTrue(NotoStickerHistory(accountID: account, defaults: defaults).items.isEmpty)
        let sent = await sender.send(staged, caption: "文字", quoteID: 9, isValid: { true }, upload: upload) { value, caption, quote in
            accepted += 1; XCTAssertEqual(value.notoEmoji, item); XCTAssertEqual(caption, "文字"); XCTAssertEqual(quote, 9); return true
        }
        XCTAssertTrue(sent); XCTAssertEqual(uploads, 1)
        let duplicate = await sender.send(staged, caption: "文字", quoteID: nil, isValid: { true }, upload: upload) { _, _, _ in accepted += 1; return true }
        XCTAssertFalse(duplicate); XCTAssertEqual(accepted, 1)
        XCTAssertEqual(NotoStickerHistory(accountID: account, defaults: defaults).items.map(\.id), [item.id])
        XCTAssertTrue(NotoEmojiRecents(accountID: account, defaults: defaults).items.isEmpty)
        let second = StagedChatSticker(source: .noto(item))
        let repeated = await sender.send(second, caption: "", quoteID: nil, isValid: { true }, upload: upload) { _, _, _ in true }
        XCTAssertTrue(repeated); XCTAssertEqual(uploads, 1, "A deliberate second sticker is valid and reuses its uploaded poster")
    }
    func testAccountChangeAndCancelCannotCommitLateStickerUploads() async throws {
        for cancel in [false, true] {
            let sender = ChatStickerSender(accountID: account, defaults: defaults)
            var valid = true, enqueued = 0
            let result = await sender.send(.init(source: .noto(try dragon())), caption: "保留", quoteID: nil, isValid: { valid }) { _ in
                if cancel { sender.cancel() } else { valid = false }
                return "https://media.example.test/late.png"
            } enqueue: { _, _, _ in enqueued += 1; return true }
            XCTAssertFalse(result); XCTAssertEqual(enqueued, 0)
            XCTAssertNil(defaults.dictionary(forKey: "nonto.native.noto-sticker-uploads.\(account)"))
        }
    }
    func testExistingTransparentCutoutsArePreservedWhenLiftingIsRequested() async throws {
        let png = try XCTUnwrap(image().pngData())
        let model = ChatStickerBrowser(accountID: account, defaults: defaults)
        await model.prepare(png, liftSubject: true)
        XCTAssertNotNil(model.prepared); XCTAssertFalse(model.usingCutout); XCTAssertNil(model.preparationNotice)
        XCTAssertLessThan(NotoEmojiPosterQuality.alphaCoverage(try XCTUnwrap(model.prepared?.image)), 0.98)
        var valid = true
        let saved = await model.commit(send: false, isValid: { valid }, upload: { _ in valid = false; return "https://media.example.test/late-photo.png" }) { _ in true }
        XCTAssertFalse(saved); XCTAssertTrue(ChatStickerLibrary(accountID: account, defaults: defaults).items.isEmpty)
    }
    func testMessagesStyleDrawerAndStickerDraftScreenshots() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://expression.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("expression-fixture")
        let session = AppSession(api: api); session.user = Person(.object(["id": .id(account), "username": .text("fixture")]))
        let library = ChatStickerLibrary(accountID: account, defaults: defaults)
        for index in 1...5 {
            let saved = try library.add(url: "https://media.example.test/sticker-\(index).png", name: "贴纸 \(index)")
            ImageRepository.shared.rememberUploadedPreview(image(), at: saved.url)
        }
        for (mode, size, name, large) in [(ChatExpressionTab.emoji, CGSize(width: 390, height: 844), "messages-emoji-text-draft", false),
                                         (.noto, CGSize(width: 390, height: 844), "messages-noto-sticker-draft", false),
                                         (.stickers, CGSize(width: 390, height: 844), "messages-personal-stickers", false),
                                         (.noto, CGSize(width: 320, height: 740), "messages-drawer-large-text", true),
                                         (.stickers, CGSize(width: 820, height: 1100), "messages-drawer-wide", false)] {
            let store = ChatStore(api: api, conversation: Conversation(.object(["id": .id(77)])), userID: account, defaults: defaults)
            store.draft = mode == .emoji ? "今晚见😀" : "附带的文字"
            let sticker = mode == .emoji ? nil : StagedChatSticker(source: .noto(try dragon()))
            let view = ExpressionInputHarness(session: session, store: store, sender: ChatStickerSender(accountID: account, defaults: defaults),
                                              mode: mode, sticker: sticker, defaults: defaults)
            try await capture(view, size: size, name: name, large: large)
        }
        let model = ChatStickerBrowser(accountID: account, defaults: defaults); await model.prepare(try XCTUnwrap(image().pngData()))
        try await capture(ChatStickerCreationView(browser: model, api: api, epoch: api.generation, onSaved: {}),
                          size: CGSize(width: 390, height: 844), name: "messages-new-sticker", navigationTitle: "新贴纸")
        let messages = ["🤤", "❣️", "🐉"].enumerated().map { index, emoji in
            ChatMessage(.object(["id": .id(10 + index), "sender_id": .id(account), "message_type": .text("text"), "content": .text(emoji)]))
        }
        let bubbles = VStack {
            ForEach(ChatTimeline.rows(messages)) { row in
                ChatMessageRow(row: row, community: false, showsReceipt: true, onQuote: { _ in }, onRecall: { _ in })
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.timelineBackground).environmentObject(session)
        try await capture(bubbles, size: CGSize(width: 390, height: 844), name: "messages-no-duplicate-emoji")
    }
    private func capture<V: View>(_ view: V, size: CGSize, name: String, large: Bool = false, navigationTitle: String? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
        let root = view.environment(\.scenePhase, .inactive).environment(\.dynamicTypeSize, large ? .accessibility2 : .large).preferredColorScheme(.dark)
        let controller = UIHostingController(rootView: AnyView(root))
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        controller.view.frame = window.bounds; window.layoutIfNeeded()
        defer {
            window.endEditing(true); controller.rootView = AnyView(EmptyView()); controller.view.layoutIfNeeded()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
        if let navigationTitle {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, !descendants(controller.view).compactMap({ $0 as? UINavigationBar }).contains(where: { $0.topItem?.title == navigationTitle }) {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await Task.sleep(for: .milliseconds(900))
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: rendered); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

private struct ExpressionInputHarness: View {
    let session: AppSession
    let store: ChatStore
    let sender: ChatStickerSender
    let mode: ChatExpressionTab
    let sticker: StagedChatSticker?
    let defaults: UserDefaults
    @State private var quote: ChatMessage?
    @State private var photos: [PhotosPickerItem] = []
    @FocusState private var focus: Bool
    var body: some View {
        VStack {
            Text("聊天").font(.headline).padding(.top, 20)
            Spacer(minLength: 0)
            ChatComposerInput(store: store, stickerSender: sender, accountEpoch: session.api.generation, availableHeight: 700,
                              quote: $quote, picks: $photos, preparingMedia: false, focus: $focus,
                              initialPicker: mode, initialSticker: sticker, pickerDefaults: defaults)
        }.background(Color.timelineBackground).environmentObject(session)
    }
}
