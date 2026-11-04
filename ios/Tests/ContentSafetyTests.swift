import XCTest
import Combine
@testable import Nonto

@MainActor
final class ContentSafetyTests: XCTestCase {
    override func tearDown() { StubProtocol.handler = nil; super.tearDown() }
    private func post(_ id: Int, author: Int = 2) -> Post {
        Post(.object(["id": .id(id), "user_id": .id(author), "content": .text("post \(id)")]))
    }
    private func session(defaults: UserDefaults? = nil, handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> AppSession {
        StubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("safety-account")
        let session = AppSession(api: api, contentDefaults: defaults ?? UserDefaults(suiteName: "safety-\(UUID())")!)
        session.user = Person(.object(["id": .id(900011)])); session.restoreContentSafety(userID: 900011)
        return session
    }
    private func list(_ session: AppSession, initial: [Post] = []) -> PagedResource<Post> {
        let resource = PagedResource<Post>(api: session.api, path: "/posts/", keys: ["posts"], userID: 900011, cacheEnabled: false)
        resource.items = initial
        resource.observePostChanges(in: session); return resource
    }
    func testHidePersistsAcrossRelaunchAndIsIsolatedBetweenAccounts() async throws {
        let defaults = UserDefaults(suiteName: "safety-\(UUID())")!
        let first = try session(defaults: defaults) { _ in (503, .object(["detail": .text("offline")])) }
        await first.setPostHidden(post(10), hidden: true)
        XCTAssertNotNil(first.contentSafety.hiddenPosts[10]); XCTAssertEqual(first.pendingPostHides[10], true)
        let relaunched = try session(defaults: defaults) { _ in (200, .object([:])) }
        XCTAssertNil(relaunched.contentSafety.visible(post(10)))
        XCTAssertNotNil(relaunched.contentSafety.visible(post(11)))
        relaunched.restoreContentSafety(userID: 900012)
        XCTAssertTrue(relaunched.contentSafety.hiddenPosts.isEmpty)
        relaunched.restoreContentSafety(userID: 900011)
        await relaunched.syncPostHides()
        XCTAssertTrue(relaunched.pendingPostHides.isEmpty)
        XCTAssertNil(relaunched.contentSafety.visible(post(10)))
    }
    func testAllLoadedListsAndDetailImmediatelyRemoveOnlySelectedPost() async throws {
        let session = try session { _ in (200, .object([:])) }
        let feed = list(session, initial: [post(10), post(11)]), search = list(session, initial: [post(10)])
        let detail = PostDetailResource(session: session, postID: 10, initial: post(10))
        await session.setPostHidden(post(10), hidden: true)
        XCTAssertEqual(feed.items.map(\.id), [11]); XCTAssertTrue(search.items.isEmpty)
        XCTAssertTrue(detail.hidden); XCTAssertNil(detail.post)
        await session.setPostHidden(post(10), hidden: false)
        XCTAssertNotNil(session.contentSafety.visible(post(10)))
    }
    func testLateFeedResponseCannotReintroduceHiddenPost() async throws {
        let started = expectation(description: "Feed started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let wire = post(10).raw
        let session = try session { request in
            if request.url!.path == "/api/posts/" {
                started.fulfill()
                guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                return (200, .object(["posts": .array([wire])]))
            }
            return (200, .object([:]))
        }
        let feed = list(session)
        let fetch = Task { await feed.load(reset: true) }
        await fulfillment(of: [started], timeout: 3)
        // Update the choice while the URLProtocol serial queue is occupied.
        var safety = session.contentSafety; safety.hiddenPosts[10] = wire; session.contentSafety = safety
        release.signal(); await fetch.value
        XCTAssertTrue(feed.items.isEmpty)
    }
    func testNestedAndLegacyQuoteCopiesAreRedactedWithoutLosingOwnCommentary() {
        let original = post(10)
        let quote = Post(.object(["id": .id(20), "user_id": .id(3), "content": .text("my commentary"), "quote_post": original.raw]))
        var safety = ContentSafety(); safety.hiddenPosts[10] = original.raw
        let visible = safety.visible(quote)
        XCTAssertEqual(visible?.content, "my commentary"); XCTAssertNil(visible?.quoted)
        XCTAssertEqual(visible?.raw["quoted_post_unavailable"], .bool(true))
        XCTAssertEqual(visible?.raw["quote_post"], .null)
        safety.hiddenPosts = [:]; safety.blockedUsers = [2]
        XCTAssertNil(safety.visible(quote)?.quoted)
        XCTAssertNil(safety.visible(original))
    }
    func testFailedUserBlockRollsBackPreferenceAndReportsAnError() async throws {
        let session = try session { _ in (503, .object(["detail": .text("offline")])) }
        let feed = list(session, initial: [post(10), post(11, author: 3)])
        var observed: [Bool] = []
        let observation = session.$contentSafety.sink { observed.append($0.blockedUsers.contains(2)) }
        defer { observation.cancel() }
        do { try await session.setUserBlocked(2, blocked: true); XCTFail("Expected failure") } catch {}
        XCTAssertTrue(observed.contains(true)); XCTAssertFalse(session.contentSafety.blockedUsers.contains(2))
        XCTAssertEqual(feed.items.map(\.id), [10, 11])
        XCTAssertNotNil(session.contentSafetyError)
    }
    func testUserBlockRemovesAllAuthorPostsAndRetainsOtherAuthors() async throws {
        let session = try session { _ in (200, .object(["moderation_notified": .bool(true)])) }
        let feed = list(session, initial: [post(10), post(11), post(12, author: 3)])
        try await session.setUserBlocked(2, blocked: true, sourcePostID: 10)
        XCTAssertEqual(feed.items.map(\.id), [12])
        session.clearUI()
        XCTAssertTrue(session.contentSafety.blockedUsers.isEmpty)
        XCTAssertTrue(session.pendingPostHides.isEmpty)
    }
    func testRestoreOfflineKeepsDesiredStateAndQueuesServerRemoval() async throws {
        let session = try session { _ in (503, .object(["detail": .text("offline")])) }
        await session.setPostHidden(post(10), hidden: true)
        await session.setPostHidden(post(10), hidden: false)
        XCTAssertNotNil(session.contentSafety.visible(post(10)))
        XCTAssertEqual(session.pendingPostHides[10], false)
        XCTAssertNotNil(session.contentSafetyError)
    }
    func testLateDetailResponseRedactsUserBlockedWhileLoading() async throws {
        let started = expectation(description: "Detail started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let wire = post(10).raw
        let session = try session { _ in
            started.fulfill()
            guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (200, .object(["post": wire]))
        }
        let detail = PostDetailResource(session: session, postID: 10)
        let fetch = Task { await detail.load() }
        await fulfillment(of: [started], timeout: 3)
        var safety = session.contentSafety; safety.blockedUsers.insert(2); session.contentSafety = safety
        release.signal(); await fetch.value
        XCTAssertNil(detail.post); XCTAssertTrue(detail.hidden)
    }
}
