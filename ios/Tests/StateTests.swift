import XCTest
import ImageIO
import UIKit
@testable import Nonto

@MainActor
final class StateTests: XCTestCase {
    private let userID = 900010
    override func tearDown() {
        super.tearDown()
        StubProtocol.handler = nil
    }
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> APIClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("account-A"); return api
    }
    private func post(_ id: Int, _ content: String) -> JSON { .object(["id": .id(id), "content": .text(content)]) }
    private func resource(_ api: APIClient, query: [String: String] = [:]) -> PagedResource<Post> {
        PagedResource(api: api, path: "/test/\(UUID().uuidString)", keys: ["posts"], query: query, userID: userID, pageSize: 2)
    }
    private func body(_ request: URLRequest) throws -> JSON {
        if let data = request.httpBody { return try JSON.decode(data) }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeContentData) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try JSON.decode(data)
    }
    private func message(_ id: Int, sender: Int = 2) -> JSON { .object(["id": .id(id), "sender_id": .id(sender), "content": .text("message \(id)"), "created_at": .text("2026-10-17T10:00:00Z")]) }
    private func room(_ api: APIClient) -> (ChatStore, UserDefaults) {
        try? LocalCache.clear(userID: userID)
        let defaults = UserDefaults(suiteName: "nonto-tests-\(UUID())")!
        let store = ChatStore(api: api, conversation: Conversation(.object(["id": .id(55)])), userID: userID, defaults: defaults)
        return (store, defaults)
    }
    private func waitForDelivery(_ store: ChatStore) async throws {
        for _ in 0..<200 {
            if !store.sending { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Delivery did not finish")
    }
    func testPageOverlapUpdatesExistingWithoutReordering() async throws {
        var page = 0
        let api = try client { _ in
            page += 1
            return (200, .object(["posts": .array(page == 1 ? [self.post(1, "old"), self.post(2, "two")] : [self.post(1, "updated"), self.post(3, "three")])]))
        }
        let feed = resource(api)
        await feed.load(reset: true); await feed.load()
        XCTAssertEqual(feed.items.map(\.id), [1, 2, 3]); XCTAssertEqual(feed.items[0].content, "updated")
    }
    func testMalformedRefreshPreservesContentAndPage() async throws {
        var calls = 0
        let api = try client { _ in
            calls += 1
            return (200, calls == 1 ? .object(["posts": .array([self.post(1, "cached"), self.post(2, "two")])]) : .object(["unexpected": .bool(true)]))
        }
        let feed = resource(api); await feed.load(reset: true); await feed.load(reset: true)
        XCTAssertEqual(feed.items.count, 2); XCTAssertEqual(feed.page, 1); XCTAssertNotNil(feed.error)
    }
    func testRepeatedPageAndEmptyPageStopPagination() async throws {
        let api = try client { _ in (200, .object(["posts": .array([self.post(1, "one"), self.post(2, "two")]), "has_more": .bool(true)])) }
        let feed = resource(api); await feed.load(reset: true); XCTAssertTrue(feed.hasMore)
        await feed.load(); XCTAssertFalse(feed.hasMore)
        let emptyAPI = try client { _ in (200, .object(["posts": .array([]), "has_more": .bool(true), "total_pages": .id(99)])) }
        let empty = resource(emptyAPI); await empty.load(reset: true); XCTAssertFalse(empty.hasMore)
    }
    func testConcurrentRefreshesShareOneRequest() async throws {
        var calls = 0
        let api = try client { _ in calls += 1; Thread.sleep(forTimeInterval: 0.03); return (200, .array([self.post(1, "one")])) }
        let feed = resource(api)
        async let first: Void = feed.load(reset: true)
        async let second: Void = feed.load(reset: true)
        _ = await (first, second)
        XCTAssertEqual(calls, 1); XCTAssertFalse(feed.loading)
    }
    func testCacheIdentitySeparatesQueryDelimitersAndSupportsLongQueries() throws {
        let api = try client { _ in (200, .null) }
        let a = PagedResource<Post>(api: api, path: "/search", keys: ["posts"], query: ["q": "a&b=c"], userID: userID)
        let b = PagedResource<Post>(api: api, path: "/search", keys: ["posts"], query: ["q": "a", "b": "c"], userID: userID)
        XCTAssertNotEqual(a.cacheKey, b.cacheKey)
        let key = String(repeating: "中文&=", count: 1000)
        LocalCache.write(.array([.text("cached")]), userID: userID, key: key)
        XCTAssertEqual(LocalCache.read(userID: userID, key: key), .array([.text("cached")]))
        try LocalCache.clear(userID: userID)
    }
    func testMutationSurvivesAnInFlightRefresh() async throws {
        let api = try client { _ in Thread.sleep(forTimeInterval: 0.03); return (200, .array([self.post(1, "old"), self.post(2, "deleted")])) }
        let feed = resource(api)
        let task = Task { await feed.load(reset: true) }
        while !feed.loading { await Task.yield() }
        feed.apply(id: 1, patch: .object(["content": .text("edited")])); feed.apply(id: 2, patch: nil)
        await task.value
        XCTAssertEqual(feed.items.map(\.id), [1]); XCTAssertEqual(feed.items.first?.content, "edited")
    }
    func testChatQueueDrainsRapidSendsInOrder() async throws {
        var contents: [String] = []
        let api = try client { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                let body = try self.body(request); contents.append(body["content"].string)
                return (200, .object(["message": self.message(100 + contents.count, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        let (store, _) = room(api); await store.activate()
        XCTAssertTrue(store.enqueue(content: "first")); XCTAssertTrue(store.enqueue(content: "second"))
        try await waitForDelivery(store)
        XCTAssertEqual(contents, ["first", "second"]); XCTAssertTrue(store.pending.isEmpty); XCTAssertEqual(store.messages.count, 2)
        store.suspend()
    }
    func testChatRetryKeepsIdempotencyKeyAndBlocksLaterMessages() async throws {
        var ids: [String] = [], fail = true
        let api = try client { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                let body = try self.body(request); ids.append(body["request_id"].string)
                if fail { return (503, .object(["detail": .text("offline")])) }
                return (200, .object(["message": self.message(100 + ids.count)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        let (store, _) = room(api); await store.activate()
        store.enqueue(content: "first"); store.enqueue(content: "second"); try await waitForDelivery(store)
        XCTAssertEqual(ids.count, 1); XCTAssertNotNil(store.pending.first?.failure)
        fail = false; store.retry(store.pending[0].id); try await waitForDelivery(store)
        XCTAssertEqual(ids.count, 3); XCTAssertEqual(ids[0], ids[1]); XCTAssertNotEqual(ids[1], ids[2]); XCTAssertTrue(store.pending.isEmpty)
        store.suspend()
    }
    func testIncompleteSendConfirmationRetainsOutboxEntry() async throws {
        let api = try client { request in
            request.httpMethod == "GET" ? (200, .object(["messages": .array([])])) : (200, .object(["ok": .bool(true)]))
        }
        let (store, _) = room(api); await store.activate(); store.enqueue(content: "keep me"); try await waitForDelivery(store)
        XCTAssertEqual(store.pending.count, 1); XCTAssertNotNil(store.pending.first?.failure); store.suspend()
    }
    func testChatPreservesReadingPositionAndAvoidsRedundantReadRequests() async throws {
        var reads = 0, newest = 1
        let api = try client { request in
            if request.url!.path.hasSuffix("mark-read") { reads += 1; return (200, .null) }
            return (200, .object(["messages": .array((1...newest).map { self.message($0) })]))
        }
        let (store, _) = room(api); await store.activate(); let before = store.scrollRequest
        await store.load(); XCTAssertEqual(reads, 1)
        store.reachedBottom(false); newest = 2; await store.load()
        XCTAssertEqual(store.scrollRequest, before); XCTAssertEqual(store.unread, 1); XCTAssertEqual(reads, 2)
        store.jumpToLatest(); XCTAssertEqual(store.unread, 0); XCTAssertGreaterThan(store.scrollRequest, before); store.suspend()
    }
    func testChatDraftRestoresAndOldAccountCannotSend() async throws {
        var sends = 0
        let api = try client { request in if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") { sends += 1 }; return (200, .object(["messages": .array([])])) }
        let (first, defaults) = room(api); await first.activate(); first.draft = "unsent draft"; first.suspend()
        let second = ChatStore(api: api, conversation: Conversation(.object(["id": .id(55)])), userID: userID, defaults: defaults)
        await second.activate(); XCTAssertEqual(second.draft, "unsent draft")
        try api.setToken("account-B")
        XCTAssertFalse(second.enqueue(content: "must not send")); XCTAssertEqual(sends, 0); second.suspend()
    }
    func testSuspendedChatDoesNotFetchOrDeliverUntilReactivated() async throws {
        var calls = 0, sends = 0
        let api = try client { request in
            calls += 1
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1; return (200, .object(["message": self.message(100)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        let (store, _) = room(api); await store.activate(); store.suspend()
        let before = calls
        store.enqueue(content: "queued while away"); await store.load()
        XCTAssertEqual(calls, before); XCTAssertEqual(sends, 0); XCTAssertEqual(store.pending.count, 1)
        await store.activate(); try await waitForDelivery(store)
        XCTAssertEqual(sends, 1); XCTAssertTrue(store.pending.isEmpty); store.suspend()
    }
    func testServerHistoryReconcilesAnUnacknowledgedSendWithoutResending() async throws {
        var sends = 0, confirmed: JSON?
        let api = try client { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1
                let body = try self.body(request)
                confirmed = self.message(100).merging(.object(["request_id": body["request_id"]]))
                throw URLError(.networkConnectionLost)
            }
            return (200, .object(["messages": .array(confirmed.map { [$0] } ?? [])]))
        }
        let (store, _) = room(api); await store.activate(); store.enqueue(content: "accepted on server")
        try await waitForDelivery(store); XCTAssertEqual(store.pending.count, 1)
        store.suspend(); await store.activate(); try await waitForDelivery(store)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertEqual(sends, 1); XCTAssertEqual(store.messages.last?.id, 100); store.suspend()
    }
    func testCachedHistoryOverlapDoesNotHideOlderPages() async throws {
        let api = try client { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1"
            let ids = page == "1" ? Array(151...200) : (page == "2" ? Array(101...150) : Array(51...100))
            return (200, .object(["messages": .array(ids.map { self.message($0) })]))
        }
        let (store, _) = room(api)
        LocalCache.write(.array((101...200).map { message($0) }), userID: userID, key: "chat.single.55")
        await store.activate(); await store.load(older: true)
        XCTAssertTrue(store.more)
        await store.load(older: true)
        XCTAssertEqual(store.messages.first?.id, 51); XCTAssertEqual(store.messages.count, 150); store.suspend()
    }
    func testResourceCannotFetchUnderAnotherAccountsToken() async throws {
        var calls = 0
        let api = try client { _ in calls += 1; return (200, .array([self.post(1, "account B")])) }
        let old = resource(api)
        try api.setToken("account-B")
        await old.load(reset: true)
        XCTAssertEqual(calls, 0); XCTAssertTrue(old.items.isEmpty)
    }
    func testPhotoDownsamplingAndInvalidData() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500)) }
        let media = try SelectedMedia.image(XCTUnwrap(image.pngData()))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(media.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1920); XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 960)
        XCTAssertEqual(media.mime, "image/jpeg"); XCTAssertThrowsError(try SelectedMedia.image(Data([1, 2, 3])))
    }
}
