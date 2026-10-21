import XCTest
import Observation
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
    func testTypingAndUnchangedRefreshDoNotInvalidatePreparedMessages() async throws {
        var current = message(81, sender: userID)
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["messages": .array([current])]))
        }
        await store.activate()
        let unchanged = expectation(description: "Timeline should stay untouched"); unchanged.isInverted = true
        withObservationTracking { _ = store.timeline.rows; _ = store.messages } onChange: { unchanged.fulfill() }
        store.draft = "输入草稿不会刷新消息"
        await store.load()
        await fulfillment(of: [unchanged], timeout: 0.05)
        let changed = expectation(description: "Read receipts must still update")
        withObservationTracking { _ = store.timeline.rows } onChange: { changed.fulfill() }
        current = current.merging(.object(["is_read": .bool(true)]))
        await store.load()
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(store.timeline.rows.first!.message.raw["is_read"].bool)
        XCTAssertEqual(store.timeline.lastOutgoingID, 81); store.suspend()
    }
    func testPreparedGalleryKeepsImageOrderAndSkipsRecalledMedia() {
        let image = message(1).merging(.object(["message_type": .text("image"), "media_url": .text("https://example.test/one.jpg")]))
        let recalled = message(2).merging(.object(["message_type": .text("image"), "media_url": .text("https://example.test/two.jpg"), "is_recalled": .bool(true)]))
        let last = message(3, sender: userID)
        let timeline = ChatPresentation(messages: [image, recalled, last].map(ChatMessage.init), userID: userID)
        XCTAssertEqual(timeline.gallery, ["https://example.test/one.jpg"])
        XCTAssertEqual(timeline.galleryIndexes, [1: 0]); XCTAssertEqual(timeline.lastOutgoingID, 3)
        XCTAssertEqual(timeline.rows.map(\.id), [1, 2, 3])
    }
    func testBottomDetectionUsesTheActualVisibleRectangleWithoutReapplyingInsets() {
        let geometry = ChatViewportMetrics(offset: 200, contentHeight: 900, visibleHeight: 700,
                                           topInset: 0, bottomInset: 100, visibleBottom: 900)
        XCTAssertTrue(geometry.nearBottom)
        XCTAssertEqual(geometry.clamped(600), 200)
    }
    func testHistoryAnchorWaitsForLoadedLayoutAndPreservesOffset() {
        let memory = ChatViewportMemory()
        _ = memory.record(ChatViewportMetrics(offset: 420, contentHeight: 1400, visibleHeight: 600, topInset: 0, bottomInset: 0))
        memory.beginHistory()
        XCTAssertNil(memory.finishHistory(addedRows: true), "The response may finish before SwiftUI measures inserted rows")
        let target = memory.record(ChatViewportMetrics(offset: 420, contentHeight: 2100, visibleHeight: 600, topInset: 0, bottomInset: 0))
        XCTAssertEqual(target, 1120)
        XCTAssertFalse(memory.preservingHistory)
        XCTAssertNil(memory.record(ChatViewportMetrics(offset: 1120, contentHeight: 2100, visibleHeight: 600, topInset: 0, bottomInset: 0)))
    }
    func testReadingCanContinueWhileHistoryIsLoading() {
        let memory = ChatViewportMemory()
        _ = memory.record(ChatViewportMetrics(offset: 200, contentHeight: 1400, visibleHeight: 600, topInset: 0, bottomInset: 0))
        memory.beginHistory(); memory.userScrolling = true
        XCTAssertNil(memory.record(ChatViewportMetrics(offset: 260, contentHeight: 1400, visibleHeight: 600, topInset: 0, bottomInset: 0)))
        XCTAssertEqual(memory.record(ChatViewportMetrics(offset: 260, contentHeight: 2000, visibleHeight: 600, topInset: 0, bottomInset: 0)), 860)
    }
    func testReturningFromMediaKeepsReadingOffsetAcrossKeyboardAndIncomingMessages() {
        let memory = ChatViewportMemory()
        _ = memory.record(ChatViewportMetrics(offset: 450, contentHeight: 1600, visibleHeight: 350, topInset: 0, bottomInset: 0))
        memory.beginMedia()
        XCTAssertNil(memory.record(ChatViewportMetrics(offset: 450, contentHeight: 1900, visibleHeight: 650, topInset: 0, bottomInset: 0)))
        XCTAssertEqual(memory.endMedia(), 450, "New messages at the end must not change the old reading position")
        XCTAssertFalse(memory.presentingMedia)
    }
    func testRepeatedRetryKeepsOneMediaMessageAndItsOriginalIdempotencyKey() async throws {
        var sent: [JSON] = []
        let conversation = Conversation(.object(["id": .id(55), "type": .text("community"), "community_id": .id(33)]))
        let store = try room(conversation: conversation) { request in
            if request.url!.path.hasSuffix("/chat/messages"), request.httpMethod == "POST" {
                let payload = try self.body(request); sent.append(payload)
                if sent.count == 1 { return (503, .object(["detail": .text("暂时无法发送")])) }
                Thread.sleep(forTimeInterval: 0.06)
                return (200, .object(["message": self.message(100, sender: self.userID)]))
            }
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate()
        XCTAssertTrue(store.enqueueMedia([(url: "https://example.test/video.mp4", kind: "video")], caption: "视频说明", quoteID: 12))
        try await waitUntil { !store.sending }
        let id = try XCTUnwrap(store.pending.first?.id)
        store.retry(id); store.retry(id)
        try await waitUntil { !store.sending }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.map { $0["client_msg_id"].string }, [id, id])
        XCTAssertEqual(sent.last?["media_url"].string, "https://example.test/video.mp4")
        XCTAssertEqual(sent.last?["quote_message_id"].int, 12)
        XCTAssertTrue(store.pending.isEmpty); XCTAssertEqual(store.messages.count, 1); store.suspend()
    }
    func testNotificationConversationLookupFindsTheServerIDBeyondFirstPage() async throws {
        var pages: [String] = []
        StubProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/chat/sessions"))
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            pages.append(page)
            if page == "1" { return (200, .object(["sessions": .array((1...50).map { .object(["id": .id($0)]) }), "has_more": .bool(true)])) }
            return (200, .object(["sessions": .array([.object(["id": .id(999), "conversation_id": .id(63)])]), "has_more": .bool(false)]))
        }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("lookup-fixture")
        let room = try await ConversationLookup.find(63, api: api)
        XCTAssertEqual(room.id, 63); XCTAssertEqual(pages, ["1", "2"])
    }
    func testImageBatchIsDurableOrderedAndRejectsAnInvalidBatchAtomically() throws {
        let store = try room { _ in (200, .object([:])) }
        XCTAssertTrue(store.enqueueMedia([(url: "https://example.test/first.jpg", kind: "image"),
                                         (url: "https://example.test/second.jpg", kind: "image")], caption: "  caption  ", quoteID: 12))
        XCTAssertEqual(store.pending.map(\.media), ["https://example.test/first.jpg", "https://example.test/second.jpg"])
        XCTAssertEqual(store.pending.map(\.content), ["caption", ""])
        XCTAssertEqual(store.pending.map(\.quoteID), [12, nil])
        XCTAssertEqual(Set(store.pending.map(\.id)).count, 2)
        XCTAssertFalse(store.enqueueMedia([(url: "file:///private/image", kind: "image")], caption: ""))
        XCTAssertEqual(store.pending.count, 2)
        let key = "nonto.native.outbox.\(userID).chat.single.55"
        let data = try XCTUnwrap(defaults.data(forKey: key))
        let restored = try JSONDecoder().decode([PendingMessage].self, from: data)
        XCTAssertEqual(restored.map(\.id), store.pending.map(\.id))
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
