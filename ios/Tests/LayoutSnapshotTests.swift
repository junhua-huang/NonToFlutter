import XCTest
import SwiftUI
import UIKit
@testable import Nonto

/// Real SwiftUI screens with isolated fixture responses, for visual review in CI.
@MainActor
final class LayoutSnapshotTests: XCTestCase {
    private let userID = 900040

    override func tearDown() {
        StubProtocol.handler = nil
        try? LocalCache.clear(userID: userID)
        super.tearDown()
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
        try await capture(AppNavigationStack { ProfileView(userID: self.userID) }, session: session, name: "profile-light", width: 390)
        try await capture(AppNavigationStack { ProfileView(userID: self.userID) }, session: session, name: "profile-dark", width: 390, dark: true)
        let longPost = Post(.object(["id": .id(920001), "author": author,
                                     "content": .text(" \n" + (1...10).map { "第 \($0) 行：#生活 与 @小明 的日常记录。" }.joined(separator: "\n") + "\n ")]))
        try await capture(AppNavigationStack {
            List { PostCard(post: longPost).timelinePostRow() }.timelineList().navigationTitle("六行折叠")
        }, session: session, name: "post-six-line-fold", width: 390)
        let photos = (1...5).map { JSON.text("https://layout.example.test/photo-\($0).jpg") }
        for count in [3, 5] {
            let photoPost = Post(.object(["id": .id(920010 + count), "author": author,
                                          "content": .text("#多图 @yuchen"), "images": .array(Array(photos.prefix(count)))]))
            try await capture(AppNavigationStack {
                List { PostCard(post: photoPost).timelinePostRow() }.timelineList().navigationTitle("多图布局")
            }, session: session, name: "post-photos-\(count)", width: 390)
        }
    }

    private func capture<V: View>(_ view: V, session: AppSession, name: String, width: CGFloat,
                                  dark: Bool = false, largeText: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = view.environmentObject(session).tint(.brand)
            .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
            .preferredColorScheme(dark ? .dark : .light)
        let controller = UIHostingController(rootView: root)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKey() }
        // Let navigation, fixture requests and SwiftUI's layout transactions settle.
        try await Task.sleep(for: .milliseconds(700))
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let markers = descendants(of: controller.view).compactMap { $0 as? ScrollChrome }
        XCTAssertTrue(markers.contains(where: { $0.window != nil && $0.isAttached }),
                      "A visible SwiftUI timeline must attach its native scroll policy (markers: \(markers.count), responders: \(markers.map { responderTypes(from: $0) }))")
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
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
