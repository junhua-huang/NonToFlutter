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
    func testNotoEmojiUsesTextRoutesAndPreservesDraft() async throws {
        for community in [false, true] {
            let conversation = Conversation(.object(["id": .id(55), "type": .text(community ? "community" : "single"),
                "community_id": community ? .id(77) : .null]))
            var sent: JSON?
            let store = try room(conversation: conversation) { request in
                if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                    let value = try self.body(request); sent = value
                    XCTAssertEqual(request.url?.path, community ? "/api/communities/77/chat/messages" : "/api/chat/conversations/55/messages")
                    return (200, .object([community ? "message" : "data": self.message(291, sender: self.userID)
                        .merging(.object(["content": value["content"], "message_type": value["message_type"]]))]))
                }
                return (200, .object(["messages": .array([])]))
            }
            await store.activate(); store.draft = "还没写完的文字"
            let emoji = try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600"))
            XCTAssertTrue(store.enqueue(content: emoji.emoji, quoteID: 25))
            try await waitUntil { !store.sending && store.pending.isEmpty }
            XCTAssertEqual(sent?["content"].string, "😀")
            XCTAssertEqual(sent?["message_type"].string, "text")
            XCTAssertEqual(sent?["quote_message_id"].int, 25)
            XCTAssertEqual(store.draft, "还没写完的文字")
            XCTAssertEqual(store.messages.last?.notoEmoji?.first?.id, emoji.id)
            store.suspend()
        }
    }
    func testPendingAndConfirmedBubbleShareIdentityAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1_792_600_000)
        let item = PendingMessage(id: "stable-send", content: "hello", createdAt: date)
        let before = ChatPresentation(userID: userID, pending: [item])
        // The authoritative timestamp can differ from the device clock. Keep the
        // visible separator stable during acknowledgement, then use server data
        // normally in future room sessions.
        let confirmed = ChatMessage(message(201, sender: userID))
        let after = ChatPresentation(messages: [confirmed], userID: userID, pending: [item],
            localIdentities: [201: ChatMessageIdentity(requestID: item.id, createdAt: date)])
        XCTAssertEqual(before.entries.count, 1); XCTAssertEqual(after.entries.count, 1)
        XCTAssertEqual(before.entries[0].id, after.entries[0].id)
        XCTAssertEqual(before.entries[0].row.date, after.entries[0].row.date)
        XCTAssertEqual(before.entries[0].row.showsTimestamp, after.entries[0].row.showsTimestamp)
        XCTAssertNotNil(before.entries[0].pending); XCTAssertNil(after.entries[0].pending)
    }
    func testOtherSendersRequestCannotReplaceLocalPendingBubble() {
        let item = PendingMessage(id: "same-id", content: "my message")
        let incoming = ChatMessage(message(201).merging(.object(["request_id": .text(item.id)])))
        let presentation = ChatPresentation(messages: [incoming], userID: userID, pending: [item])
        XCTAssertEqual(presentation.entries.map(\.id), ["server:201", "local:same-id"])
        XCTAssertNotNil(presentation.entries.last?.pending)
    }
    func testHTTPConfirmationWithoutRequestIDDoesNotReplaceRowOrScrollAgain() async throws {
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                Thread.sleep(forTimeInterval: 0.05)
                return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate()
        let scrolls = store.scrollRequest
        XCTAssertTrue(store.enqueue(content: "hello"))
        let entry = try XCTUnwrap(store.timeline.entries.last)
        try await waitUntil { !store.sending && store.pending.isEmpty }
        XCTAssertEqual(store.timeline.entries.count, 1)
        XCTAssertEqual(store.timeline.entries[0].id, entry.id)
        XCTAssertEqual(store.timeline.entries[0].row.date, entry.row.date)
        XCTAssertEqual(store.scrollRequest, scrolls)
        store.suspend()
    }
    func testSendingFromHistoryJumpsOnceAndAcknowledgementRespectsReadingPosition() async throws {
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                Thread.sleep(forTimeInterval: 0.05)
                return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([self.message(100)])]))
        }
        await store.activate(); store.reachedBottom(false)
        let scrolls = store.scrollRequest
        XCTAssertTrue(store.enqueue(content: "hello"))
        XCTAssertEqual(store.scrollRequest, scrolls + 1)
        store.reachedBottom(false)
        try await waitUntil { !store.sending && store.pending.isEmpty }
        XCTAssertEqual(store.scrollRequest, scrolls + 1); XCTAssertFalse(store.nearBottom)
        store.suspend()
    }
    func testSocketConfirmationRetainsOneBubbleThroughHTTPAndHistoryRefresh() async throws {
        var confirmed: JSON?
        var startedSending = false
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                startedSending = true
                Thread.sleep(forTimeInterval: 0.1)
                return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array(confirmed.map { [$0] } ?? [])]))
        }
        await store.activate(); store.enqueue(content: "hello")
        let item = try XCTUnwrap(store.pending.first)
        let identity = try XCTUnwrap(store.timeline.entries.last?.id)
        try await waitUntil { startedSending }
        confirmed = message(201, sender: userID).merging(.object(["request_id": .text(item.id)]))
        XCTAssertFalse(store.receive(.object(["event": .text("new_message"), "data": .object([
            "conversation_id": .id(55), "message": confirmed!])])) )
        XCTAssertEqual(store.timeline.entries.map(\.id), [identity])
        try await waitUntil { !store.sending }
        await store.load()
        XCTAssertEqual(store.timeline.entries.map(\.id), [identity]); XCTAssertTrue(store.pending.isEmpty)
        store.suspend()
    }
    func testLegacyOutboxWithoutCreatedDateStillDecodes() throws {
        let data = Data("[{\"id\":\"legacy\",\"content\":\"hello\",\"kind\":\"text\"}]".utf8)
        let item = try XCTUnwrap(JSONDecoder().decode([PendingMessage].self, from: data).first)
        XCTAssertNil(item.createdAt)
        XCTAssertEqual(ChatPresentation(userID: userID, pending: [item]).entries.first?.id, "local:legacy")
    }
    func testTypingAndUnchangedRefreshDoNotInvalidatePreparedMessages() async throws {
        let current = message(81, sender: userID)
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
        XCTAssertEqual(store.timeline.lastOutgoingID, 81); store.suspend()
    }
    func testExistingReceiptChangesStillRebuildPreparedMessages() async throws {
        var current = message(81, sender: userID)
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["messages": .array([current])]))
        }
        await store.activate()
        current = current.merging(.object(["is_read": .bool(true)]))
        await store.load()
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
    func testKeyboardCoveredAreaIsExcludedFromReadabilityAndScrollBounds() {
        // Native metrics from the reported keyboard failure: the full bounds
        // remain 896pt tall, but 399pt at the bottom are covered by controls.
        let covered = ChatViewportMetrics(offset: -116, contentHeight: 586, visibleHeight: 896,
                                          topInset: 116, bottomInset: 399)
        XCTAssertFalse(covered.nearBottom)
        XCTAssertEqual(covered.clamped(.greatestFiniteMagnitude), 89)
        XCTAssertEqual(covered.clamped(-1000), -116)
        XCTAssertTrue(covered.shouldLoadHistory(userScrolling: true))
        let revealed = ChatViewportMetrics(offset: 89, contentHeight: 586, visibleHeight: 896,
                                           topInset: 116, bottomInset: 399)
        XCTAssertTrue(revealed.nearBottom)
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
    func testPrivateChatAcceptsTheDeployedBackendsDataConfirmation() async throws {
        var sends = 0
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1
                return (200, .object(["message": .text("Message sent"), "data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); XCTAssertTrue(store.enqueue(content: "这条已经发送成功"))
        try await waitUntil { !store.sending }
        XCTAssertEqual(sends, 1); XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.messages.last?.id, 201); store.suspend()
    }
    func testSendConfirmationsAcceptBothRoutesAndRejectSuccessTextWithoutAMessage() {
        let value = message(200)
        XCTAssertEqual(ChatMessage.confirmation(.object(["message": value]))?.id, 200)
        XCTAssertEqual(ChatMessage.confirmation(.object(["message": .text("Message sent"), "data": value]))?.id, 200)
        XCTAssertEqual(ChatMessage.confirmation(value)?.id, 200)
        XCTAssertNil(ChatMessage.confirmation(.object(["message": .text("success")])) )
    }
    func testRealtimeEnvelopeNormalizesHTTPWebsocketAndCommunityMessages() {
        let value = message(201).merging(.object(["conversation_id": .id(55)]))
        for data in [value, .object(["conversation_id": .id(55), "data": value]),
                     .object(["conversation_id": .id(55), "community_id": .id(33), "message": value])] {
            let event = ChatRealtimeEvent(.object(["event": .text("new_message"), "data": data]))
            XCTAssertEqual(event.conversationID, 55); XCTAssertEqual(event.message.id, 201)
            XCTAssertTrue(event.affectsConversationList)
        }
        XCTAssertFalse(ChatRealtimeEvent(.object(["event": .text("typing")])).affectsConversationList)
        XCTAssertFalse(ChatRealtimeEvent(.object(["event": .text("new_notification")])).affectsConversationList)
    }
    func testRealtimeMessagesUpdateOnlyTheirRoomWithoutFetchingOrMovingHistory() async throws {
        var fetches = 0
        let store = try room { request in
            if request.httpMethod == "GET" { fetches += 1 }
            return (200, .object(["messages": .array([self.message(100)])]))
        }
        await store.activate(); store.reachedBottom(false)
        let scrollRequest = store.scrollRequest
        let unrelated: JSON = .object(["event": .text("new_message"), "data": message(200).merging(.object(["conversation_id": .id(99)]))])
        XCTAssertFalse(store.receive(unrelated)); XCTAssertEqual(store.messages.map(\.id), [100])
        for id in 101...110 {
            let event: JSON = .object(["event": .text("new_message"), "data": .object([
                "conversation_id": .id(55), "data": message(id)])])
            XCTAssertFalse(store.receive(event)); XCTAssertFalse(store.receive(event))
        }
        XCTAssertEqual(store.messages.map(\.id), Array(100...110))
        XCTAssertEqual(store.unread, 10); XCTAssertEqual(store.scrollRequest, scrollRequest)
        XCTAssertEqual(fetches, 1); store.suspend()
    }
    func testCommunityRealtimeUsesResolvedConversationIDAndItsNestedMessage() async throws {
        let conversation = Conversation(.object(["id": .id(33), "type": .text("community"), "community_id": .id(33)]))
        let store = try room(conversation: conversation) { request in
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["conversation": .object(["id": .id(55)]), "messages": .array([])]))
        }
        await store.activate()
        XCTAssertEqual(store.roomID, 55, "Community identity must follow the resolved server conversation, including quote context events")
        XCTAssertFalse(store.receive(.object(["event": .text("new_message"), "data": .object([
            "conversation_id": .id(55), "community_id": .id(33), "message": message(101)])])))
        XCTAssertEqual(store.messages.map(\.id), [101]); store.suspend()
    }
    func testRemoteRecallRemovesMediaEvenOutsideTheLatestHistoryPage() async throws {
        let image = message(1).merging(.object(["message_type": .text("image"), "media_url": .text("https://example.test/old.jpg")]))
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["messages": .array([image] + (2...60).map { self.message($0) })]))
        }
        await store.activate()
        XCTAssertFalse(store.receive(.object(["event": .text("message_recalled"), "data": .object([
            "conversation_id": .id(55), "message_id": .id(1)])])))
        XCTAssertTrue(store.messages.first!.recalled); XCTAssertTrue(store.timeline.gallery.isEmpty)
        XCTAssertEqual(store.messages.first?.content, ""); store.suspend()
    }
    func testAnOlderHTTPRefreshCannotRestoreARecalledImage() {
        let original = ChatMessage(message(1).merging(.object([
            "message_type": .text("image"), "media_url": .text("https://example.test/recalled.jpg")
        ])))
        let recalled = ChatMessage(original.raw.merging(.object([
            "is_recalled": .bool(true), "content": .text(""), "media_url": .null
        ])))
        let result = Records.messages([recalled], [original, ChatMessage(message(2))])
        XCTAssertTrue(result.first!.recalled); XCTAssertTrue(ChatMediaTimeline.images(result).isEmpty)
    }
    func testReadReceiptFailureDoesNotFailMessageLoadingOrClearUnreadHistory() async throws {
        var reads = 0, latest = 1
        let store = try room { request in
            if request.url!.path.hasSuffix("mark-read") { reads += 1; return (503, .object(["detail": .text("try later")])) }
            return (200, .object(["messages": .array((1...latest).map { self.message($0) })]))
        }
        await store.activate(); try await waitUntil { reads == 1 }
        XCTAssertNil(store.error); XCTAssertFalse(store.loading)
        store.reachedBottom(false); latest = 2; await store.load()
        XCTAssertEqual(reads, 1); XCTAssertEqual(store.unread, 1); XCTAssertNil(store.error)
        store.reachedBottom(true); try await waitUntil { reads == 2 }
        XCTAssertEqual(store.unread, 0); store.suspend()
    }
    func testSocketConfirmationContinuesQueueAfterHTTPAcknowledgementIsLost() async throws {
        var sent: [JSON] = []
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                let value = try self.body(request); sent.append(value)
                if sent.count == 1 {
                    Thread.sleep(forTimeInterval: 0.1)
                    return (504, .object(["detail": .text("response lost")]))
                }
                return (200, .object(["data": self.message(202, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); store.enqueue(content: "first"); store.enqueue(content: "second")
        let id = store.pending[0].id
        try await waitUntil { sent.count == 1 }
        XCTAssertFalse(store.receive(.object(["event": .text("new_message"), "data": .object([
            "conversation_id": .id(55), "data": message(201, sender: userID).merging(.object(["request_id": .text(id)]))])])) )
        try await waitUntil { !store.sending }
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(sent.count, 2); XCTAssertEqual(sent.last?["content"].string, "second")
        store.suspend()
    }
    func testPrivateChatUsesSupportedQuoteAndRecallEndpoints() async throws {
        var quoted: Int?, recalled = false
        let store = try room { request in
            if request.url!.path.hasSuffix("/recall") {
                XCTAssertEqual(request.httpMethod, "POST"); recalled = true
                return (200, .object(["success": .bool(true)]))
            }
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                quoted = try self.body(request)["quote_message_id"].int
                return (200, .object(["data": self.message(202, sender: self.userID)]))
            }
            if request.httpMethod == "POST" { return (200, .null) }
            return (200, .object(["messages": .array(recalled ? [] : [self.message(201, sender: self.userID)])]))
        }
        await store.activate(); store.enqueue(content: "引用回复", quoteID: 201)
        try await waitUntil { !store.sending }; XCTAssertEqual(quoted, 201)
        await store.recall(store.messages.first!); XCTAssertTrue(recalled)
        XCTAssertTrue(store.messages.first!.recalled); store.suspend()
    }
    func testUncertainDeliveryIsDistinguishedFromExplicitRejectionAndSurvivesRestore() throws {
        XCTAssertTrue(ChatDeliveryFailure.isUncertain(APIError(status: 504, message: "timeout")))
        XCTAssertTrue(ChatDeliveryFailure.isUncertain(URLError(.timedOut)))
        XCTAssertFalse(ChatDeliveryFailure.isUncertain(APIError(status: 422, message: "rejected")))
        XCTAssertFalse(ChatDeliveryFailure.isUncertain(URLError(.notConnectedToInternet)))
        let legacy = Data("{\"id\":\"old\",\"content\":\"hello\",\"kind\":\"text\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(PendingMessage.self, from: legacy).deliveryUncertain)
        let uncertain = PendingMessage(content: "hello", failure: "timeout", deliveryUncertain: true)
        XCTAssertEqual(try JSONDecoder().decode(PendingMessage.self, from: JSONEncoder().encode(uncertain)).deliveryUncertain, true)
    }
    func testDeployedUnreadCountFieldIsShownOnTheInboxBadge() async throws {
        StubProtocol.handler = { request in
            request.url!.path.hasSuffix("/chat/unread-count")
                ? (200, .object(["total_unread": .id(7)])) : (200, .object(["unread_count": .id(2)]))
        }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("counts-fixture")
        let session = AppSession(api: api); session.user = Person(.object(["id": .id(userID)]))
        await session.refreshCounts()
        XCTAssertEqual(session.messageUnread, 7); XCTAssertEqual(session.noticeUnread, 2)
    }
    func testInterruptedSendIsNotAutomaticallyRepeatedWhenReturningToTheRoom() async throws {
        var sends = 0
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1; Thread.sleep(forTimeInterval: 0.1)
                return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); store.enqueue(content: "可能已送达")
        try await waitUntil { sends == 1 }
        store.suspend(); await store.activate()
        XCTAssertEqual(sends, 1); XCTAssertEqual(store.pending.first?.deliveryUncertain, true)
        XCTAssertNotNil(store.pending.first?.failure); XCTAssertFalse(store.sending); store.suspend()
    }
    func testRestoredUncertainAndLegacyMessagesWaitForInspection() async throws {
        var sends = 0
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") { sends += 1 }
            return (200, .object(["messages": .array([])]))
        }
        let legacy = Data("[{\"id\":\"old\",\"content\":\"hello\",\"kind\":\"text\",\"failure\":\"未收到发送确认，请重试\"}]".utf8)
        defaults.set(legacy, forKey: "nonto.native.outbox.\(userID).chat.single.55")
        await store.activate()
        XCTAssertEqual(sends, 0); XCTAssertEqual(store.pending.first?.deliveryUncertain, true)
        store.suspend()
        let interrupted = PendingMessage(content: "interrupted", deliveryUncertain: true)
        defaults.set(try JSONEncoder().encode([interrupted]), forKey: "nonto.native.outbox.\(userID).chat.single.55")
        let restored = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") { sends += 1 }
            return (200, .object(["messages": .array([])]))
        }
        await restored.activate()
        XCTAssertEqual(sends, 0); XCTAssertNotNil(restored.pending.first?.failure)
        XCTAssertEqual(restored.pending.first?.deliveryUncertain, true); restored.suspend()
    }
    func testRestoredNeverAttemptedMessageStillSendsNormally() async throws {
        var sends = 0
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1; return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        let unsent = PendingMessage(content: "尚未发送")
        defaults.set(try JSONEncoder().encode([unsent]), forKey: "nonto.native.outbox.\(userID).chat.single.55")
        await store.activate(); try await waitUntil { !store.sending }
        XCTAssertEqual(sends, 1); XCTAssertTrue(store.pending.isEmpty); store.suspend()
    }
    func testClearlyUnsentOfflineMessagesResumeInOrderAfterSuccessfulSync() async throws {
        var attempts: [JSON] = []
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                attempts.append(try self.body(request))
                if attempts.count == 1 { throw URLError(.notConnectedToInternet) }
                return (200, .object(["data": self.message(200 + attempts.count, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate()
        store.enqueue(content: "第一条"); store.enqueue(content: "第二条")
        try await waitUntil { !store.sending }
        XCTAssertEqual(attempts.count, 1); XCTAssertEqual(store.pending.first?.retryWhenOnline, true)
        XCTAssertEqual(store.pending.first?.deliveryUncertain, false)
        let firstID = store.pending.first?.id
        await store.load()
        try await waitUntil { store.pending.isEmpty && !store.sending }
        XCTAssertEqual(attempts.map { $0["content"].string }, ["第一条", "第一条", "第二条"])
        XCTAssertEqual(attempts.prefix(2).map { $0["request_id"].string }, [firstID!, firstID!])
        store.suspend()
    }
    func testTimeoutIsNeverAutomaticallyRetriedAfterSuccessfulSync() async throws {
        var sends = 0
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sends += 1; throw URLError(.timedOut)
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); store.enqueue(content: "可能已送达")
        try await waitUntil { !store.sending }
        await store.load(); await store.load()
        XCTAssertEqual(sends, 1); XCTAssertEqual(store.pending.first?.deliveryUncertain, true)
        XCTAssertEqual(store.pending.first?.retryWhenOnline, false); store.suspend()
    }
    func testOfflineRetryIntentSurvivesRestoreWithoutChangingRequestID() async throws {
        let item = PendingMessage(id: "offline-stable", content: "离线草稿", failure: "离线", retryWhenOnline: true)
        defaults.set(try JSONEncoder().encode([item]), forKey: "nonto.native.outbox.\(userID).chat.single.55")
        var sentID = ""
        let store = try room { request in
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/messages") {
                sentID = try self.body(request)["request_id"].string
                return (200, .object(["data": self.message(201, sender: self.userID)]))
            }
            return (200, .object(["messages": .array([])]))
        }
        await store.activate(); try await waitUntil { !store.sending }
        XCTAssertEqual(sentID, item.id); XCTAssertTrue(store.pending.isEmpty); store.suspend()
    }
    func testRecallRedactsReferencesEvenWhenTheOriginalIsOutsideLoadedHistory() async throws {
        let reply = message(101).merging(.object(["quote_message_id": .id(1), "quote_preview": .text("不应再次出现的原文")]))
        let store = try room { request in
            if request.url!.path.hasSuffix("/around") {
                return (200, .object(["messages": .array([self.message(1), reply])]))
            }
            return (200, .object(["messages": .array([reply])]))
        }
        await store.activate()
        store.receive(.object(["event": .text("message_recalled"), "data": .object([
            "conversation_id": .id(55), "message_id": .id(1)])]))
        XCTAssertEqual(store.messages.first?.raw["quote_preview"].string, "消息已撤回")
        await store.load()
        XCTAssertEqual(store.messages.first?.raw["quote_preview"].string, "消息已撤回")
        let context = try await store.quoteContext(1)
        XCTAssertTrue(context.first!.recalled); XCTAssertEqual(context.first?.content, "")
        XCTAssertEqual(context.last?.raw["quote_preview"].string, "消息已撤回")
        XCTAssertEqual(store.messages.map(\.id), [101]); store.suspend()
    }
    func testQuoteContextUsesBothExistingRoutesWithoutMutatingTimelineOrReadPosition() async throws {
        for community in [false, true] {
            let conversation = Conversation(.object(["id": .id(55), "type": .text(community ? "community" : "direct"),
                                                      "community_id": community ? .id(33) : .null]))
            var contextRequests = 0
            let store = try room(conversation: conversation) { request in
                if request.url!.path.hasSuffix("/around") {
                    contextRequests += 1
                    XCTAssertEqual(request.url!.path, community ? "/api/communities/33/chat/messages/around" : "/api/chat/conversations/55/messages/around")
                    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                    XCTAssertEqual(query?.first { $0.name == "target_id" }?.value, "1")
                    return (200, .object(["messages": .array([self.message(1), self.message(2)])]))
                }
                return (200, .object(["messages": .array([self.message(100)])]))
            }
            await store.activate(); store.reachedBottom(false)
            let before = store.scrollRequest
            let context = try await store.quoteContext(1)
            XCTAssertEqual(context.map(\.id), [1, 2]); XCTAssertEqual(contextRequests, 1)
            XCTAssertEqual(store.messages.map(\.id), [100]); XCTAssertFalse(store.nearBottom)
            XCTAssertEqual(store.scrollRequest, before); store.suspend()
        }
    }
    func testUnavailableQuoteDoesNotReplaceTheRoomWithAnUnrelatedContext() async throws {
        let store = try room { request in
            (200, .object(["messages": .array([self.message(100)])]))
        }
        await store.activate()
        do { _ = try await store.quoteContext(1); XCTFail("A context must contain its requested target") }
        catch { XCTAssertEqual((error as? APIError)?.status, 404) }
        XCTAssertEqual(store.messages.map(\.id), [100]); XCTAssertNil(store.error); store.suspend()
    }
    func testHistoryAutoloadRequiresUserScrollingNearTheTopOfLongContent() {
        let top = ChatViewportMetrics(offset: -40, contentHeight: 2000, visibleHeight: 700, topInset: 40, bottomInset: 0)
        XCTAssertTrue(top.shouldLoadHistory(userScrolling: true))
        XCTAssertFalse(top.shouldLoadHistory(userScrolling: false), "Initial bottom layout must not trigger a history fetch")
        let bottom = ChatViewportMetrics(offset: 1300, contentHeight: 2000, visibleHeight: 700, topInset: 40, bottomInset: 0)
        XCTAssertFalse(bottom.shouldLoadHistory(userScrolling: true))
        let short = ChatViewportMetrics(offset: 0, contentHeight: 200, visibleHeight: 700, topInset: 0, bottomInset: 0)
        XCTAssertFalse(short.shouldLoadHistory(userScrolling: true))
    }
    func testExplicitHistoryCursorContinuesEvenWhenAVisiblePageIsShort() async throws {
        let store = try room { request in
            if request.httpMethod == "POST" { return (200, .null) }
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            return (200, .object(["messages": .array([self.message(page == "2" ? 1 : 100)]), "has_more": .bool(page != "2")]))
        }
        await store.activate(); XCTAssertTrue(store.more)
        store.reachedBottom(false); await store.load(older: true)
        XCTAssertEqual(store.messages.map(\.id), [1, 100]); XCTAssertFalse(store.more)
        store.suspend()
    }
    func testStaleWirePreviewCannotRestoreRecalledContentOrAlternateMediaFields() {
        let original = ChatMessage(message(1).merging(.object(["is_recalled": .bool(true), "text": .text("旧正文"),
            "file_url": .text("https://example.test/private.jpg")])))
        let reply = ChatMessage(message(2).merging(.object(["quote_message_id": .id(1), "quote_preview": .text("旧正文")])))
        let merged = Records.messages([original], [reply])
        XCTAssertEqual(merged[0].content, ""); XCTAssertEqual(merged[0].media, "")
        XCTAssertEqual(merged[1].raw["quote_preview"].string, "消息已撤回")
    }
}
