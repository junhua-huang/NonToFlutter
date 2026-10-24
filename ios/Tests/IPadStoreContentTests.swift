import XCTest
import SwiftUI
import UIKit
@testable import Nonto

/// Captures unchanged production views from an authenticated account's public content snapshot.
/// No login password, session token, email, private posts or conversations are included.
@MainActor final class IPadStoreContentTests: XCTestCase {
    private let portrait = CGSize(width: 1032, height: 1376)
    private let landscape = CGSize(width: 1376, height: 1032)
    private let snapshotText = #"""
{"profile":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]},"feed":[{"id":213,"content":"coser们在展会中互动合影 #二次元 ","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-8F4EAAB3-BADE-4457-BF55-8167C1A0E696.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-8F4EAAB3-BADE-4457-BF55-8167C1A0E696.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":47,"quoted_post_id":null,"created_at":"2026-10-23T22:06:50","updated_at":"2026-10-23T22:32:02","visibility":"public","is_public":true,"like_count":1,"comment_count":1,"view_count":2,"community_id":2,"topics":[{"id":92,"name":"二次元","description":"关于 #二次元 的讨论","icon_url":null,"color":"#3b82f6","post_count":3,"follower_count":0,"is_trending":false,"created_at":"2026-10-21T17:08:12","updated_at":"2026-10-23T22:08:46"}],"is_liked":false,"author":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]}},{"id":214,"content":"爱你所爱 #二次元 ","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-E987D0A0-970C-4E24-BAD7-184E90A0302B.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-383482E0-7052-46F3-8DEC-15551B9F11BC.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-F8B7A8AD-B876-49EA-8FF0-26A555D3186E.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-E987D0A0-970C-4E24-BAD7-184E90A0302B.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-383482E0-7052-46F3-8DEC-15551B9F11BC.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-F8B7A8AD-B876-49EA-8FF0-26A555D3186E.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":47,"quoted_post_id":null,"created_at":"2026-10-23T22:08:46","updated_at":"2026-10-23T22:16:16","visibility":"public","is_public":true,"like_count":1,"comment_count":0,"view_count":1,"community_id":null,"topics":[{"id":92,"name":"二次元","description":"关于 #二次元 的讨论","icon_url":null,"color":"#3b82f6","post_count":3,"follower_count":0,"is_trending":false,"created_at":"2026-10-21T17:08:12","updated_at":"2026-10-23T22:08:46"}],"is_liked":true,"author":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]}},{"id":215,"content":"精美的手办、同人志与周边摊位","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/133/20261023/photo-E5C26BD6-F93B-4432-93F0-1AF65C6E98EA.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/133/20261023/photo-E5C26BD6-F93B-4432-93F0-1AF65C6E98EA.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":133,"quoted_post_id":null,"created_at":"2026-10-23T22:15:17","updated_at":"2026-10-23T22:15:17","visibility":"public","is_public":true,"like_count":1,"comment_count":0,"view_count":0,"community_id":null,"topics":[],"is_liked":false,"author":{"id":133,"username":"半岛铁盒","display_name":"半岛铁盒","bio":"摄影佬一枚，坐标南宁，目前只接互勉系列，技术在打磨中……","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/133/20260604/796e4971.jpg","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/133/20261021/photo-0664A73D-857B-4605-9E5B-F81F6F4657D6.jpg","created_at":"2026-06-04T10:57:35","verified_roles":[],"verified_role_labels":[]}}],"own":[{"id":214,"content":"爱你所爱 #二次元 ","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-E987D0A0-970C-4E24-BAD7-184E90A0302B.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-383482E0-7052-46F3-8DEC-15551B9F11BC.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-F8B7A8AD-B876-49EA-8FF0-26A555D3186E.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-E987D0A0-970C-4E24-BAD7-184E90A0302B.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-383482E0-7052-46F3-8DEC-15551B9F11BC.jpg","https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-F8B7A8AD-B876-49EA-8FF0-26A555D3186E.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":47,"quoted_post_id":null,"created_at":"2026-10-23T22:08:46","updated_at":"2026-10-23T22:16:16","visibility":"public","is_public":true,"like_count":1,"comment_count":0,"view_count":1,"community_id":null,"topics":[{"id":92,"name":"二次元","description":"关于 #二次元 的讨论","icon_url":null,"color":"#3b82f6","post_count":3,"follower_count":0,"is_trending":false,"created_at":"2026-10-21T17:08:12","updated_at":"2026-10-23T22:08:46"}],"is_liked":true,"author":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]}},{"id":213,"content":"coser们在展会中互动合影 #二次元 ","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-8F4EAAB3-BADE-4457-BF55-8167C1A0E696.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261023/photo-8F4EAAB3-BADE-4457-BF55-8167C1A0E696.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":47,"quoted_post_id":null,"created_at":"2026-10-23T22:06:50","updated_at":"2026-10-23T22:32:02","visibility":"public","is_public":true,"like_count":1,"comment_count":1,"view_count":2,"community_id":2,"topics":[{"id":92,"name":"二次元","description":"关于 #二次元 的讨论","icon_url":null,"color":"#3b82f6","post_count":3,"follower_count":0,"is_trending":false,"created_at":"2026-10-21T17:08:12","updated_at":"2026-10-23T22:08:46"}],"is_liked":false,"author":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]}},{"id":211,"content":"","images":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261021/photo-A99EF8C8-1D0B-4F18-9D03-5C0F90C30F37.jpg"],"image_urls":["https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/posts/47/20261021/photo-A99EF8C8-1D0B-4F18-9D03-5C0F90C30F37.jpg"],"video_url":null,"post_type":"image","content_category":null,"display_role_type":null,"display_role_label":null,"user_id":47,"quoted_post_id":null,"created_at":"2026-10-21T20:08:37","updated_at":"2026-10-21T20:08:37","visibility":"public","is_public":true,"like_count":1,"comment_count":0,"view_count":0,"community_id":2,"topics":[],"is_liked":true,"author":{"id":47,"username":"长风","display_name":"长风","bio":"这家伙什么也没写","avatar_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/avatars/47/20260726/image_1785062064157.png","cover_photo_url":"https://junhua-1316525126.cos.ap-guangzhou.myqcloud.com/covers/47/20260603/087e91b1.jpg","created_at":"2026-04-24T12:50:13","verified_roles":[],"verified_role_labels":[]}}]}
"""#
    func testStoreCapturesWithAccountContent() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires iPad") }
        let snapshot = try JSON.decode(Data(snapshotText.utf8))
        let profile = snapshot["profile"], feed = snapshot["feed"].array, own = snapshot["own"].array
        let account = profile["id"].int
        try? LocalCache.clear(userID: account)
        defer { StubProtocol.handler = nil; ImageRepository.shared.clear(); try? LocalCache.clear(userID: account) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://store-capture.example.test/api")!,
                            session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("public-content-snapshot")
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/auth/profile") { return (200, profile) }
            if path.contains("/recommendations/feed") { return (200, .object(["posts": .array(feed), "has_more": .bool(false)])) }
            if path.contains("/posts/user/") { return (200, .object(["posts": .array(own), "has_more": .bool(false)])) }
            if path.hasSuffix("/comments") { return (200, .object(["comments": .array([]), "has_more": .bool(false)])) }
            if let id = Int(path.split(separator: "/").last ?? ""), let post = (feed + own).first(where: { $0["id"].int == id }) { return (200, .object(["post": post])) }
            return (200, .object(["unread_count": .id(0)]))
        }
        let session = AppSession(api: api); session.user = Person(profile); session.restoring = false
        var urls = Set<String>()
        for item in feed + own {
            urls.formUnion(Post(item).images)
            let avatar = Post(item).author.avatar
            if !avatar.isEmpty { urls.insert(avatar) }
        }
        if !Person(profile).avatar.isEmpty { urls.insert(Person(profile).avatar) }
        for url in urls.sorted() {
            let image = try await ImageRepository.shared.image(at: url, maxPixelSize: 960)
            ImageRepository.shared.rememberUploadedPreview(image, at: url)
        }
        if !Person(profile).cover.isEmpty { _ = try await ImageRepository.shared.image(at: Person(profile).cover, maxPixelSize: 1200) }
        try await capture(MainTabs(), session: session, size: portrait, name: "real-01-feed-portrait")
        try await capture(MainTabs(), session: session, size: landscape, name: "real-02-feed-landscape")
        try await capture(MainTabs(initialTab: 4), session: session, size: portrait, name: "real-03-profile-portrait")
        let multi = try XCTUnwrap((feed + own).first { Post($0).images.count >= 3 })
        try await capture(AppNavigationStack { PostDetailView(session: session, postID: multi["id"].int, initial: Post(multi)) },
                          session: session, size: portrait, name: "real-04-post-portrait")
        try await capture(MainTabs(), session: session, size: portrait, name: "real-05-feed-dark-portrait", dark: true)
        let pictures = Post(multi).images
        _ = try await ImageRepository.shared.image(at: pictures[0])
        try await capture(ImageGallery(images: pictures, initial: 0), session: session, size: landscape, name: "real-06-gallery-landscape", dark: true)
    }
    private func capture<V: View>(_ view: V, session: AppSession, size: CGSize, name: String, dark: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = AnyView(view.environmentObject(session).environment(\.scenePhase, .active).tint(.brand)
            .environment(\.dynamicTypeSize, .large).preferredColorScheme(dark ? .dark : .light))
        let controller = UIHostingController(rootView: root)
        window.rootViewController = controller
        window.frame = CGRect(origin: .zero, size: size)
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.view.frame = window.bounds
        window.makeKeyAndVisible(); controller.loadViewIfNeeded(); window.layoutIfNeeded()
        defer {
            controller.rootView = AnyView(EmptyView()); controller.view.layoutIfNeeded()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(3))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.cgImage?.width, Int(size.width * 2))
        XCTAssertEqual(image.cgImage?.height, Int(size.height * 2))
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}