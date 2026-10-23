import Foundation

enum ChatDeliveryFailure {
    /// Connection establishment failed before a request could reach the server.
    /// Lost responses/timeouts must never opt into automatic retry.
    static func canRetryWhenOnline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }
    /// HTTP gateways can lose the acknowledgement after the server has persisted a message.
    static func isUncertain(_ error: Error) -> Bool {
        if let error = error as? APIError { return error.status == 0 || error.status == 408 || error.status >= 500 }
        if let error = error as? URLError { return [.timedOut, .networkConnectionLost, .badServerResponse, .cannotParseResponse].contains(error.code) }
        return false
    }
}

/// The HTTP and community send routes use different websocket envelopes.
struct ChatRealtimeEvent {
    let name: String
    let data: JSON
    let message: ChatMessage
    let conversationID: Int
    let communityID: Int
    init(_ payload: JSON) {
        name = payload["event"].string
        data = payload["data"].or(payload)
        message = ChatMessage(data["message"].or(data["data"]).or(data))
        conversationID = [data["conversation_id"].int, message.raw["conversation_id"].int, payload["conversation_id"].int].first { $0 > 0 } ?? 0
        communityID = [data["community_id"].int, message.raw["community_id"].int].first { $0 > 0 } ?? 0
    }
    var affectsConversationList: Bool {
        ["new_message", "message_recalled", "conversation_read", "session_list", "resync"].contains(name)
    }
}

/// Keeps conversational runs compact while retaining date and time context.
enum ChatTimeline {
    struct Row: Identifiable, Equatable {
        let message: ChatMessage
        let date: Date?
        let showsTimestamp: Bool
        let startsRun: Bool
        var id: Int { message.id }
    }
    static func rows(_ messages: [ChatMessage], calendar: Calendar = .current, preparedDates: [Date?]? = nil) -> [Row] {
        var previous: ChatMessage?
        var previousDate: Date?
        return messages.enumerated().map { index, message in
            let date: Date?
            if let preparedDates, preparedDates.indices.contains(index) { date = preparedDates[index] }
            else { date = message.date }
            let separator: Bool
            if let date, let earlier = previousDate {
                separator = !calendar.isDate(date, inSameDayAs: earlier) || date.timeIntervalSince(earlier) >= 300
            } else { separator = date != nil }
            let startsRun = previous == nil || separator || previous?.senderID != message.senderID || previous?.recalled == true || message.recalled
            previous = message; previousDate = date
            return Row(message: message, date: date, showsTimestamp: separator, startsRun: startsRun)
        }
    }
}

/// Gallery order follows the visible timeline, excluding recalled/invalid media.
enum ChatMediaTimeline {
    struct Item: Identifiable, Equatable { let id: Int; let url: String }
    static func images(_ messages: [ChatMessage]) -> [Item] {
        messages.filter { !$0.recalled && $0.kind == "image" && ["https", "http"].contains(URL(string: $0.media)?.scheme?.lowercased() ?? "") }
            .map { Item(id: $0.id, url: $0.media) }
    }
}

/// Geometry is kept outside observable view state; pixel updates do not redraw the chat.
struct ChatViewportMetrics: Equatable {
    var offset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    var visibleBottom: CGFloat? = nil
    private var bottom: CGFloat { visibleBottom ?? (offset + visibleHeight - bottomInset) }
    var nearBottom: Bool { contentHeight - bottom < 80 }
    func shouldLoadHistory(userScrolling: Bool) -> Bool {
        userScrolling && offset + topInset < 100 && contentHeight > visibleHeight + 120
    }
    func clamped(_ y: CGFloat) -> CGFloat {
        min(max(-topInset, y), max(-topInset, offset + contentHeight - bottom))
    }
}
@MainActor final class ChatViewportMemory {
    private(set) var metrics: ChatViewportMetrics?
    private var history: ChatViewportMetrics?
    private var historyFinished = false
    private var mediaOffset: CGFloat?
    private(set) var presentingMedia = false
    var userScrolling = false {
        didSet { if userScrolling && historyFinished { history = nil } }
    }
    var preservingHistory: Bool { history != nil }

    func record(_ value: ChatViewportMetrics) -> CGFloat? {
        let previous = metrics
        metrics = value
        guard !presentingMedia, var anchor = history else { return nil }
        if userScrolling, let previous, abs(value.contentHeight - previous.contentHeight) < 1 {
            anchor.offset += value.offset - previous.offset; history = anchor
            return nil
        }
        let target = value.clamped(anchor.offset + value.contentHeight - anchor.contentHeight)
        if historyFinished { history = nil }
        return abs(target - value.offset) > 1 ? target : nil
    }
    func beginHistory() { history = metrics; historyFinished = false }
    func finishHistory(addedRows: Bool) -> CGFloat? {
        historyFinished = true
        guard addedRows, let current = metrics, let anchor = history else { history = nil; return nil }
        // Wait for the new stack's layout if the network finished before SwiftUI measured it.
        guard abs(current.contentHeight - anchor.contentHeight) > 1 else { return nil }
        let target = current.clamped(anchor.offset + current.contentHeight - anchor.contentHeight)
        // Keep the anchor through the next geometry update, which includes the loaded rows.
        return abs(target - current.offset) > 1 ? target : nil
    }
    func beginMedia() { mediaOffset = metrics?.offset; presentingMedia = true; history = nil }
    func endMedia() -> CGFloat? {
        presentingMedia = false
        defer { mediaOffset = nil }
        guard let mediaOffset, let metrics else { return nil }
        return metrics.clamped(mediaOffset)
    }
    func clearPreservation() { history = nil; mediaOffset = nil }
}

extension ChatMessage {
    var clientRequestID: String? {
        [raw["request_id"].string, raw["client_msg_id"].string].first { !$0.isEmpty }
    }
}

struct ChatMessageIdentity {
    let requestID: String
    let createdAt: Date?
}

/// One stable row owns the bubble throughout queued -> sending -> acknowledged.
/// Server messages and the outbox must share a ForEach identity namespace.
struct ChatTimelineEntry: Identifiable, Equatable {
    let id: String
    let row: ChatTimeline.Row
    let pending: PendingMessage?
}

/// Prepared when messages or the outbox change, never while typing or measuring the viewport.
struct ChatPresentation {
    var rows: [ChatTimeline.Row] = []
    var entries: [ChatTimelineEntry] = []
    var gallery: [String] = []
    var galleryIndexes: [Int: Int] = [:]
    var lastOutgoingID: Int?
    init(messages: [ChatMessage] = [], userID: Int = 0, pending: [PendingMessage] = [],
         localIdentities: [Int: ChatMessageIdentity] = [:], preparedRows: [ChatTimeline.Row]? = nil) {
        rows = preparedRows ?? ChatTimeline.rows(messages)
        var visible = messages
        var dates = rows.map(\.date)
        var identities: [String] = []
        var used = Set<String>()
        for (index, message) in messages.enumerated() {
            let local = message.senderID == userID ? localIdentities[message.id] : nil
            let requestID = message.senderID == userID ? (local?.requestID ?? message.clientRequestID) : nil
            let proposed = requestID.map { "local:" + $0 } ?? "server:\(message.id)"
            let id = used.insert(proposed).inserted ? proposed : "server:\(message.id)"
            identities.append(id)
            if let date = local?.createdAt {
                dates[index] = date
            }
        }
        var pendingByID: [String: PendingMessage] = [:]
        for item in pending {
            let id = "local:" + item.id
            guard used.insert(id).inserted else { continue }
            var raw: [String: JSON] = ["id": .id(0), "sender_id": .id(userID), "content": .text(item.content),
                                      "message_type": .text(item.kind), "request_id": .text(item.id)]
            if let media = item.media { raw["media_url"] = .text(media) }
            if let date = item.createdAt { raw["created_at"] = .number(date.timeIntervalSince1970) }
            if let quoteID = item.quoteID, let quote = messages.first(where: { $0.id == quoteID }) {
                raw["quote_message_id"] = .id(quoteID)
                raw["quote_preview"] = .text(ChatQuoteSummary.preview(quote))
            }
            visible.append(ChatMessage(.object(raw))); dates.append(item.createdAt)
            identities.append(id); pendingByID[id] = item
        }
        // Sending-status changes reuse parsed server dates rather than parsing
        // the entire loaded history again on the main actor.
        entries = zip(identities, ChatTimeline.rows(visible, preparedDates: dates)).map { id, row in
            ChatTimelineEntry(id: id, row: row, pending: pendingByID[id])
        }
        let images = ChatMediaTimeline.images(messages)
        gallery = images.map(\.url)
        galleryIndexes = Dictionary(images.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        lastOutgoingID = messages.last(where: { $0.senderID == userID })?.id
    }
}
