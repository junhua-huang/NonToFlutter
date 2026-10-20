import Foundation

/// Keeps conversational runs compact while retaining date and time context.
enum ChatTimeline {
    struct Row: Identifiable {
        let message: ChatMessage
        let showsTimestamp: Bool
        let startsRun: Bool
        var id: Int { message.id }
    }
    static func rows(_ messages: [ChatMessage], calendar: Calendar = .current) -> [Row] {
        var previous: ChatMessage?
        return messages.map { message in
            let separator: Bool
            if let date = message.date, let earlier = previous?.date {
                separator = !calendar.isDate(date, inSameDayAs: earlier) || date.timeIntervalSince(earlier) >= 300
            } else { separator = message.date != nil }
            let startsRun = previous == nil || separator || previous?.senderID != message.senderID || previous?.recalled == true || message.recalled
            previous = message
            return Row(message: message, showsTimestamp: separator, startsRun: startsRun)
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
