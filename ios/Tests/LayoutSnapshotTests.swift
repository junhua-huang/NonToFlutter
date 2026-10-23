import XCTest
import SwiftUI
import UIKit
@testable import Nonto

private struct ComposerCrashHarness: View {
    let editor: ComposerEditor
    @State private var presented = true
    var body: some View {
        Color.clear.sheet(isPresented: $presented) { PostComposer(editor: editor) }
    }
}

/// Real SwiftUI screens with isolated fixture responses, for visual review in CI.
@MainActor
final class LayoutSnapshotTests: XCTestCase {
    private let userID = 900040

    override func tearDown() {
        StubProtocol.handler = nil
        try? LocalCache.clear(userID: userID)
        ImageRepository.shared.clear()
        super.tearDown()
    }

    func testLegalScreensRemainOfflineAndReadableBeforeConsent() async throws {
        let suite = "nonto-legal-layout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PrivacyConsent(defaults: defaults, revision: "legal-layout")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        var requests = 0
        StubProtocol.handler = { _ in requests += 1; return (200, .null) }
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        let session = AppSession(api: api, consent: consent); session.restoring = false
        try await capture(PrivacyWelcomeView().environmentObject(consent), session: session,
                          name: "legal-welcome", width: 390, expectsScrollChrome: false)
        try await capture(NavigationStack { PolicyView(kind: "privacy") }, session: session,
                          name: "legal-privacy", width: 390, expectsScrollChrome: false)
        try await capture(NavigationStack { PolicyView(kind: "community") }, session: session,
                          name: "legal-community-dark", width: 390, dark: true, expectsScrollChrome: false)
        try await capture(NavigationStack { ContactAndComplaintsView() }, session: session,
                          name: "legal-contact-small-large-text", width: 320, largeText: true, expectsScrollChrome: false)
        try await capture(AppNavigationStack { SettingsView() }, session: session,
                          name: "legal-settings", width: 390, expectsScrollChrome: false, scrollOffset: 450)
        XCTAssertFalse(consent.accepted)
        XCTAssertEqual(requests, 0, "Reading rules and preparing a request must not start account or reporting requests")
    }

    func testTimelineAndProfileAtPhoneAndAccessibilitySizes() async throws {
        let user: JSON = .object(["id": .id(userID), "username": .text("nonto"),
                                  "display_name": .text("南图"),
                                  "bio": .text("记录生活里的小事，也发现更大的世界。")])
        let author: JSON = .object(["id": .id(900041), "username": .text("yuchen"), "display_name": .text("雨辰")])
        let posts: [JSON] = [
            .object(["id": .id(910001), "user_id": .id(900041), "author": author,
                     "content": .text(" \n\n把周末留给散步和日落。 #生活 @yuchen\n走慢一点，总能发现一些新的风景。\n "),
                     "like_count": .id(128), "comment_count": .id(12), "is_liked": .bool(true),
                     "created_at": .text("2026-10-18T10:00:00Z")]),
            .object(["id": .id(910002), "user_id": .id(userID), "author": user,
                     "content": .text("你好，南图。\n在这里分享想法，和有趣的人相遇。"),
                     "like_count": .id(24), "comment_count": .id(3),
                     "created_at": .text("2026-10-18T09:00:00Z"),
                     "quoted_post": .object(["id": .id(910003), "author": author, "content": .text("引用 #生活 @nonto，头像直线连接。"),
                                               "quoted_post": .object(["id": .id(910004), "author": user, "content": .text("最初的动态，串联展示。")])])])
        ]
        StubProtocol.handler = { request in
            if request.url?.path.contains("profile") == true { return (200, .object(["user": user])) }
            if request.url?.path.contains("/posts/user/") == true {
                let extra = (1...10).map { posts[0].merging(.object(["id": .id(950000 + $0)])) }
                return (200, .object(["posts": .array(posts + extra), "has_more": .bool(false)]))
            }
            return (200, .object(["posts": .array(posts), "has_more": .bool(false)]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!,
                            session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("layout-fixture")
        let session = AppSession(api: api); session.user = Person(user); session.restoring = false
        try? LocalCache.clear(userID: userID)
        let feed = PagedResource<Post>(api: api, path: "/recommendations/feed", keys: ["posts", "items"], userID: userID)
        await feed.load(reset: true)
        XCTAssertEqual(feed.items.count, 2, "Visual review requires loaded fixture content")

        try await capture(MainTabs(), session: session, name: "timeline-light", width: 390)
        try await capture(MainTabs(), session: session, name: "timeline-dark", width: 390, dark: true)
        try await capture(MainTabs(), session: session, name: "timeline-small-phone", width: 320)
        try await capture(MainTabs(), session: session, name: "timeline-large-text", width: 390, largeText: true)
        try await capture(AppNavigationStack { ProfileView(userID: self.userID) }, session: session, name: "profile-light", width: 390, verifiesCoverAtTop: true)
        try await capture(AppNavigationStack { ProfileView(userID: self.userID) }, session: session, name: "profile-dark", width: 390, dark: true, verifiesCoverAtTop: true)
        try await capture(AppNavigationStack { ProfileView(userID: self.userID) }, session: session,
                          name: "profile-scrolled-glass", width: 390, scrollOffset: 260)
        let longPost = Post(.object(["id": .id(920001), "author": author,
                                     "content": .text(" \n" + (1...10).map { "第 \($0) 行：#生活 与 @小明 的日常记录。" }.joined(separator: "\n") + "\n ")]))
        try await capture(AppNavigationStack {
            List { PostCard(post: longPost).timelinePostRow() }.timelineList().navigationTitle("六行折叠")
        }, session: session, name: "post-six-line-fold", width: 390)
        try await capture(AppNavigationStack {
            List { PostCard(post: longPost).timelinePostRow() }.timelineList().navigationTitle("编辑后折叠")
        }, session: session, name: "post-six-line-after-edit", width: 390, afterLayout: {
            let edited = (1...10).map { "第 \($0) 行：#生活 与 @小明 的更新记录。" }.joined(separator: "\n")
            session.postChange = PostChange(postID: longPost.id, patch: .object(["content": .text(edited)]))
        })
        let photos = (1...5).map { JSON.text("https://layout.example.test/photo-\($0).jpg") }
        for count in [3, 5] {
            let photoPost = Post(.object(["id": .id(920010 + count), "author": author,
                                          "content": .text("#多图 @yuchen"), "images": .array(Array(photos.prefix(count)))]))
            try await capture(AppNavigationStack {
                List { PostCard(post: photoPost).timelinePostRow() }.timelineList().navigationTitle("多图布局")
            }, session: session, name: "post-photos-\(count)", width: 390)
        }
    }

    func testComposerReferencePickerLayouts() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("composer-layout")
        let session = AppSession(api: api); session.restoring = false
        session.user = Person(.object(["id": .id(userID), "username": .text("nonto"), "display_name": .text("南图")]))
        var friendLoaded = false, topicsLoaded = false
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("/friends") {
                friendLoaded = true
                return (200, .object(["friends": .array([
                    .object(["id": .id(41), "username": .text("yuchen"), "display_name": .text("雨辰")]),
                    .object(["id": .id(42), "username": .text("xiaoming"), "display_name": .text("小明")])])]))
            }
            topicsLoaded = true
            return (200, .object(["topics": .array(["生活", "摄影", "手办"].enumerated().map { .object(["id": .id($0.offset + 1), "name": .text($0.element)]) })]))
        }
        try await capture(PostComposer(), session: session, name: "composer-reference-actions-small", width: 320, expectsScrollChrome: false)
        try await capture(ComposerReferencePicker(api: api, kind: .mention) { _ in }, session: session,
                          name: "composer-friends-picker", width: 390, expectsScrollChrome: false, ready: { friendLoaded })
        try await capture(ComposerReferencePicker(api: api, kind: .topic) { _ in }, session: session,
                          name: "composer-topics-picker-dark", width: 390, dark: true, expectsScrollChrome: false, ready: { topicsLoaded })
    }

    func testComposerOpensPicksAndReturnsWithTheKeyboardAcrossBothReferenceActions() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("composer-interaction")
        let session = AppSession(api: api); session.restoring = false
        session.user = Person(.object(["id": .id(userID), "username": .text("nonto")]))
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("/friends") {
                return (200, .object(["friends": .array([.object(["id": .id(41), "username": .text("yuchen")])])]))
            }
            return (200, .object(["topics": .array([.object(["id": .id(1), "name": .text("生活")])])]))
        }
        PostDraftStore().remove(userID: userID)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), editor = ComposerEditor()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: ComposerCrashHarness(editor: editor)
            .environmentObject(session).environment(\.scenePhase, .active).tint(.brand))
        window.makeKeyAndVisible()
        defer {
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
            PostDraftStore().remove(userID: userID)
        }
        try await waitForComposer { editor.textView?.window != nil && self.presentedDepth(window.rootViewController) == 1 && window.rootViewController?.presentedViewController?.isBeingPresented == false }
        let native = try XCTUnwrap(editor.textView)
        XCTAssertTrue(native.becomeFirstResponder())
        native.insertText("🌅 你好，世界")
        native.selectedRange = NSRange(location: 6, length: 0)
        let before = native.text ?? ""
        let expected = ComposerReferenceInsertion.insert("yuchen", kind: .mention, into: before, selection: native.selectedRange)
        // This is the same action used by the actual @ button, inside an already-presented composer sheet.
        editor.beginReference(.mention)
        try await waitForComposer { self.presentedDepth(window.rootViewController) >= 2 }
        XCTAssertEqual(editor.text, before)
        editor.stageReference("yuchen", kind: .mention); editor.referenceKind = nil
        try await waitForComposer { !editor.hasReferenceSession && editor.text == expected.text && native.isFirstResponder }
        XCTAssertEqual(native.text, expected.text)
        XCTAssertEqual(native.selectedRange.location, expected.caretUTF16)

        editor.beginReference(.topic)
        try await waitForComposer { self.presentedDepth(window.rootViewController) >= 2 }
        editor.referenceKind = nil // Cancel must keep the text and restore the editor.
        try await waitForComposer { !editor.hasReferenceSession && native.isFirstResponder }
        XCTAssertEqual(editor.text, expected.text)

        native.selectAll(nil); native.deleteBackward()
        try await waitForComposer { editor.text.isEmpty }
        editor.beginReference(.topic)
        try await waitForComposer { self.presentedDepth(window.rootViewController) >= 2 }
        editor.stageReference("生活", kind: .topic); editor.referenceKind = nil
        try await waitForComposer { !editor.hasReferenceSession && editor.text == "#生活 " && native.isFirstResponder }
        XCTAssertEqual(native.text, "#生活 ")
        XCTAssertEqual(native.selectedRange, NSRange(location: "#生活 ".utf16.count, length: 0))
    }

    private func waitForComposer(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        guard condition() else {
            XCTFail("The real composer/picker transition must finish")
            throw NSError(domain: "NontoComposerTransition", code: 1)
        }
    }
    private func presentedDepth(_ root: UIViewController?) -> Int {
        guard let root else { return 0 }
        let childDepth = root.children.map { presentedDepth($0) }.max() ?? 0
        return max(childDepth, root.presentedViewController.map { 1 + presentedDepth($0) } ?? 0)
    }

    func testApprovedChatMediaAndAttachmentLayouts() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!,
                            session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("chat-media-fixture")
        let session = AppSession(api: api)
        session.user = Person(.object(["id": .id(userID), "username": .text("nonto")]))
        session.restoring = false
        let preview = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 180))
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 240, y: 0, width: 80, height: 180))
        }
        let photo = "https://layout.example.test/chat-photo.jpg"
        ImageRepository.shared.rememberUploadedPreview(preview, at: photo)
        let sender: JSON = .object(["id": .id(900041), "username": .text("yuchen"), "display_name": .text("雨辰")])
        let messages: [JSON] = [
            .object(["id": .id(940001), "sender_id": .id(900041), "sender": sender,
                     "message_type": .text("image"), "media_url": .text(photo), "content": .text(photo)]),
            .object(["id": .id(940002), "sender_id": .id(userID), "message_type": .text("image"),
                     "media_url": .text(photo), "content": .text("图片说明独立显示")])
        ]
        var loaded = false
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("/chat") { loaded = true; return (200, .object(["messages": .array(messages), "has_more": .bool(false)])) }
            return (200, .object([:]))
        }
        let room = Conversation(.object(["id": .id(940000), "type": .text("community"),
                                        "community_id": .id(940000), "community_name": .text("NonTo 官方群")]))
        try await capture(AppNavigationStack { ChatRoomView(conversation: room) }, session: session,
                          name: "chat-bare-photos-light", width: 390, expectsScrollChrome: false, ready: { loaded })
        try await capture(AppNavigationStack { ChatRoomView(conversation: room) }, session: session,
                          name: "chat-bare-photos-keyboard", width: 390, dark: true, expectsScrollChrome: false, focusComposer: true)
        let video = ChatMessage(.object(["id": .id(940003), "sender_id": .id(900041), "sender": sender,
                                         "message_type": .text("video"), "media_url": .text("https://layout.example.test/clip.mp4"), "content": .text("视频说明")]))
        let row = ChatTimeline.rows([video])[0]
        try await capture(AppNavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ChatMessageRow(row: row, community: true, showsReceipt: false, onQuote: { _ in }, onRecall: { _ in })
                    ChatPendingRow(item: PendingMessage(content: "待发送视频", kind: "video", media: video.media), sending: true, blocked: false, retry: {}, remove: {})
                    ChatPendingRow(item: PendingMessage(content: "这是一条发送失败的文字消息", failure: "暂时无法发送，请重试"), sending: false, blocked: false, retry: {}, remove: {})
                }.padding(.vertical)
            }.navigationTitle("媒体与发送状态")
        }, session: session, name: "chat-bare-video-and-retry", width: 390, dark: true, expectsScrollChrome: false)
        let media = SelectedMedia(data: try XCTUnwrap(preview.jpegData(compressionQuality: 0.8)), name: "preview.jpg", mime: "image/jpeg")
        let store = ChatStore(api: api, conversation: room, userID: userID)
        try await capture(ChatAttachmentSheet(media: [media], api: api, store: store, quoteID: nil, onSent: {}),
                          session: session, name: "chat-attachment-preview", width: 390, expectsScrollChrome: false)
    }

    func testUncertainChatDeliveryOnSmallPhonesAndLargeText() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { _ in (200, .object([:])) }
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        let session = AppSession(api: api); session.restoring = false
        session.user = Person(.object(["id": .id(userID)]))
        try await capture(AppNavigationStack {
            ScrollView {
                ChatPendingRow(item: PendingMessage(content: "弱网时发送的消息", failure: "未收到发送确认，请先检查最新消息", deliveryUncertain: true),
                               sending: false, blocked: false, retry: {}, remove: {})
            }.navigationTitle("发送状态")
        }, session: session, name: "chat-uncertain-delivery-large-text", width: 320, largeText: true, expectsScrollChrome: false)
    }

    func testQuoteContextAndOfflineRecoveryLayouts() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("chat-quote-context")
        let session = AppSession(api: api); session.user = Person(.object(["id": .id(userID)])); session.restoring = false
        let original: JSON = .object(["id": .id(1), "sender_id": .id(900041), "content": .text("周末一起去看展吗？"), "created_at": .text("2026-10-24T02:00:00Z")])
        let reply: JSON = .object(["id": .id(2), "sender_id": .id(userID), "content": .text("好呀，下午两点在入口见。"),
            "quote_message_id": .id(1), "quote_preview": .text("周末一起去看展吗？"), "created_at": .text("2026-10-24T02:01:00Z")])
        var contextLoaded = false
        StubProtocol.handler = { request in
            if request.httpMethod == "POST" { return (200, .null) }
            if request.url!.path.hasSuffix("/around") {
                contextLoaded = true
                return (200, .object(["messages": .array([original, reply])]))
            }
            return (200, .object(["messages": .array([reply]), "has_more": .bool(false)]))
        }
        let room = Conversation(.object(["id": .id(55), "other_user": .object(["id": .id(900041), "username": .text("雨辰")])]))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quote-context-layout"))
        let store = ChatStore(api: api, conversation: room, userID: userID, defaults: defaults)
        await store.activate()
        defer { store.suspend(); defaults.removePersistentDomain(forName: "quote-context-layout") }
        try await capture(ChatQuoteContextView(targetID: 1, store: store, conversation: room, socket: session.socket), session: session,
                          name: "chat-quote-context-dark", width: 390, dark: true, expectsScrollChrome: false, ready: { contextLoaded })
        let item = PendingMessage(content: "网络恢复后继续发送这条消息", failure: "网络暂不可用", retryWhenOnline: true)
        try await capture(AppNavigationStack {
            ScrollView { ChatPendingRow(item: item, sending: false, blocked: false, retry: {}, remove: {}) }
                .navigationTitle("发送状态")
                .overlay(alignment: .top) {
                    ChatSyncNotice(error: "正在等待网络恢复", retry: {}, dismiss: {}).padding(.horizontal)
                }
        }, session: session, name: "chat-offline-recovery-large-text", width: 320, largeText: true, expectsScrollChrome: false)
    }

    func testOutgoingBubbleHeightDoesNotChangeOnAcknowledgementOrReceiptHandoff() throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        let session = AppSession(api: api); session.user = Person(.object(["id": .id(userID)])); session.restoring = false
        let date = Date(timeIntervalSince1970: 1_792_600_000)
        for width in [CGFloat(320), CGFloat(390)] {
            for largeText in [false, true] {
                for text in ["你好", "这是一条多行消息。\n发送确认到达时，聊天记录不应先上跳再下跳。"] {
                    let item = PendingMessage(id: "measured-send", content: text, createdAt: date)
                    let pending = try XCTUnwrap(ChatPresentation(userID: userID, pending: [item]).entries.first?.row)
                    let confirmed = ChatMessage(.object(["id": .id(201), "sender_id": .id(userID), "content": .text(text),
                                                        "message_type": .text("text"), "created_at": .number(date.timeIntervalSince1970)]))
                    let row = try XCTUnwrap(ChatTimeline.rows([confirmed]).first)
                    func height(_ row: ChatTimeline.Row, pending: PendingMessage?, sending: Bool, receipt: Bool) -> CGFloat {
                        let view = ChatMessageRow(row: row, community: false, showsReceipt: receipt,
                                                  pending: pending, sending: sending, onQuote: { _ in }, onRecall: { _ in })
                            .environmentObject(session).environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
                        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 10_000)).height
                    }
                    let queued = height(pending, pending: item, sending: false, receipt: false)
                    let sending = height(pending, pending: item, sending: true, receipt: false)
                    let sent = height(row, pending: nil, sending: false, receipt: true)
                    let previous = height(row, pending: nil, sending: false, receipt: false)
                    XCTAssertGreaterThan(sent, 0)
                    XCTAssertEqual(queued, sending, accuracy: 1, "Queue status must not change bubble height")
                    XCTAssertEqual(sending, sent, accuracy: 1, "Acknowledgement must not resize the bubble")
                    XCTAssertEqual(sent, previous, accuracy: 1, "Moving the receipt to the next message must preserve height")
                }
            }
        }
    }

    func testReportedLoginSearchChatAndDetailLayouts() async throws {
        let author: JSON = .object(["id": .id(900041), "username": .text("涂装老陈"), "display_name": .text("涂装老陈")])
        let post = Post(.object(["id": .id(930001), "author": author,
                                 "content": .text("  \nGK 白模修复教程，桩位对不上怎么办 #手办 #教程\n "),
                                 "images": .array([.text("https://layout.example.test/detail.jpg")]),
                                 "created_at": .text("2026-09-17T14:02:00Z")]))
        var failChat = false, chatRequests = 0, commentRequests = 0
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/topics/trending") { return (200, .object(["topics": .array([])])) }
            if path.hasSuffix("/search/history") {
                return (200, .object(["history": .array(["hjjd", "一停", "阿飞", "热门话题", "ov", "热门帖子", "哈哈", "254207738"].map { .object(["query": .text($0)]) })]))
            }
            if path.hasSuffix("/posts/930001") { return (200, .object(["post": post.raw])) }
            if path.hasSuffix("/comments") {
                commentRequests += 1
                return (200, .object(["comments": .array([]), "has_more": .bool(false)]))
            }
            if path.hasSuffix("/chat") {
                chatRequests += 1
                return failChat ? (503, .object(["detail": .text("暂时无法加载消息，请重试。")]))
                                : (200, .object(["messages": .array([]), "has_more": .bool(false)]))
            }
            return (200, .object([:]))
        }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://layout.example.test/api")!,
                            session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("reported-layout-fixture")
        let session = AppSession(api: api)
        session.user = Person(.object(["id": .id(userID), "username": .text("nonto")]))
        session.restoring = false
        try await capture(AuthView(), session: session, name: "reported-auth-dark", width: 390, dark: true, expectsScrollChrome: false)
        try await capture(AuthView(), session: session, name: "reported-auth-small", width: 320, expectsScrollChrome: false)
        try await capture(AppNavigationStack { ExploreView() }, session: session, name: "reported-search-dark", width: 390, dark: true)
        let conversation = Conversation(.object(["id": .id(930020), "type": .text("community"),
                                                "community_id": .id(930020), "community_name": .text("NonTo 官方群")]))
        try await capture(AppNavigationStack { ChatRoomView(conversation: conversation) }, session: session,
                          name: "reported-chat-empty-keyboard", width: 390, dark: true,
                          expectsScrollChrome: false, focusComposer: true, ready: { chatRequests > 0 })
        failChat = true; chatRequests = 0
        try await capture(AppNavigationStack { ChatRoomView(conversation: conversation) }, session: session,
                          name: "reported-chat-error", width: 390, dark: true, expectsScrollChrome: false, ready: { chatRequests > 0 })
        try await capture(TabView {
            AppNavigationStack { PostDetailView(session: session, postID: post.id, initial: post) }
                .tabItem { Label("首页", systemImage: "house") }
            Text("发现").tabItem { Label("发现", systemImage: "magnifyingglass") }
        }, session: session, name: "reported-detail-dark", width: 390, dark: true, ready: { commentRequests > 0 })
        commentRequests = 0
        try await capture(AppNavigationStack { PostDetailView(session: session, postID: post.id, initial: post) },
                          session: session, name: "reported-detail-large-text", width: 390, largeText: true, ready: { commentRequests > 0 })
    }

    private func capture<V: View>(_ view: V, session: AppSession, name: String, width: CGFloat,
                                  dark: Bool = false, largeText: Bool = false, afterLayout: (() -> Void)? = nil,
                                  expectsScrollChrome: Bool = true, focusComposer: Bool = false, ready: (() -> Bool)? = nil,
                                  verifiesCoverAtTop: Bool = false, scrollOffset: CGFloat? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = view.environmentObject(session).tint(.brand)
            .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
            .environment(\.scenePhase, .active)
            .preferredColorScheme(dark ? .dark : .light)
        let controller = UIHostingController(rootView: root)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKey() }
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        // Let navigation, fixture requests and SwiftUI's layout transactions settle.
        if let ready {
            let deadline = Date().addingTimeInterval(5)
            while !ready(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
            XCTAssertTrue(ready(), "The screenshot must wait for its fixture response")
        }
        try await Task.sleep(for: .milliseconds(700))
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        if let scrollOffset {
            let barHeights = descendants(of: controller.view).compactMap { $0 as? UINavigationBar }.map { $0.frame.height }
            let scroll = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UIScrollView }
                .filter { $0.bounds.width > width * 0.8 && $0.bounds.height > 300 }.first)
            scroll.setContentOffset(CGPoint(x: 0, y: scrollOffset), animated: false)
            try await Task.sleep(for: .milliseconds(400)); controller.view.layoutIfNeeded()
            let afterHeights = descendants(of: controller.view).compactMap { $0 as? UINavigationBar }.map { $0.frame.height }
            XCTAssertEqual(barHeights, afterHeights, "Changing the header material must not change navigation bar height")
        }
        if let afterLayout {
            afterLayout()
            try await Task.sleep(for: .milliseconds(300))
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        }
        if focusComposer {
            let field = try XCTUnwrap(descendants(of: controller.view).first { $0 is UITextField || $0 is UITextView })
            XCTAssertTrue(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
        }
        let markers = descendants(of: controller.view).compactMap { $0 as? ScrollChrome }
        if expectsScrollChrome {
            XCTAssertTrue(markers.contains(where: { $0.window != nil && $0.isAttached }),
                          "A visible SwiftUI timeline must attach its native scroll policy (markers: \(markers.count), responders: \(markers.map { responderTypes(from: $0) }))")
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if verifiesCoverAtTop {
            let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 10, y: 10, width: 20, height: 20)))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                     bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                     bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertGreaterThan(Int(pixel[2]) - Int(pixel[0]), 5, "The blue fixture cover must extend behind the status/navigation area")
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(image.size.width, width, accuracy: 1, "Snapshot must use the requested phone width")
        window.isHidden = true; window.rootViewController = nil
        XCTAssertTrue(markers.allSatisfy { !$0.isAttached }, "Detached timelines must release the navigation bar")
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
    private func responderTypes(from view: UIView) -> [String] {
        var result: [String] = [], next: UIResponder? = view
        while let responder = next, result.count < 20 {
            result.append(String(describing: type(of: responder))); next = responder.next
        }
        return result
    }
}
