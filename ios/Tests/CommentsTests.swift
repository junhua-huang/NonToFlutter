import XCTest
import SwiftUI
import UIKit
@testable import Nonto

@MainActor final class CommentsTests: XCTestCase {
    override func tearDown() { StubProtocol.handler = nil; super.tearDown() }
    private func comment(_ id: Int, parent: Int? = nil, replies: [JSON] = []) -> JSON {
        .object(["id": .id(id), "parent_id": parent.map(JSON.id) ?? .null, "user_id": .id(7),
                 "author": .object(["id": .id(7), "username": .text("rain"), "display_name": .text("雨")]),
                 "content": .text("评论 \(id)"), "like_count": .id(2), "is_liked": .bool(false),
                 "replies": .array(replies), "reply_count": .id(replies.count), "replies_page": .id(1)])
    }
    private func setup(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> (CommentsStore, APIClient, UserDefaults) {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://comments.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("comment-tests")
        let defaults = UserDefaults(suiteName: "comment-tests-\(UUID())")!
        return (CommentsStore(api: api, postID: 50, userID: 7, defaults: defaults), api, defaults)
    }
    private func requestBody(_ request: URLRequest) throws -> JSON {
        if let data = request.httpBody { return try JSON.decode(data) }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        return try JSON.decode(data)
    }
    func testLikeOfExpandedReplyUsesLocalServerConfirmationWithoutReloading() async throws {
        var lists = 0
        let root = comment(1, replies: (2...12).map { comment($0, parent: 1) })
        let (store, _, _) = try setup { request in
            if request.url!.path.hasSuffix("/like") { return (200, .object(["liked": .bool(true), "like_count": .id(8)])) }
            lists += 1; return (200, .object(["comments": .array([root]), "total": .id(1)]))
        }
        await store.load(); await store.expandReplies(1)
        await store.toggleLike(store.threads[0].replies.last!)
        XCTAssertEqual(lists, 1); XCTAssertTrue(store.threads[0].expanded)
        XCTAssertEqual(store.threads[0].replies.last!.likes, 8)
        XCTAssertTrue(store.threads[0].replies.last!.liked)
    }
    func testFailedLikeRollsBackAndKeepsExpandedReplies() async throws {
        let root = comment(1, replies: [comment(2, parent: 1)])
        let (store, _, _) = try setup { request in
            request.url!.path.hasSuffix("/like") ? (503, .object(["detail": .text("稍后重试")])) : (200, .object(["comments": .array([root])]))
        }
        await store.load(); await store.toggleLike(store.threads[0].replies[0])
        XCTAssertFalse(store.threads[0].replies[0].liked)
        XCTAssertEqual(store.threads[0].replies[0].likes, 2)
        XCTAssertNotNil(store.actionError); XCTAssertTrue(store.busyIDs.isEmpty)
    }
    func testReplyPagingDoesNotSkipPageAndSurvivesRefresh() async throws {
        var pages: [String] = []
        var root = comment(1, replies: (2...11).map { comment($0, parent: 1) })
        root["replies_has_more"] = .bool(true); root["reply_count"] = .id(11)
        let (store, _, _) = try setup { request in
            let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if params.contains(where: { $0.name == "parent_id" }) {
                pages.append(params.first { $0.name == "page" }!.value!)
                return (200, .object(["comments": .array([self.comment(11, parent: 1), self.comment(12, parent: 1)]), "has_more": .bool(false)]))
            }
            return (200, .object(["comments": .array([root]), "total": .id(1)]))
        }
        await store.load(); XCTAssertEqual(store.threads[0].visibleReplies.count, 2)
        await store.expandReplies(1); await store.expandReplies(1); await store.load(reset: true)
        XCTAssertEqual(pages, ["2"]); XCTAssertEqual(store.threads[0].replies.map(\.id), Array(2...12))
        XCTAssertTrue(store.threads[0].expanded); XCTAssertFalse(store.threads[0].hasMore)
    }
    func testRootPaginationUsesServerTotalAndPreservesRowsOnFailure() async throws {
        var fail = false
        let (store, _, _) = try setup { request in
            if fail { return (500, .object([:])) }
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            let rows = page == "1" ? (1...20).map { self.comment($0) } : [self.comment(21)]
            return (200, .object(["comments": .array(rows), "total": .id(21)]))
        }
        await store.load(); XCTAssertTrue(store.hasMore)
        fail = true; await store.load(); XCTAssertEqual(store.threads.count, 20); XCTAssertEqual(store.page, 1)
        XCTAssertNotNil(store.loadError)
        fail = false; await store.load(); XCTAssertEqual(store.threads.count, 21); XCTAssertFalse(store.hasMore)
    }
    func testReplyToReplyUsesRootAndActualRecipientThenAppearsImmediately() async throws {
        var sent: JSON = .null
        let root = comment(1, replies: [comment(2, parent: 1)])
        let (store, _, _) = try setup { request in
            if request.httpMethod == "POST" {
                sent = try self.requestBody(request)
                return (200, .object(["comment": self.comment(3, parent: 1), "comment_count": .id(19)]))
            }
            return (200, .object(["comments": .array([root])]))
        }
        await store.load(); store.reply = store.threads[0].replies[0]; store.text = "  👋 好作品 \n"
        await store.send()
        XCTAssertEqual(sent["parent_id"].int, 1); XCTAssertEqual(sent["reply_to_user_id"].int, 7)
        XCTAssertEqual(sent["content"].string, "👋 好作品")
        XCTAssertEqual(store.threads[0].replies.map(\.id), [2, 3]); XCTAssertEqual(store.scrollTarget, 3)
        XCTAssertEqual(store.commentCount, 19); XCTAssertTrue(store.text.isEmpty); XCTAssertNil(store.reply)
    }
    func testFailedSendRetainsDraftAndRejectsWhitespace() async throws {
        var writes = 0
        let (store, api, defaults) = try setup { _ in writes += 1; return (503, .object(["detail": .text("网络暂不可用")])) }
        store.text = " \n "; await store.send(); XCTAssertEqual(writes, 0)
        store.text = "保留草稿"; store.reply = Comment(comment(2, parent: 1)); await store.send(); store.flushDraft()
        let restored = CommentsStore(api: api, postID: 50, userID: 7, defaults: defaults)
        XCTAssertEqual(restored.text, "保留草稿"); XCTAssertEqual(restored.reply?.rootID, 1)
        XCTAssertNotNil(store.sendError); XCTAssertFalse(store.sending)
        let otherPost = CommentsStore(api: api, postID: 51, userID: 7, defaults: defaults)
        let otherAccount = CommentsStore(api: api, postID: 50, userID: 8, defaults: defaults)
        XCTAssertTrue(otherPost.text.isEmpty); XCTAssertTrue(otherAccount.text.isEmpty)
    }
    func testSuccessfulSendDoesNotClearNewReplyWithSameTextOrDoubleSend() async throws {
        let started = expectation(description: "Sending")
        let respond = DispatchSemaphore(value: 0)
        defer { respond.signal() }
        var writes = 0
        let (store, _, _) = try setup { _ in
            writes += 1; started.fulfill()
            // Hold the response until the reply address really changed. A
            // fixed sleep can expire before a busy simulator resumes this test.
            guard respond.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (200, .object(["comment": self.comment(30), "comment_count": .id(1)]))
        }
        store.text = "同一段文字"
        let pending = Task { await store.send() }
        await fulfillment(of: [started], timeout: 2)
        store.reply = Comment(comment(2, parent: 1)); await store.send()
        respond.signal(); await pending.value
        XCTAssertEqual(writes, 1); XCTAssertEqual(store.text, "同一段文字"); XCTAssertEqual(store.reply?.id, 2)
        XCTAssertNil(store.sendError); XCTAssertEqual(store.commentCount, 1)
    }
    func testDeletingChildKeepsSiblingsAndClearsOnlyItsReplyAddress() async throws {
        let root = comment(1, replies: [comment(2, parent: 1), comment(3, parent: 1)])
        let (store, _, _) = try setup { request in
            if request.httpMethod == "DELETE" { return (200, .object(["comment_count": .id(2)])) }
            return (200, .object(["comments": .array([root])]))
        }
        await store.load(); store.text = "保留输入"; store.reply = store.threads[0].replies[0]
        await store.delete(store.threads[0].replies[0])
        XCTAssertEqual(store.threads[0].replies.map(\.id), [3]); XCTAssertNil(store.reply)
        XCTAssertEqual(store.text, "保留输入"); XCTAssertEqual(store.commentCount, 2)
        await store.load(reset: true); XCTAssertEqual(store.threads[0].replies.map(\.id), [3])
    }
    func testOldRefreshCannotResurrectDeletedComment() async throws {
        let started = expectation(description: "Refresh started")
        var reads = 0, deleted = false
        let root = comment(1)
        let (store, _, _) = try setup { request in
            if request.httpMethod == "DELETE" { deleted = true; return (200, .object(["comment_count": .id(0)])) }
            reads += 1
            if reads == 2 { started.fulfill(); Thread.sleep(forTimeInterval: 0.1); return (200, .object(["comments": .array([root])])) }
            return (200, .object(["comments": .array(deleted ? [] : [root])]))
        }
        await store.load(); let pending = Task { await store.load(reset: true) }
        await fulfillment(of: [started], timeout: 2); await store.delete(store.threads[0].root); await pending.value
        XCTAssertTrue(store.threads.isEmpty); XCTAssertEqual(store.commentCount, 0)
    }
    func testAccountSwitchDoesNotConsumeAnotherAccountsComposer() async throws {
        let started = expectation(description: "Sending old account")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let (store, api, _) = try setup { _ in
            started.fulfill(); _ = release.wait(timeout: .now() + 10)
            return (200, .object(["comment": self.comment(30)]))
        }
        store.text = "旧账号草稿"; let pending = Task { await store.send() }
        await fulfillment(of: [started], timeout: 2)
        try api.setToken("different-account"); release.signal(); await pending.value
        XCTAssertEqual(store.text, "旧账号草稿"); XCTAssertTrue(store.threads.isEmpty); XCTAssertNil(store.notice)
    }
    func testConfirmedLegacyEnvelopeDoesNotInviteDuplicateResend() async throws {
        var writes = 0
        let (store, _, _) = try setup { request in
            if request.httpMethod == "POST" { writes += 1; return (200, .object(["message": .text("ok")])) }
            return (200, .object(["comments": .array([self.comment(30)]), "total": .id(1)]))
        }
        store.text = "发送一次"; await store.send(); await store.send()
        XCTAssertEqual(writes, 1); XCTAssertNil(store.sendError); XCTAssertTrue(store.text.isEmpty)
        XCTAssertEqual(store.threads.map(\.id), [30])
    }
    func testDeletingParentReconcilesRepliesRetainedByServer() async throws {
        var deleted = false
        let child = comment(2)
        let root = comment(1, replies: [comment(2, parent: 1)])
        let (store, _, _) = try setup { request in
            if request.httpMethod == "DELETE" { deleted = true; return (200, .object(["comment_count": .id(1)])) }
            return (200, .object(["comments": .array(deleted ? [child] : [root]), "total": .id(1)]))
        }
        await store.load(); await store.delete(store.threads[0].root)
        XCTAssertEqual(store.threads.map(\.id), [2]); XCTAssertEqual(store.commentCount, 1)
    }
    func testZeroParentIsRootAndSentReplyIsNotLostByPreviewRefresh() async throws {
        var root = comment(1, replies: (2...11).map { comment($0, parent: 1) })
        root["parent_id"] = .id(0); root["replies_has_more"] = .bool(true)
        let (store, _, _) = try setup { request in
            if request.httpMethod == "POST" { return (200, .object(["comment": self.comment(12, parent: 1)])) }
            return (200, .object(["comments": .array([root]), "total": .id(1)]))
        }
        await store.load(); XCTAssertNil(store.threads[0].root.parentID)
        store.reply = store.threads[0].root; store.text = "新回复"; await store.send(); await store.load(reset: true)
        XCTAssertTrue(store.threads[0].expanded); XCTAssertEqual(store.threads[0].replies.last?.id, 12)
    }
    func testPostDetailComposerStaysWithinWindowWithKeyboard() async throws {
        let (_, api, _) = try setup { request in
            if request.url!.path.hasSuffix("/comments") { return (200, .object(["comments": .array([self.comment(1, replies: [self.comment(2, parent: 1)])]), "total": .id(1)])) }
            return (200, .object(["post": .object(["id": .id(50), "content": .text("评论交互验证"), "user_id": .id(7), "comment_count": .id(2)])]))
        }
        let session = AppSession(api: api); session.user = Person(.object(["id": .id(7)])); session.restoring = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let size = UIDevice.current.userInterfaceIdiom == .pad ? CGSize(width: 1032, height: 1376) : CGSize(width: 390, height: 844)
        let controller = UIHostingController(rootView: NavigationStack { PostDetailView(session: session, postID: 50) }.environmentObject(session))
        window.rootViewController = controller; window.frame = CGRect(origin: .zero, size: size); controller.view.frame = window.bounds
        window.makeKeyAndVisible(); window.layoutIfNeeded()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(800))
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let field = try XCTUnwrap(descendants(window).first { $0 is UITextField || $0 is UITextView })
        let initialY = field.convert(field.bounds, to: window).minY
        XCTAssertTrue(field.becomeFirstResponder())
        let deadline = Date().addingTimeInterval(6)
        while field.convert(field.bounds, to: window).minY > initialY - 100, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        let frame = field.convert(field.bounds, to: window)
        XCTAssertLessThan(frame.minY, initialY - 100, "The software keyboard must actually move the comment composer")
        XCTAssertGreaterThan(frame.width, 100); XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, size.width); XCTAssertLessThan(frame.maxY, size.height)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
        attachment.name = "comments-keyboard"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
