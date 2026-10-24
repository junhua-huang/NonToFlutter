import XCTest
import SwiftUI
import UIKit
@testable import Nonto

@MainActor final class FriendsAndMessagesTests: XCTestCase {
    private let account = 990120
    override func tearDown() {
        StubProtocol.handler = nil
        try? LocalCache.clear(userID: account)
        super.tearDown()
    }
    private func makeAPI(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> APIClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://friends.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("isolated-friend-fixture")
        return api
    }
    private var applicant: JSON {
        .object(["id": .id(702), "username": .text("friend_test"), "display_name": .text("申请测试")])
    }
    private var request: JSON {
        .object(["id": .id(501), "sender_id": .id(702), "receiver_id": .id(account),
                 "status": .text("pending"), "user": applicant])
    }
    func testReceivedRequestsUseDetailedEndpointAndApplicantIdentity() async throws {
        let api = try makeAPI { request in
            XCTAssertEqual(request.url?.path, "/api/friends/requests/received")
            return (200, .object(["requests": .array([self.request]), "total": .id(1)]))
        }
        let resource = FriendRequestRecord.received(api: api, userID: account)
        await resource.load(reset: true)
        XCTAssertNil(resource.error)
        XCTAssertEqual(resource.items.count, 1)
        XCTAssertEqual(resource.items.first?.id, 501, "Accept/reject must use the friendship ID")
        XCTAssertEqual(resource.items.first?.applicant.id, 702, "Profile links must use the applicant ID")
        XCTAssertEqual(resource.items.first?.applicant.name, "申请测试")
        XCTAssertFalse(resource.hasMore)
    }
    func testNoReceivedRequestsIsAValidEmptyList() async throws {
        let api = try makeAPI { _ in (200, .object(["requests": .array([]), "total": .id(0)])) }
        let resource = FriendRequestRecord.received(api: api, userID: account)
        await resource.load(reset: true)
        XCTAssertNil(resource.error); XCTAssertTrue(resource.items.isEmpty); XCTAssertFalse(resource.hasMore)
    }
    func testMalformedRefreshDoesNotEraseExistingRequests() async throws {
        var calls = 0
        let api = try makeAPI { _ in
            calls += 1
            return (200, calls == 1 ? .object(["requests": .array([self.request])])
                    : .object(["received": .array([]), "sent": .array([])]))
        }
        let resource = FriendRequestRecord.received(api: api, userID: account)
        await resource.load(reset: true); await resource.load(reset: true)
        XCTAssertNotNil(resource.error); XCTAssertEqual(resource.items.first?.id, 501)
    }
    func testCompactConversationListDoesNotKeepSplitSelectionTint() async throws {
        let room = Conversation(.object(["id": .id(55), "other_user": applicant,
            "last_message": .object(["message_type": .text("post"), "content": .text("")])]))
        let api = try makeAPI { request in
            if request.url?.path == "/api/chat/sessions" {
                return (200, .object(["sessions": .array([room.raw]), "has_more": .bool(false)]))
            }
            return (200, .object([:]))
        }
        let session = AppSession(api: api)
        session.user = Person(.object(["id": .id(account), "username": .text("test")]))
        session.restoring = false
        let compact = try await capture(NavigationStack {
            MessagesView(session: session, selectedRouteKey: AppRoute.chat(room).key)
        }, session: session, sizeClass: .compact, name: "messages-returned-phone-no-selection")
        let regular = try await capture(NavigationStack {
            MessagesView(session: session, selectedRouteKey: AppRoute.chat(room).key)
        }, session: session, sizeClass: .regular, name: "messages-sidebar-keeps-selection")
        let selected = try blueTintPixels(regular)
        XCTAssertGreaterThan(selected, 100, "The wide layout must actually render the selected conversation")
        XCTAssertLessThan(try blueTintPixels(compact), selected / 2,
                          "Returning to the compact list must remove the retained split-view selection tint")
    }
    func testFriendsEmptyAndIncomingScreenshots() async throws {
        var incoming = false
        let api = try makeAPI { request in
            switch request.url?.path {
            case "/api/friends/requests/received": return (200, .object(["requests": .array(incoming ? [self.request] : []), "total": .id(incoming ? 1 : 0)]))
            case "/api/friends/": return (200, .object(["friends": .array([self.applicant])]))
            default: return (404, .object(["detail": .text("Unexpected fixture route")]))
            }
        }
        let session = AppSession(api: api)
        session.user = Person(.object(["id": .id(account), "username": .text("test")]))
        session.restoring = false
        _ = try await capture(NavigationStack { FriendsView(session: session) }, session: session,
                              sizeClass: .compact, name: "friends-no-pending-requests")
        incoming = true
        _ = try await capture(NavigationStack { FriendsView(session: session) }, session: session,
                              sizeClass: .compact, name: "friends-incoming-applicant-details")
    }
    private func capture<V: View>(_ view: V, session: AppSession, sizeClass: UserInterfaceSizeClass, name: String) async throws -> UIImage {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: view.environmentObject(session)
            .environment(\.horizontalSizeClass, sizeClass).preferredColorScheme(.light).tint(.brand))
        controller.traitOverrides.horizontalSizeClass = sizeClass == .compact ? .compact : .regular
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        controller.loadViewIfNeeded(); controller.view.frame = window.bounds; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1200))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return image
    }
    private func blueTintPixels(_ image: UIImage) throws -> Int {
        let image = try XCTUnwrap(image.cgImage)
        let width = 128, height = 256
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).filter { i in
            Int(bytes[i]) > 210 && Int(bytes[i + 2]) > Int(bytes[i]) + 8 && Int(bytes[i + 1]) > Int(bytes[i]) + 4
        }.count
    }
}
