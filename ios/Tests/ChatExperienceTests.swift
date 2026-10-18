import XCTest
@testable import Nonto

@MainActor
final class ChatExperienceTests: XCTestCase {
    private let userID = 900020
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        try await super.setUp()
        suite = "nonto-chat-ux-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        try? LocalCache.clear(userID: userID)
    }
    override func tearDown() async throws {
        StubProtocol.handler = nil
        defaults.removePersistentDomain(forName: suite)
        try? LocalCache.clear(userID: userID)
        try await super.tearDown()
    }
    private func message(_ id: Int, sender: Int = 2, time: String = "2026-10-18T10:00:00Z") -> JSON {
        .object(["id": .id(id), "sender_id": .id(sender), "content": .text("message \(id)"), "created_at": .text(time)])
    }
    private func room(conversation: Conversation = Conversation(.object(["id": .id(55)])), _ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> ChatStore {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("chat-ux-account")
        return ChatStore(api: api, conversation: conversation, userID: userID, defaults: defaults)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    private func body(_ request: URLRequest) throws -> JSON {
        if let data = request.httpBody { return try JSON.decode(data) }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let size = stream.read(&buffer, maxLength: buffer.count)
            if size <= 0 { break }
            data.append(contentsOf: buffer.prefix(size))
        }
        return try JSON.decode(data)
    }
    func testTimelineSeparatesPausesAndDaysWithoutRepeatingEveryTimestamp() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let input = [message(1, time: "2026-10-18T23:52:00Z"), message(2, time: "2026-10-18T23:53:00Z"),
                     message(3, sender: 3, time: "2026-10-18T23:54:00Z"), message(4, sender: 3, time: "2026-10-18T23:59:00Z"),
                     message(5, sender: 3, time: "2026-10-19T00:00:00Z")]
        let rows = ChatTimeline.rows(input.map(ChatMessage.init), calendar: calendar)
        XCTAssertEqual(rows.map(\.showsTimestamp), [true, false, false, true, true])
        XCTAssertEqual(rows.map(\.startsRun), [true, false, true, true, true])
    }
    func testRecallBreaksSenderRunAndMissingTimeIsSafe() {
        let rows = ChatTimeline.rows([ChatMessage(message(1)), ChatMessage(message(2).merging(.object(["is_recalled": .bool(true)]))),
                                      ChatMessage(message(3)), ChatMessage(.object(["id": .id(4), "sender_id": .id(2)]))])
        XCTAssertEqual(rows.map(\.startsRun), [true, true, true, false])
        XCTAssertFalse(rows.last!.showsTimestamp)
    }
    func testHistoryRequestIsNotLostBehindRefresh() async throws {
        var pages: [String] = []
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            pages.append(page); Thread.sleep(forTimeInterval: 0.06)
            return (200, .object(["messages": .array((page == "1" ? Array(51...100) : Array(1...50)).map { self.message($0) })]))
        }
        await store.activate(); pages = []
        let refresh = Task { await store.load() }
        try await waitUntil { store.loading }
        await store.load(older: true); await refresh.value
        XCTAssertEqual(pages, ["1", "2"]); XCTAssertEqual(store.messages.count, 100)
        XCTAssertFalse(store.loading); XCTAssertFalse(store.loadingOlder); store.suspend()
    }
    func testRefreshIsNotLostBehindHistoryRequest() async throws {
        var pages: [String] = []
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            pages.append(page); Thread.sleep(forTimeInterval: 0.06)
            return (200, .object(["messages": .array((51...100).map { self.message($0) })]))
        }
        await store.activate(); pages = []
        let history = Task { await store.load(older: true) }
        try await waitUntil { store.loadingOlder }
        await store.load(); await history.value
        XCTAssertEqual(pages, ["2", "1"]); store.suspend()
    }
    func testFullFinalPageRespectsServerHasMoreFalse() async throws {
        var fetches = 0
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            fetches += 1
            return (200, .object(["messages": .array((1...50).map { self.message($0) }), "has_more": .bool(false)]))
        }
        await store.activate(); XCTAssertFalse(store.more)
        await store.load(older: true); XCTAssertEqual(fetches, 1); store.suspend()
    }
    func testHistoryAcknowledgementUnblocksFollowingQueuedMessageWhileRoomStaysOpen() async throws {
        var confirmed: JSON?, sends: [String] = []
        let store = try room { request in
            if request.url!.path.hasSuffix("mark-read") { return (200, .null) }
            if request.httpMethod == "POST" {
                let payload = try self.body(request); sends.append(payload["content"].string)
                if sends.count == 1 {
                    confirmed = self.message(100, sender: self.userID).merging(.object(["request_id": payload["request_id"]]))
                    return (504, .object(["detail": .text("acknowledgement lost")]))
                }
                return (200, .object(["message": self.message(101, sender: self.userID)]))
            }
            return (200, .object(["messages": .array(confirmed.map { [$0] } ?? [])]))
        }
        await store.activate(); store.enqueue(content: "first"); store.enqueue(content: "second")
        try await waitUntil { !store.sending }; XCTAssertEqual(store.pending.count, 2)
        await store.load(); try await waitUntil { !store.sending }
        XCTAssertEqual(sends, ["first", "second"]); XCTAssertTrue(store.pending.isEmpty); store.suspend()
    }
    func testInFlightMessageCannotBeRemovedAsIfItWereUnsent() async throws {
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                Thread.sleep(forTimeInterval: 0.1)
                return (200, .object(["message": self.message(100, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); store.enqueue(content: "sending")
        try await waitUntil { store.sendingID != nil }
        store.remove(store.pending[0].id); XCTAssertEqual(store.pending.count, 1)
        try await waitUntil { !store.sending }
        XCTAssertNil(store.sendingID); XCTAssertTrue(store.pending.isEmpty); store.suspend()
    }
    func testLeavingRoomImmediatelyFlushesDebouncedDraft() async throws {
        let store = try room { _ in (200, .object(["messages": .array([])])) }
        await store.activate(); store.draft = "刚输入的草稿"; store.scheduleDraftSave(); store.suspend()
        XCTAssertEqual(defaults.string(forKey: "nonto.native.chat-draft.900020.chat.single.55"), "刚输入的草稿")
    }
    func testRecallUpdatesBubbleWhenHistoryOmitsRecalledMessages() async throws {
        var recalled = false
        let conversation = Conversation(.object(["id": .id(55), "type": .text("community"), "community_id": .id(33)]))
        let store = try room(conversation: conversation) { request in
            if request.httpMethod == "DELETE" { recalled = true; return (200, .null) }
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["conversation": .object(["id": .id(55)]), "messages": .array(recalled ? [] : [self.message(1, sender: self.userID)])]))
        }
        await store.activate(); await store.recall(try XCTUnwrap(store.messages.first))
        XCTAssertTrue(recalled); XCTAssertTrue(try XCTUnwrap(store.messages.first).recalled)
        XCTAssertEqual(store.messages.first?.content, ""); store.suspend()
    }
}
