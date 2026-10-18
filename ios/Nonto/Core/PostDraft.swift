import Foundation

struct PostDraft: Codable, Equatable {
    var text: String
    var visibility: String
    var role: String
    init(text: String = "", visibility: String = "public", role: String = "") {
        self.text = text; self.visibility = visibility == "public" ? "public" : "friends"; self.role = role
    }
}

/// Persists the audience alongside the text so restoring a draft never widens it.
struct PostDraftStore {
    var defaults: UserDefaults = .standard
    private func key(_ userID: Int, _ communityID: Int, _ quoteID: Int) -> String {
        "nonto.native.draft.\(userID).\(communityID).\(quoteID)"
    }
    func read(userID: Int, communityID: Int = 0, quoteID: Int = 0, defaultVisibility: String) -> PostDraft {
        guard userID > 0 else { return PostDraft(visibility: defaultVisibility) }
        let key = key(userID, communityID, quoteID)
        if let data = defaults.data(forKey: key + ".v2"), let saved = try? JSONDecoder().decode(PostDraft.self, from: data) {
            return PostDraft(text: saved.text, visibility: saved.visibility, role: saved.role)
        }
        return PostDraft(text: defaults.string(forKey: key) ?? "", visibility: defaultVisibility)
    }
    func save(_ draft: PostDraft, userID: Int, communityID: Int = 0, quoteID: Int = 0) {
        guard userID > 0, let data = try? JSONEncoder().encode(draft) else { return }
        let key = key(userID, communityID, quoteID)
        defaults.set(data, forKey: key + ".v2"); defaults.removeObject(forKey: key)
    }
    func remove(userID: Int, communityID: Int = 0, quoteID: Int = 0) {
        guard userID > 0 else { return }
        let key = key(userID, communityID, quoteID)
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: key + ".v2")
    }
}
