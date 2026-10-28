import XCTest
import Combine
@testable import Nonto

@MainActor
final class UserExperienceTests: XCTestCase {
    func testBlockEnvelopeUsesBlockedUserInsteadOfBlockPrimaryKey() {
        let raw: JSON = .object(["id": .id(8), "blocker_id": .id(1), "blocked_id": .id(93),
            "blocked_user": .object(["id": .id(93), "username": .text("artist"), "display_name": .text("画师")])])
        let record = BlockedRecord(raw)
        XCTAssertEqual(record.id, 93)
        XCTAssertEqual(record.person.id, 93)
        XCTAssertEqual(record.person.name, "画师")
        XCTAssertEqual(BlockedRecord(record.raw).id, 93)
    }
    func testDeletedBlockedUserKeepsOnlyKnownTargetIdentity() {
        let record = BlockedRecord(.object(["id": .id(8), "blocked_id": .id(93), "blocked_user": .null]))
        XCTAssertEqual(record.id, 93)
        XCTAssertFalse(record.person.name.isEmpty)
        XCTAssertEqual(BlockedRecord(.object(["id": .id(8), "blocker_id": .id(1), "blocked_user": .null])).id, 0)
        XCTAssertEqual(BlockedRecord(.object(["user": .object(["id": .id(93)])])).id, 93)
    }
    func testProvisionalLikeSurvivesStaleRefreshAndCanRollBack() async throws {
        let original: JSON = .object(["id": .id(1), "content": .text("keep this"), "is_liked": .bool(false), "like_count": .id(4)])
        let api = try api { _ in (200, .object(["posts": .array([original])])) }
        let resource = posts(api)
        resource.items = [Post(original)]
        resource.apply(id: 1, patch: .object(["is_liked": .bool(true), "like_count": .id(5)]), provisional: true)
        await resource.load(reset: true)
        XCTAssertTrue(resource.items[0].liked)
        XCTAssertEqual(resource.items[0].likes, 5)
        resource.apply(id: 1, patch: .object(["is_liked": .bool(false), "like_count": .id(4)]))
        XCTAssertFalse(resource.items[0].liked)
        XCTAssertEqual(resource.items[0].content, "keep this")
        await resource.load(reset: true)
        XCTAssertEqual(resource.items[0].likes, 4)
    }
    func testFailedPostLikeBroadcastsOptimisticStateThenRollback() async throws {
        let api = try api { _ in (503, .object(["detail": .text("offline")])) }
        let session = AppSession(api: api)
        session.user = Person(.object(["id": .id(userID)]))
        var changes: [PostChange] = []
        let observer = session.$postChange.compactMap { $0 }.sink { changes.append($0) }
        defer { observer.cancel() }
        let post = Post(.object(["id": .id(1), "is_liked": .bool(false), "like_count": .id(4)]))
        do { try await session.togglePostLike(post); XCTFail("Expected request failure") } catch {}
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.first?.patch?["is_liked"], .bool(true))
        XCTAssertEqual(changes.first?.provisional, true)
        XCTAssertEqual(changes.last?.patch?["like_count"], .id(4))
        XCTAssertEqual(changes.last?.provisional, false)
        XCTAssertEqual(session.pendingLikePatch(for: 1), .object([:]))
    }
    private let userID = 900030
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        try await super.setUp()
        suite = "nonto-ux-\(UUID())"; defaults = UserDefaults(suiteName: suite)
        try? LocalCache.clear(userID: userID)
    }
    override func tearDown() async throws {
        StubProtocol.handler = nil
        defaults.removePersistentDomain(forName: suite)
        try? LocalCache.clear(userID: userID)
        try await super.tearDown()
    }
    private func api(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> APIClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("ux-account"); return api
    }
    private func posts(_ api: APIClient) -> PagedResource<Post> {
        PagedResource(api: api, path: "/ux-posts", keys: ["posts"], userID: userID, pageSize: 2)
    }
    private func post(_ id: Int) -> JSON { .object(["id": .id(id), "content": .text("post \(id)")]) }
    private func page(_ request: URLRequest) -> String {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
    }
    func testRetryRepeatsFailedRefreshInsteadOfAdvancing() async throws {
        var pages: [String] = []
        let api = try api { request in
            pages.append(self.page(request))
            if pages.count == 2 { return (503, .object(["detail": .text("temporarily unavailable")])) }
            return (200, .object(["posts": .array([self.post(1), self.post(2)])]))
        }
        let resource = posts(api)
        await resource.load(reset: true); await resource.load(reset: true)
        XCTAssertNotNil(resource.error); XCTAssertEqual(resource.items.count, 2)
        await resource.retry()
        XCTAssertEqual(pages, ["1", "1", "1"]); XCTAssertNil(resource.error)
    }
    func testRetryRepeatsFailedNextPage() async throws {
        var pages: [String] = []
        let api = try api { request in
            pages.append(self.page(request))
            if pages.count == 2 { return (503, .object(["detail": .text("offline")])) }
            return (200, .array((self.page(request) == "1" ? [1, 2] : [3]).map { self.post($0) }))
        }
        let resource = posts(api)
        await resource.load(reset: true); await resource.load(); await resource.retry()
        XCTAssertEqual(pages, ["1", "2", "2"]); XCTAssertEqual(resource.items.map(\.id), [1, 2, 3])
    }
    func testReturningToFreshResourcePreservesLoadedPages() async throws {
        var calls = 0
        let api = try api { request in
            calls += 1
            return (200, .array((self.page(request) == "1" ? [1, 2] : [3]).map { self.post($0) }))
        }
        let resource = posts(api)
        await resource.loadIfNeeded(); await resource.load(); await resource.loadIfNeeded()
        XCTAssertEqual(calls, 2); XCTAssertEqual(resource.page, 2); XCTAssertEqual(resource.items.count, 3)
    }
    func testExplicitRefreshAndExpiredFreshnessStillFetch() async throws {
        var calls = 0
        let api = try api { _ in calls += 1; return (200, .array([self.post(calls)])) }
        let resource = posts(api)
        await resource.loadIfNeeded(); await resource.load(reset: true); await resource.loadIfNeeded(maxAge: 0)
        XCTAssertEqual(calls, 3); XCTAssertEqual(resource.items.map(\.id), [3])
    }
    func testCacheIndicatorClearsOnlyAfterSuccessfulFetch() async throws {
        var fail = true
        let api = try api { _ in
            fail ? (503, .object(["detail": .text("offline")])) : (200, .array([self.post(2)]))
        }
        let key = posts(api).cacheKey
        LocalCache.write(.array([post(1)]), userID: userID, key: key)
        let resource = posts(api)
        XCTAssertTrue(resource.showingCache)
        await resource.loadIfNeeded(); XCTAssertTrue(resource.showingCache); XCTAssertEqual(resource.items.first?.id, 1)
        fail = false; await resource.retry()
        XCTAssertFalse(resource.showingCache); XCTAssertEqual(resource.items.first?.id, 2)
    }
    func testReadAllSurvivesRefreshWithoutMarkingNewArrival() async throws {
        var calls = 0
        let api = try api { _ in
            calls += 1; Thread.sleep(forTimeInterval: 0.04)
            let rows: [JSON] = (calls == 1 ? [1] : [1, 2]).map { .object(["id": .id($0), "is_read": .bool(false)]) }
            return (200, .array(rows))
        }
        let resource = PagedResource<Notice>(api: api, path: "/ux-notices", keys: ["notifications"], userID: userID)
        await resource.load(reset: true)
        let refresh = Task { await resource.load(reset: true) }
        while !resource.loading { await Task.yield() }
        resource.applyAll(patch: .object(["is_read": .bool(true)]))
        await refresh.value
        XCTAssertTrue(resource.items[0].isRead); XCTAssertFalse(resource.items[1].isRead)
    }
    func testDraftPreservesAudienceAndRole() {
        let store = PostDraftStore(defaults: defaults)
        let draft = PostDraft(text: "给朋友看的草稿\n第二行", visibility: "friends", role: "artist")
        store.save(draft, userID: userID)
        XCTAssertEqual(store.read(userID: userID, defaultVisibility: "public"), draft)
    }
    func testDraftSeparatesAccountsCommunitiesAndQuotes() {
        let store = PostDraftStore(defaults: defaults)
        store.save(PostDraft(text: "private draft", visibility: "friends"), userID: userID, communityID: 3, quoteID: 8)
        for (uid, community, quote) in [(userID + 1, 3, 8), (userID, 0, 8), (userID, 3, 0)] {
            XCTAssertEqual(store.read(userID: uid, communityID: community, quoteID: quote, defaultVisibility: "public").text, "")
        }
        XCTAssertEqual(store.read(userID: userID, communityID: 3, quoteID: 8, defaultVisibility: "public").text, "private draft")
    }
    func testLegacyDraftMigratesWithoutLosingText() {
        let key = "nonto.native.draft.\(userID).0.0"
        defaults.set("旧草稿", forKey: key)
        let store = PostDraftStore(defaults: defaults)
        let draft = store.read(userID: userID, defaultVisibility: "friends")
        XCTAssertEqual(draft.text, "旧草稿"); XCTAssertEqual(draft.visibility, "friends")
        store.save(draft, userID: userID)
        XCTAssertNil(defaults.string(forKey: key)); XCTAssertNotNil(defaults.data(forKey: key + ".v2"))
    }
    func testDiscardRemovesLegacyAndCurrentCopies() {
        let key = "nonto.native.draft.\(userID).0.0"
        let store = PostDraftStore(defaults: defaults)
        store.save(PostDraft(text: "new"), userID: userID); defaults.set("legacy", forKey: key)
        store.remove(userID: userID)
        XCTAssertNil(defaults.object(forKey: key)); XCTAssertNil(defaults.object(forKey: key + ".v2"))
        XCTAssertEqual(store.read(userID: userID, defaultVisibility: "friends"), PostDraft(visibility: "friends"))
    }
    func testUnknownSavedAudienceDoesNotBecomePublic() throws {
        let data = Data("{\"text\":\"old private draft\",\"visibility\":\"private\",\"role\":\"\"}".utf8)
        defaults.set(data, forKey: "nonto.native.draft.\(userID).0.0.v2")
        XCTAssertEqual(PostDraftStore(defaults: defaults).read(userID: userID, defaultVisibility: "public").visibility, "friends")
    }
}
