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
