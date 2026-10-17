import Foundation
import Combine

struct PendingMessage: Codable, Identifiable {
    var id: String = UUID().uuidString
    var content: String
    var kind = "text"
    var media: String? = nil
    var quoteID: Int? = nil
    var failure: String? = nil
}

/// Owns one account's durable outbox and cancels room work when it is no longer visible.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var pending: [PendingMessage] = []
    @Published private(set) var loading = false
    @Published private(set) var sending = false
    @Published private(set) var more = true
    @Published var error: String?
    @Published var draft = ""
    @Published private(set) var scrollRequest = 0
    @Published private(set) var unread = 0
    var nearBottom = true
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
    private var roomID = 0
    private var markedReadThrough: Int?
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var loadID = UUID()
    private var sendID = UUID()
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
            if let cache = LocalCache.read(userID: accountID, key: cacheKey) { messages = Records.messages([], cache.array.map(ChatMessage.init)) }
            if let data = defaults.data(forKey: outboxKey), let saved = try? JSONDecoder().decode([PendingMessage].self, from: data) { pending = saved }
            draft = defaults.string(forKey: draftKey) ?? ""
            jumpToLatest()
        }
        joinRoom()
        await load()
        flush()
    }
    func suspend() {
        active = false
        loadID = UUID(); loadTask?.cancel(); loadTask = nil; loading = false
        sendID = UUID(); sendTask?.cancel(); sendTask = nil; sending = false
        if valid {
            socket?.room(roomID, joined: false)
            if NativeNotifications.shared.activeConversation == roomID { NativeNotifications.shared.activeConversation = nil }
        }
        saveDraft()
    }
    func saveDraft() { guard valid else { return }; defaults.set(draft, forKey: draftKey) }
    func jumpToLatest() { nearBottom = true; unread = 0; scrollRequest += 1 }
    func reachedBottom(_ value: Bool) { nearBottom = value; if value { unread = 0 } }
    func load(older: Bool = false) async {
        guard active, valid, !Task.isCancelled else { return }
        if let task = loadTask { await task.value; return }
        let ticket = UUID(); loadID = ticket; loading = true
        let task = Task<Void, Never> { [weak self] in await self?.fetch(older: older, ticket: ticket) }
        loadTask = task
        await task.value
        if loadID == ticket { loadTask = nil; loading = false }
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
            let known = Set(messages.map(\.id)), last = messages.last?.id
            let added = rows.filter { $0.id > 0 && !known.contains($0.id) }
            messages = Records.messages(messages, rows)
            if older {
                let ids = rows.map(\.id)
                page += 1
                // Cached history can legitimately overlap multiple server pages.
                more = rows.count >= 50 && ids != lastOlderIDs && (communityID == nil || !added.isEmpty)
                lastOlderIDs = ids
            } else if page == 1 { more = rows.count >= 50 }
            if communityID != nil, json["conversation"]["id"].int > 0 { roomID = json["conversation"]["id"].int }
            joinRoom()
            let confirmed = Set(rows.flatMap { [$0.raw["request_id"].string, $0.raw["client_msg_id"].string] }.filter { !$0.isEmpty })
            pending.removeAll { confirmed.contains($0.id) }; persistPending()
            persistMessages()
            if !older && messages.last?.id != last {
                if nearBottom || known.isEmpty { jumpToLatest() }
                else { unread += added.filter { $0.senderID != accountID }.count }
            }
            let through = messages.last?.id ?? 0
            if roomID > 0, markedReadThrough != through {
                _ = try await api.request("/chat/conversations/\(roomID)/mark-read", method: "POST")
                guard active, valid, loadID == ticket else { return }
                markedReadThrough = through
            }
            error = nil
        } catch {
            guard active, valid, loadID == ticket, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }
    private func joinRoom() {
        guard active, valid, roomID > 0 else { return }
        socket?.room(roomID, joined: true)
        NativeNotifications.shared.activeConversation = roomID
    }
    @discardableResult
    func enqueue(content: String, kind: String = "text", media: String? = nil, quoteID: Int? = nil) -> Bool {
        guard valid else { return false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || media != nil else { return false }
        let item = PendingMessage(content: text, kind: kind, media: media, quoteID: quoteID)
        pending.append(item)
        guard persistPending() else { pending.removeLast(); return false }
        jumpToLatest(); flush(); return true
    }
    func retry(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failure = nil; persistPending(); flush()
    }
    func remove(_ id: String) { pending.removeAll { $0.id == id }; persistPending(); flush() }
    func flush() {
        guard active, valid, sendTask == nil else { return }
        let ticket = UUID(); sendID = ticket; sending = true
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { if sendID == ticket { sending = false; sendTask = nil } }
            while active, valid, !Task.isCancelled, sendID == ticket,
                  let item = pending.first {
                guard item.failure == nil else { break }
                do {
                    var body: [String: JSON] = ["content": .text(item.content), "message_type": .text(item.kind)]
                    body[communityID == nil ? "request_id" : "client_msg_id"] = .text(item.id)
                    if let media = item.media { body["media_url"] = .text(media) }
                    if let quoteID = item.quoteID { body["quote_message_id"] = .id(quoteID) }
                    let json = try await api.request(communityID == nil ? path : path + "/messages", method: "POST", body: .object(body))
                    try Task.checkCancellation()
                    guard active, valid, sendID == ticket else { return }
                    let message = ChatMessage(json["message"].or(json))
                    // Do not silently discard an outbox entry on an incomplete success response.
                    guard message.id > 0 else { throw APIError(status: 0, message: "未收到发送确认，请重试") }
                    messages = Records.messages(messages, [message]); persistMessages()
                    pending.removeAll { $0.id == item.id }; persistPending()
                    if nearBottom { jumpToLatest() }
                } catch {
                    guard active, valid, sendID == ticket, !Task.isCancelled else { return }
                    if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].failure = error.localizedDescription; persistPending() }
                    // Keep delivery order when a message fails; retry resumes the queue.
                    break
                }
            }
        }
    }
    private func persistMessages() { LocalCache.write(.array(Array(messages.suffix(500)).map(\.raw)), userID: accountID, key: cacheKey) }
    @discardableResult private func persistPending() -> Bool {
        guard valid, let data = try? JSONEncoder().encode(pending) else { return false }
        defaults.set(data, forKey: outboxKey); return true
    }
    func recall(_ message: ChatMessage) async {
        guard active, valid, let communityID else { return }
        do { _ = try await api.request("/communities/\(communityID)/chat/messages/\(message.id)", method: "DELETE"); await load() }
        catch { if active && valid { self.error = error.localizedDescription } }
    }
}
