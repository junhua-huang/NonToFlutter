import Foundation
import Observation

struct PendingMessage: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var content: String
    var kind = "text"
    var media: String? = nil
    var quoteID: Int? = nil
    var failure: String? = nil
    var deliveryUncertain: Bool? = false
    var createdAt: Date? = Date()
    var retryWhenOnline: Bool? = false
}

/// Owns one account's durable outbox and cancels room work when it is no longer visible.
@MainActor @Observable
final class ChatStore {
    private(set) var messages: [ChatMessage] = []
    private(set) var timeline = ChatPresentation()
    private(set) var pending: [PendingMessage] = []
    private(set) var loading = false
    private(set) var loadingOlder = false
    private(set) var sending = false
    private(set) var sendingID: String?
    private(set) var more = true
    var error: String?
    var draft = ""
    private(set) var scrollRequest = 0
    private(set) var unread = 0
    private(set) var nearBottom = true
    private let api: APIClient
    private let socket: RealtimeClient?
    private let accountID: Int
    private let epoch: UUID
    private let conversation: Conversation
    private let defaults: UserDefaults
    private var active = false
    private var restored = false
    private var page = 1
    private var lastOlderIDs: [Int]?
    private(set) var roomID = 0
    private var markedReadThrough: Int?
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var readID = UUID()
    private var loadID = UUID()
    private var sendID = UUID()
    private var lifecycleID = UUID()
    private var localIdentities: [Int: ChatMessageIdentity] = [:]
    private var recalledIDs = Set<Int>()
    private var communityID: Int? { conversation.isCommunity ? conversation.communityID : nil }
    private var cacheKey: String { "chat.\(communityID == nil ? "single" : "community").\(communityID ?? conversation.id)" }
    private var outboxKey: String { "nonto.native.outbox.\(accountID).\(cacheKey)" }
    private var draftKey: String { "nonto.native.chat-draft.\(accountID).\(cacheKey)" }
    private var path: String { if let communityID { return "/communities/\(communityID)/chat" }; return "/chat/conversations/\(conversation.id)/messages" }
    private var valid: Bool { accountID > 0 && api.generation == epoch && api.token != nil }

    init(api: APIClient, conversation: Conversation, userID: Int, socket: RealtimeClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api; self.conversation = conversation; accountID = userID
        self.socket = socket; self.defaults = defaults; epoch = api.generation
        roomID = conversation.id
    }
    func activate() async {
        guard valid, !Task.isCancelled else { return }
        active = true
        if !restored {
            restored = true
            if let cache = LocalCache.read(userID: accountID, key: cacheKey) { setMessages(Records.messages([], cache.array.map(ChatMessage.init))) }
            if let data = defaults.data(forKey: outboxKey), let saved = try? JSONDecoder().decode([PendingMessage].self, from: data) {
                pending = saved
                for index in pending.indices {
                    // Legacy outboxes did not distinguish unsent items from interrupted HTTP writes.
                    if pending[index].deliveryUncertain == true || (pending[index].deliveryUncertain == nil && (index == 0 || pending[index].failure != nil)) {
                        pending[index].deliveryUncertain = true
                        if pending[index].failure == nil { pending[index].failure = "上次发送未收到确认，请先检查最新消息" }
                    }
                }
                persistPending()
            }
            draft = defaults.string(forKey: draftKey) ?? ""
            jumpToLatest()
        }
        joinRoom()
        await load()
        flush()
    }
    func suspend() {
        active = false
        if let id = sendingID, let index = pending.firstIndex(where: { $0.id == id }) {
            pending[index].deliveryUncertain = true
            pending[index].retryWhenOnline = false
            pending[index].failure = "发送已中断，结果待确认，请先检查最新消息"
            persistPending()
        }
        lifecycleID = UUID()
        loadID = UUID(); loadTask?.cancel(); loadTask = nil; loading = false; loadingOlder = false
        sendID = UUID(); sendTask?.cancel(); sendTask = nil; sending = false; sendingID = nil
        readID = UUID(); readTask?.cancel(); readTask = nil
        if valid {
            socket?.room(roomID, joined: false)
            if NativeNotifications.shared.activeConversation == roomID { NativeNotifications.shared.activeConversation = nil }
        }
        saveDraft()
    }
    func scheduleDraftSave() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.saveDraft()
        }
    }
    func saveDraft() {
        draftTask?.cancel(); draftTask = nil
        guard valid else { return }; defaults.set(draft, forKey: draftKey)
    }
    func jumpToLatest() { nearBottom = true; unread = 0; scrollRequest += 1 }
    func reachedBottom(_ value: Bool) {
        if nearBottom != value { nearBottom = value }
        if value && unread > 0 { unread = 0 }
        if value { markReadIfNeeded() }
    }
    func load(older: Bool = false) async {
        guard active, valid, !Task.isCancelled else { return }
        if let task = loadTask {
            let ticket = loadID, wasOlder = loadingOlder, lifecycle = lifecycleID
            await task.value
            guard active, valid, lifecycleID == lifecycle, !Task.isCancelled else { return }
            finishLoad(ticket)
            // A history request must not disappear behind a realtime refresh (or vice versa).
            if older != wasOlder { await load(older: older) }
            return
        }
        guard !older || more else { return }
        let ticket = UUID(); loadID = ticket; loading = true; loadingOlder = older
        let task = Task<Void, Never> { [weak self] in await self?.fetch(older: older, ticket: ticket) }
        loadTask = task
        await task.value
        finishLoad(ticket)
    }
    private func finishLoad(_ ticket: UUID) {
        if loadID == ticket { loadTask = nil; loading = false; loadingOlder = false }
    }
    private func fetch(older: Bool, ticket: UUID) async {
        guard active, valid, loadID == ticket, !Task.isCancelled else { return }
        do {
            var query = ["per_page": "50", "page": String(older ? page + 1 : 1)]
            if communityID != nil {
                query = ["limit": "50"]
                if older, let first = messages.map(\.id).filter({ $0 > 0 }).min() { query["before_id"] = String(first) }
            }
            let json = try await api.request(path, query: query)
            try Task.checkCancellation()
            guard active, valid, loadID == ticket else { return }
            let rows = try PagedResource<ChatMessage>.rows(json, keys: ["messages", "items"]).map(ChatMessage.init)
            let knownMessages = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let known = Set(knownMessages.keys), last = messages.last?.id
            let added = rows.filter { $0.id > 0 && !known.contains($0.id) }
            let changed = rows.contains { row in row.id > 0 && knownMessages[row.id] != row }
            if changed, setMessages(Records.messages(messages, rows)) { persistMessages() }
            let hasMore = json["has_more"] == .bool(true) || (json["has_more"] != .bool(false) && rows.count >= 50)
            if older {
                let ids = rows.map(\.id)
                page += 1
                // Cached history can legitimately overlap multiple server pages.
                more = hasMore && ids != lastOlderIDs && (communityID == nil || !added.isEmpty)
                lastOlderIDs = ids
            } else if page == 1 { more = hasMore }
            if communityID != nil, json["conversation"]["id"].int > 0 {
                updateRoomID(json["conversation"]["id"].int)
            }
            joinRoom()
            let confirmed = Set(rows.filter { $0.senderID == accountID }.compactMap(\.clientRequestID))
            if pending.contains(where: { confirmed.contains($0.id) }) {
                pending.removeAll { confirmed.contains($0.id) }; persistPending()
            }
            resumeSafelyUnsentMessages()
            flush()
            if !older && messages.last?.id != last && !nearBottom && !known.isEmpty {
                unread += added.filter { $0.senderID != accountID }.count
            }
            if !older { markReadIfNeeded() }
            error = nil
        } catch {
            guard active, valid, loadID == ticket, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }
    /// Reading older messages or viewing media must not clear newly arrived messages on the server.
    private func markReadIfNeeded() {
        guard active, valid, nearBottom, roomID > 0, readTask == nil,
              let through = messages.last(where: { $0.senderID != accountID })?.id, through > 0, markedReadThrough != through else { return }
        let ticket = UUID(); readID = ticket
        readTask = Task { [weak self] in
            guard let self else { return }
            defer { if readID == ticket { readTask = nil } }
            while active, valid, nearBottom, readID == ticket, !Task.isCancelled,
                  let through = messages.last(where: { $0.senderID != accountID })?.id, markedReadThrough != through {
                do {
                    _ = try await api.request("/chat/conversations/\(roomID)/mark-read", method: "POST")
                    guard active, valid, readID == ticket, !Task.isCancelled else { return }
                    markedReadThrough = through
                } catch {
                    // A failed receipt must not turn an otherwise successful history fetch into an error.
                    return
                }
            }
        }
    }
    private func updateRoomID(_ value: Int) {
        guard value > 0, roomID != value else { return }
        if active, valid { socket?.room(roomID, joined: false) }
        readID = UUID(); readTask?.cancel(); readTask = nil
        roomID = value; markedReadThrough = nil
    }
    /// Returns true only when a relevant event needs an authoritative HTTP refresh.
    @discardableResult
    func receive(_ payload: JSON) -> Bool {
        guard active, valid else { return false }
        let event = ChatRealtimeEvent(payload)
        if event.name == "resync" { return true }
        guard event.conversationID == roomID || (communityID != nil && event.communityID == communityID) else { return false }
        switch event.name {
        case "new_message":
            let message = event.message
            guard message.id > 0, message.senderID > 0 else { return true }
            if communityID != nil, event.conversationID > 0 { updateRoomID(event.conversationID); joinRoom() }
            let added = !messages.contains { $0.id == message.id }
            if setMessages(Records.messages(messages, [message])) { persistMessages() }
            let confirmations = Set([message.raw["request_id"].string, message.raw["client_msg_id"].string].filter { !$0.isEmpty })
            if message.senderID == accountID, pending.contains(where: { confirmations.contains($0.id) }) {
                pending.removeAll { confirmations.contains($0.id) }; persistPending(); flush()
            }
            if added && !nearBottom && message.senderID != accountID { unread += 1 }
            markReadIfNeeded()
            return false
        case "message_recalled":
            let id = event.data["message_id"].or(event.data["id"]).int
            if id > 0 { applyRecall(id: id) }
            return false
        case "conversation_read": return true
        default: return false
        }
    }
    private func joinRoom() {
        guard active, valid, roomID > 0 else { return }
        socket?.room(roomID, joined: true)
        NativeNotifications.shared.activeConversation = roomID
    }
    @discardableResult
    func enqueueSticker(_ sticker: ChatSticker, quoteID: Int? = nil) -> Bool {
        guard ChatSticker.validURL(sticker.url) else { return false }
        return enqueue(content: ChatSticker.messageContent, kind: "image", media: sticker.url, quoteID: quoteID)
    }
    @discardableResult
    func enqueue(content: String, kind: String = "text", media: String? = nil, quoteID: Int? = nil) -> Bool {
        guard valid else { return false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || media != nil else { return false }
        let item = PendingMessage(content: text, kind: kind, media: media, quoteID: quoteID)
        return appendToOutbox([item])
    }
    /// A photo selection becomes one durable, ordered batch after all uploads succeed.
    @discardableResult
    func enqueueMedia(_ media: [(url: String, kind: String)], caption: String, quoteID: Int? = nil) -> Bool {
        guard valid, (1...9).contains(media.count), media.allSatisfy({ item in
            ["image", "video"].contains(item.kind) && ["http", "https"].contains(URL(string: item.url)?.scheme?.lowercased() ?? "")
        }) else { return false }
        let items = media.enumerated().map { index, item in
            PendingMessage(content: index == 0 ? caption.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                           kind: item.kind, media: item.url, quoteID: index == 0 ? quoteID : nil)
        }
        return appendToOutbox(items)
    }
    private func appendToOutbox(_ items: [PendingMessage]) -> Bool {
        let previous = pending
        pending.append(contentsOf: items)
        guard persistPending() else { pending = previous; updatePresentation(); return false }
        // Size-change anchoring follows new rows at the bottom. Only jump when
        // sending from history; acknowledgements must never request another jump.
        if !nearBottom { jumpToLatest() }
        flush(); return true
    }
    func retry(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failure = nil; pending[index].deliveryUncertain = false
        pending[index].retryWhenOnline = false; persistPending(); flush()
    }
    func remove(_ id: String) {
        guard id != sendingID else { return }
        pending.removeAll { $0.id == id }; persistPending(); flush()
    }
    func flush() {
        guard active, valid, sendTask == nil, let first = pending.first, first.failure == nil else { return }
        let ticket = UUID(); sendID = ticket; sending = true
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { if sendID == ticket { sending = false; sendingID = nil; sendTask = nil } }
            while active, valid, !Task.isCancelled, sendID == ticket,
                  let item = pending.first {
                guard item.failure == nil else { break }
                sendingID = item.id
                // Persist before the request: termination after the server writes must not cause an automatic resend.
                if let index = pending.firstIndex(where: { $0.id == item.id }) {
                    pending[index].deliveryUncertain = true; pending[index].retryWhenOnline = false; persistPending()
                }
                do {
                    var body: [String: JSON] = ["content": .text(item.content), "message_type": .text(item.kind)]
                    body[communityID == nil ? "request_id" : "client_msg_id"] = .text(item.id)
                    if let media = item.media { body["media_url"] = .text(media) }
                    if let quoteID = item.quoteID { body["quote_message_id"] = .id(quoteID) }
                    let json = try await api.request(communityID == nil ? path : path + "/messages", method: "POST", body: .object(body))
                    try Task.checkCancellation()
                    guard active, valid, sendID == ticket else { return }
                    // Do not silently discard an outbox entry on an incomplete success response.
                    guard let message = ChatMessage.confirmation(json) else { throw APIError(status: 0, message: "未收到发送确认，请先检查最新消息") }
                    localIdentities[message.id] = ChatMessageIdentity(requestID: item.id, createdAt: item.createdAt)
                    if setMessages(Records.messages(messages, [message])) { persistMessages() }
                    pending.removeAll { $0.id == item.id }; persistPending()
                } catch {
                    guard active, valid, sendID == ticket, !Task.isCancelled else { return }
                    // A socket acknowledgement may have already confirmed this item while HTTP was in flight.
                    guard let index = pending.firstIndex(where: { $0.id == item.id }) else { continue }
                    pending[index].failure = error.localizedDescription
                    pending[index].deliveryUncertain = ChatDeliveryFailure.isUncertain(error)
                    pending[index].retryWhenOnline = ChatDeliveryFailure.canRetryWhenOnline(error)
                    persistPending()
                    // Keep delivery order when a message fails; retry resumes the queue.
                    break
                }
            }
        }
    }
    private func resumeSafelyUnsentMessages() {
        // Called only after an authenticated history request succeeds. Socket
        // reconnects alone do not prove the HTTP send route is reachable.
        var changed = false
        for index in pending.indices where pending[index].retryWhenOnline == true && pending[index].deliveryUncertain != true {
            pending[index].failure = nil; pending[index].retryWhenOnline = false; changed = true
        }
        if changed { persistPending() }
    }
    @discardableResult private func setMessages(_ incoming: [ChatMessage]) -> Bool {
        let value = ChatMessageReferences.redactingRecalls(incoming, known: recalledIDs)
        for message in value where message.senderID == accountID {
            if let requestID = message.clientRequestID, let item = pending.first(where: { $0.id == requestID }) {
                localIdentities[message.id] = ChatMessageIdentity(requestID: item.id, createdAt: item.createdAt)
            }
        }
        guard messages != value else { return false }
        messages = value
        updatePresentation(serverMessagesChanged: true)
        return true
    }
    private func updatePresentation(serverMessagesChanged: Bool = false) {
        timeline = ChatPresentation(messages: messages, userID: accountID, pending: pending,
                                    localIdentities: localIdentities, preparedRows: serverMessagesChanged ? nil : timeline.rows)
    }
    private func persistMessages() { LocalCache.write(.array(Array(messages.suffix(500)).map(\.raw)), userID: accountID, key: cacheKey) }
    @discardableResult private func persistPending() -> Bool {
        defer { updatePresentation() }
        guard valid, let data = try? JSONEncoder().encode(pending) else { return false }
        defaults.set(data, forKey: outboxKey); return true
    }
    func recall(_ message: ChatMessage) async {
        guard active, valid, message.senderID == accountID, !message.recalled else { return }
        do {
            if let communityID {
                _ = try await api.request("/communities/\(communityID)/chat/messages/\(message.id)", method: "DELETE")
            } else {
                _ = try await api.request("/chat/messages/\(message.id)/recall", method: "POST")
            }
            guard active, valid, !Task.isCancelled else { return }
            applyRecall(id: message.id)
            await load()
        }
        catch { if active && valid { self.error = error.localizedDescription } }
    }
    private func applyRecall(id: Int) {
        recalledIDs.insert(id)
        if setMessages(messages) { persistMessages() }
    }
    func quoteContext(_ targetID: Int) async throws -> [ChatMessage] {
        guard active, valid, targetID > 0 else { throw APIError(status: 404, message: "原消息已不可用") }
        let contextPath = communityID == nil ? path + "/around" : path + "/messages/around"
        let result = try await api.request(contextPath, query: ["target_id": String(targetID), "before": "10", "after": "10"])
        try Task.checkCancellation()
        guard active, valid else { throw CancellationError() }
        let context = Records.messages([], try PagedResource<ChatMessage>.rows(result, keys: ["messages", "items"]).map(ChatMessage.init))
        guard context.contains(where: { $0.id == targetID }) else { throw APIError(status: 404, message: "原消息已删除或暂时无法查看") }
        // A context window must not be merged into the main paginated timeline:
        // doing so would conceal an unloaded gap and move the user's viewport.
        return ChatMessageReferences.redactingRecalls(context, known: recalledIDs)
    }
}

@MainActor enum ConversationLookup {
    static func find(_ id: Int, api: APIClient) async throws -> Conversation {
        guard id > 0 else { throw APIError(status: 404, message: "无效会话") }
        for page in 1...20 {
            try Task.checkCancellation()
            let json = try await api.request("/chat/sessions", query: ["page": String(page), "per_page": "50"])
            let rows = try PagedResource<Conversation>.rows(json, keys: ["sessions", "conversations", "items"]).map(Conversation.init)
            if let value = rows.first(where: { $0.id == id }) { return value }
            if json["has_more"] == .bool(false) || rows.count < 50 { break }
        }
        throw APIError(status: 404, message: "会话已不可访问")
    }
}
