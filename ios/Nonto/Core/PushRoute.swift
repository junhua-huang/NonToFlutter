import Foundation

struct PushRoute: Identifiable, Equatable {
    enum Destination: Equatable { case conversation(Int), community(Int), post(Int), notification(Int), inbox }
    let id: String
    let payload: JSON
    let recipientID: Int
    let destination: Destination
    init?(_ json: JSON) {
        let recipient = json["recipient_id"].or(json["user_id"]).int
        // Every server notification is explicitly scoped to its recipient.
        guard recipient > 0 else { return nil }
        payload = json
        recipientID = recipient
        let type = json["related_type"].string, related = json["related_id"].int
        if type == "conversation", related > 0 { destination = .conversation(related) }
        else if type == "community", related > 0 { destination = .community(related) }
        else if type == "post", related > 0 { destination = .post(related) }
        else if json["notification_id"].int > 0 { destination = .notification(json["notification_id"].int) }
        else { destination = .inbox }
        id = json["dedupe_key"].string.isEmpty ? UUID().uuidString : json["dedupe_key"].string
    }
    static func decode(_ userInfo: [AnyHashable: Any]) -> JSON? {
        guard JSONSerialization.isValidJSONObject(userInfo), let data = try? JSONSerialization.data(withJSONObject: userInfo) else { return nil }
        return try? JSON.decode(data)
    }
}

/// Shared by socket-local and APNs foreground presentation, bounded to one session.
struct PushDeduplicator {
    private var seen: [String: Date] = [:]
    mutating func accept(_ key: String, now: Date = Date()) -> Bool {
        guard !key.isEmpty else { return true }
        seen = seen.filter { now.timeIntervalSince($0.value) < 300 }
        guard seen[key] == nil else { return false }
        if seen.count >= 256, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen.removeValue(forKey: oldest) }
        seen[key] = now; return true
    }
}
