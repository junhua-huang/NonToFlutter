import XCTest
import SwiftUI
import UIKit
@testable import Nonto

/// Real iPad-hosted production views. All content is isolated example data.
@MainActor final class IPadLayoutTests: XCTestCase {
    private let account = 980040
    private let portrait = CGSize(width: 1032, height: 1376)
    private let landscape = CGSize(width: 1376, height: 1032)

    override func tearDown() {
        StubProtocol.handler = nil
        ImageRepository.shared.clear()
        clearDrafts()
        try? LocalCache.clear(userID: account)
        super.tearDown()
    }

    private func requireIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Runs in the dedicated iPad regression.") }
    }

    private func clearDrafts() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("nonto.native.chat-draft.\(account).") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func fixture() throws -> (AppSession, Conversation) {
        clearDrafts()
        let me: JSON = .object(["id": .id(account), "username": .text("nonto"), "display_name": .text("南图"),
            "bio": .text("分享创作，记录生活。和同好一起，把热爱变成作品。"),
            "avatar_url": .text("https://ipad.example.test/avatar-me"), "cover_photo_url": .text("https://ipad.example.test/cover")])
        let friend: JSON = .object(["id": .id(account + 1), "username": .text("linyu"), "display_name": .text("林雨"),
            "avatar_url": .text("https://ipad.example.test/avatar-friend")])
        let messages: [JSON] = [
            .object(["id": .id(981001), "sender_id": .id(account + 1), "content": .text("刚看了你分享的作品，色彩很好看。"), "created_at": .text("2026-10-24T01:40:00Z")]),
            .object(["id": .id(981002), "sender_id": .id(account), "content": .text("谢谢！这组是在周末散步时画的。"), "created_at": .text("2026-10-24T01:41:00Z")]),
            .object(["id": .id(981003), "sender_id": .id(account + 1), "content": .text("下次一起去看展吧，也可以约大家一起创作。"), "created_at": .text("2026-10-24T01:42:00Z")]),
            .object(["id": .id(981004), "sender_id": .id(account), "content": .text("好呀，周末见。到时候把新的灵感也带上！"), "created_at": .text("2026-10-24T01:43:00Z")])]
        let room = Conversation(.object(["id": .id(982001), "other_user": friend, "last_message": messages.last!]))
        let second = Conversation(.object(["id": .id(982002), "other_user": .object(["id": .id(account + 2), "username": .text("xiaoxing"), "display_name": .text("小星")]),
            "unread_count": .id(2), "last_message": .object(["content": .text("新作品已经发到社群里啦"), "created_at": .text("2026-10-24T01:30:00Z")])]))
        let posts: [JSON] = [
            .object(["id": .id(983001), "author": friend, "content": .text("把周末留给风景和创作。\n一组关于山海与日落的色彩练习。 #创作 #日常"),
                     "images": .array([.text("https://ipad.example.test/art-1"), .text("https://ipad.example.test/art-2"), .text("https://ipad.example.test/art-3")]),
                     "like_count": .id(128), "comment_count": .id(12), "created_at": .text("2026-10-24T01:00:00Z")]),
            .object(["id": .id(983002), "author": me, "user_id": .id(account), "content": .text("你好，南图。\n分享喜欢的作品，也认识认真创作的人。 #二次元 #生活"),
                     "like_count": .id(36), "comment_count": .id(5), "created_at": .text("2026-10-23T15:00:00Z")]),
            .object(["id": .id(983003), "author": friend, "content": .text("慢一点，总能发现新的灵感。\n你最近在创作什么？"), "like_count": .id(21), "created_at": .text("2026-10-23T12:00:00Z")])]
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://ipad.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("isolated-ipad-fixture")
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/chat/sessions") { return (200, .object(["sessions": .array([room.raw, second.raw]), "has_more": .bool(false)])) }
            if path.hasSuffix("/messages") { return (200, .object(["messages": .array(messages), "has_more": .bool(false)])) }
            if path.contains("profile") { return (200, .object(["user": me])) }
            if path.contains("posts") || path.contains("feed") { return (200, .object(["posts": .array(posts), "has_more": .bool(false)])) }
            return (200, .object([:]))
        }
        try? LocalCache.clear(userID: account)
        let session = AppSession(api: api); session.user = Person(me); session.restoring = false
        for index in 1...3 { ImageRepository.shared.rememberUploadedPreview(artwork(index), at: "https://ipad.example.test/art-\(index)") }
        ImageRepository.shared.rememberUploadedPreview(artwork(1), at: "https://ipad.example.test/cover")
        ImageRepository.shared.rememberUploadedPreview(avatar("南", color: .systemBlue), at: "https://ipad.example.test/avatar-me")
        ImageRepository.shared.rememberUploadedPreview(avatar("雨", color: .systemTeal), at: "https://ipad.example.test/avatar-friend")
        return (session, room)
    }

    func testIPadStoreScreenshots() async throws {
        try requireIPad()
        let (session, room) = try fixture()
        try await capture(MainTabs(), session: session, size: portrait, name: "ipad-13-feed-portrait")
        try await capture(MainTabs(), session: session, size: landscape, name: "ipad-13-feed-landscape")
        try await capture(MainTabs(initialTab: 4), session: session, size: portrait, name: "ipad-13-profile-portrait")
        try await capture(MainTabs(initialTab: 3, initialConversation: room), session: session, size: landscape,
                          name: "ipad-13-messages-landscape", requiresSplit: true)
        try await capture(MainTabs(initialTab: 3, initialConversation: room), session: session, size: portrait,
                          name: "ipad-13-messages-dark-portrait", dark: true, requiresSplit: true)
    }

    func testConversationAndDraftSurviveWindowResizing() async throws {
        try requireIPad()
        let (session, room) = try fixture()
        let host = try makeHost(MessagesNavigationView(session: session, initialConversation: room), session: session, size: landscape)
        defer { host.close() }
        try await settle()
        let text = "窗口缩小后，这条草稿仍然保留。"
        let field = try XCTUnwrap(inputs(host.window).first)
        if let input = field as? UITextField { input.text = text; input.sendActions(for: .editingChanged) }
        if let input = field as? UITextView { input.text = text; input.delegate?.textViewDidChange?(input) }
        await Task.yield()
        for size in [CGSize(width: 600, height: 1024), CGSize(width: 390, height: 844), portrait, landscape] {
            host.resize(size); try await settle()
            let current = try XCTUnwrap(inputs(host.window).first, "Selected conversation must survive column collapse")
            let value = (current as? UITextField)?.text ?? (current as? UITextView)?.text
            XCTAssertEqual(value, text, "Resizing must preserve the same conversation draft")
            let frame = current.convert(current.bounds, to: host.window)
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThanOrEqual(frame.minX, -1)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 1)
            attach(host.window, name: "ipad-window-\(Int(size.width))x\(Int(size.height))")
        }
    }

    func testLatestMessageStaysAboveIPadKeyboard() async throws {
        try requireIPad()
        let (session, room) = try fixture()
        let store = ChatStore(api: session.api, conversation: room, userID: account)
        var latest = CGRect.zero
        let view = NavigationStack {
            ChatRoomContent(session: session, conversation: room, store: store,
                            onMessageFrame: { id, frame in if id == store.timeline.entries.last?.id { latest = frame } })
        }
        let host = try makeHost(view, session: session, size: portrait)
        defer { host.close() }
        try await settle()
        let field = try XCTUnwrap(inputs(host.window).first)
        let initialY = field.convert(field.bounds, to: host.window).minY
        XCTAssertTrue(field.becomeFirstResponder())
        let deadline = Date().addingTimeInterval(6)
        while field.convert(field.bounds, to: host.window).minY > initialY - 120, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await settle()
        let composer = field.convert(field.bounds, to: host.window)
        XCTAssertLessThan(composer.minY, initialY - 120, "Must actually display the iPad software keyboard")
        XCTAssertGreaterThan(latest.height, 0)
        XCTAssertLessThan(latest.maxY, composer.minY + 2, "Latest bubble must remain readable above the input")
        attach(host.window, name: "ipad-keyboard-chat")
        host.window.endEditing(true); try await settle()
        XCTAssertEqual(field.convert(field.bounds, to: host.window).minY, initialY, accuracy: 6)
    }

    private func capture<V: View>(_ view: V, session: AppSession, size: CGSize, name: String,
                                  dark: Bool = false, requiresSplit: Bool = false) async throws {
        let host = try makeHost(view, session: session, size: size, dark: dark)
        defer { host.close() }
        try await settle()
        if requiresSplit {
            XCTAssertFalse(inputs(host.window).isEmpty, "Selected conversation must render in the detail column")
            let panes = descendants(host.window).compactMap { $0 as? UIScrollView }.filter {
                let frame = $0.convert($0.bounds, to: host.window)
                return !$0.isHidden && $0.alpha > 0 && frame.height > 400 && frame.width > 220 && frame.intersects(host.window.bounds)
            }
            XCTAssertGreaterThanOrEqual(panes.count, 2, "Wide iPad layout must show conversation list and chat together")
        }
        attach(host.window, name: name)
    }

    private func makeHost<V: View>(_ view: V, session: AppSession, size: CGSize, dark: Bool = false) throws -> Host {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = AnyView(view.environmentObject(session).environment(\.scenePhase, .active).tint(.brand)
            .environment(\.dynamicTypeSize, .large).preferredColorScheme(dark ? .dark : .light))
        let controller = UIHostingController(rootView: root)
        let host = Host(window: window, controller: controller, previous: scene.windows.first(where: \.isKeyWindow))
        window.rootViewController = controller; host.resize(size); window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); window.layoutIfNeeded()
        return host
    }

    @MainActor private final class Host {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
        let previous: UIWindow?
        init(window: UIWindow, controller: UIHostingController<AnyView>, previous: UIWindow?) {
            self.window = window; self.controller = controller; self.previous = previous
        }
        func resize(_ size: CGSize) {
            window.frame = CGRect(origin: .zero, size: size)
            controller.traitOverrides.horizontalSizeClass = size.width < 700 ? .compact : .regular
            controller.view.frame = window.bounds
            window.setNeedsLayout(); window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        }
        func close() {
            window.endEditing(true); controller.rootView = AnyView(EmptyView()); controller.view.layoutIfNeeded()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(1400)) }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func inputs(_ view: UIView) -> [UIView] { descendants(view).filter { $0 is UITextField || $0 is UITextView } }
    private func attach(_ window: UIWindow, name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func avatar(_ letter: String, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { c in
            color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            (letter as NSString).draw(at: CGPoint(x: 36, y: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 90, weight: .medium), .foregroundColor: UIColor.white])
        }
    }
    private func artwork(_ index: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 750)).image { c in
            let palettes: [[UIColor]] = [[.init(red: 0.69, green: 0.85, blue: 0.97, alpha: 1), .init(red: 0.20, green: 0.57, blue: 0.68, alpha: 1)], [.init(red: 0.98, green: 0.77, blue: 0.64, alpha: 1), .init(red: 0.44, green: 0.39, blue: 0.65, alpha: 1)], [.init(red: 0.79, green: 0.87, blue: 0.80, alpha: 1), .init(red: 0.24, green: 0.47, blue: 0.42, alpha: 1)]]
            let colors = palettes[index - 1]; colors[0].setFill(); c.fill(CGRect(x: 0, y: 0, width: 1000, height: 750))
            UIColor.white.withAlphaComponent(0.85).setFill(); UIBezierPath(ovalIn: CGRect(x: 690, y: 100, width: 125, height: 125)).fill()
            colors[1].withAlphaComponent(0.45).setFill()
            let rear = UIBezierPath(); rear.move(to: CGPoint(x: 0, y: 430)); rear.addCurve(to: CGPoint(x: 1000, y: 350), controlPoint1: CGPoint(x: 270, y: 130), controlPoint2: CGPoint(x: 580, y: 630));rear.addLine(to: CGPoint(x: 1000, y: 750));rear.addLine(to: CGPoint(x: 0, y: 750));rear.close();rear.fill()
            colors[1].setFill();let front = UIBezierPath();front.move(to: CGPoint(x: 0, y: 580));front.addCurve(to: CGPoint(x: 1000, y: 560), controlPoint1: CGPoint(x: 320, y: 350), controlPoint2: CGPoint(x: 630, y: 800));front.addLine(to: CGPoint(x: 1000, y: 750));front.addLine(to: CGPoint(x: 0, y: 750));front.close();front.fill()
        }
    }
}
