import Foundation

protocol Record: Identifiable, Codable, Equatable where ID == Int { var raw: JSON { get set }; init(_ raw: JSON) }
extension Record { var id: Int { raw["id"].int } }

struct Person: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var username: String { raw["username"].string }
    var name: String { let n = raw["display_name"].string; return n.isEmpty ? username : n }
    var bio: String { raw["bio"].string }
    var avatar: String { raw["avatar_url"].string }
    var cover: String { raw["cover_photo_url"].string }
    // Public email is opt-in; never infer permission from the presence of email.
    var publicEmail: String? { raw["show_email"] == .bool(true) ? raw["email"].string : nil }
    var verifiedLabels: [String] {
        Array(raw["verified_role_labels"].array.prefix(raw["verified_roles"].array.count)).map(\.string)
    }
}
struct Post: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var userID: Int { raw["user_id"].int > 0 ? raw["user_id"].int : author.id }
    var author: Person { Person(raw["author"].or(raw["user"])) }
    var content: String { raw["content"].string }
    var images: [String] {
        let value = raw["images"].or(raw["image_urls"])
        if case .string(let s) = value, let d = s.data(using: .utf8), let j = try? JSON.decode(d) { return j.array.map(\.string) }
        return value.array.map(\.string)
    }
    var video: String { raw["video_url"].string }
    var liked: Bool { raw["is_liked"].bool }
    var likes: Int { raw["like_count"].int }
    var comments: Int { raw["comment_count"].int }
    var date: Date? { ServerDate.parse(raw["created_at"]) }
    var visibilityForEdit: String {
        if raw["visibility"].isNull { return raw["is_public"] == .bool(false) ? "friends" : "public" }
        return raw["visibility"].string == "public" ? "public" : "friends"
    }
    var quoted: Post? {
        let q = raw["quoted_post"].or(raw["quote_post"])
        return q.isNull || q["unavailable"].bool || q["id"].int <= 0 ? nil : Post(q)
    }
}
struct Comment: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var author: Person { Person(raw["author"].or(raw["user"])) }
    var content: String { raw["content"].string }
    var replies: [Comment] { raw["replies"].array.map(Comment.init) }
}
struct ChatMessage: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var senderID: Int { raw["sender_id"].or(raw["user_id"]).int }
    var content: String { raw["content"].or(raw["text"]).string }
    var kind: String { raw["message_type"].or(raw["type"]).string }
    var media: String { raw["media_url"].or(raw["file_url"]).string }
    var recalled: Bool { raw["is_recalled"].bool || raw["status"].string == "recalled" }
    var date: Date? { ServerDate.parse(raw["created_at"].or(raw["sent_at"]).or(raw["timestamp"])) }
}
struct Conversation: Record {
    var id: Int { raw["conversation_id"].int > 0 ? raw["conversation_id"].int : raw["id"].int }
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var isCommunity: Bool { raw["type"].string == "community" }
    var communityID: Int? { raw["community_id"].isNull ? nil : raw["community_id"].int }
    var other: Person { Person(raw["other_user"]) }
    var name: String { isCommunity ? raw["community_name"].string : other.name }
    var avatar: String { isCommunity ? raw["community_avatar"].string : other.avatar }
    var unread: Int { raw["unread_count"].int }
    var last: ChatMessage { ChatMessage(raw["last_message"]) }
}
struct Community: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var name: String { raw["name"].string }
    var avatar: String { raw["avatar_url"].string }
    var description: String { raw["description"].string }
    var isMember: Bool { raw["my_status"].string == "active" }
    var isManager: Bool { ["owner", "admin"].contains(raw["my_role"].string) }
}
struct Notice: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var sender: Person { Person(raw["sender"]) }
    var title: String { raw["title"].string }
    var content: String { raw["content"].string }
    var isRead: Bool { raw["is_read"].bool }
}
struct Topic: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw }
    var name: String { raw["name"].string }
}

enum Records {
    static func unique<T: Record>(_ items: [T]) -> [T] {
        var result: [T] = [], positions: [Int: Int] = [:]
        for item in items where item.id > 0 {
            if let index = positions[item.id] { result[index] = item }
            else { positions[item.id] = result.count; result.append(item) }
        }
        return result
    }
    static func messages(_ old: [ChatMessage], _ new: [ChatMessage]) -> [ChatMessage] {
        var items = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for m in new where m.id > 0 { items[m.id] = m }
        // Parse each wire date once; parsing inside the comparator creates formatters O(n log n) times.
        var dated: [(message: ChatMessage, date: Date)] = items.values.map { message in
            (message: message, date: message.date ?? Date.distantPast)
        }
        dated.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.message.id < rhs.message.id }
            return lhs.date < rhs.date
        }
        return dated.map { $0.message }
    }
}
