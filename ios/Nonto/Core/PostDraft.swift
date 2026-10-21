import Foundation

enum ComposerReferenceKind: String, Identifiable {
    case mention, topic
    var id: String { rawValue }
    var marker: String { self == .mention ? "@" : "#" }
    var title: String { self == .mention ? "艾特好友" : "引用话题" }
}

enum ComposerReferenceInsertion {
    struct Result { let text: String; let caretUTF16: Int }
    /// UTF-16 selections are converted before editing, so emoji and CJK text keep valid boundaries.
    static func insert(_ value: String, kind: ComposerReferenceKind, into text: String, selection: NSRange?) -> Result {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Result(text: text, caretUTF16: text.utf16.count) }
        var range = selection.flatMap { Range($0, in: text) } ?? text.endIndex..<text.endIndex
        if range.isEmpty, range.lowerBound > text.startIndex {
            let before = text.index(before: range.lowerBound)
            if String(text[before]) == kind.marker { range = before..<range.upperBound }
        }
        let before = String(text[..<range.lowerBound]), after = String(text[range.upperBound...])
        let leading = before.last.map { $0.isWhitespace ? "" : " " } ?? ""
        let trailing = after.first?.isWhitespace == true ? "" : " "
        let insertion = leading + kind.marker + name + trailing
        let caret = before.utf16.count + insertion.utf16.count + (after.first == " " && trailing.isEmpty ? 1 : 0)
        return Result(text: before + insertion + after, caretUTF16: caret)
    }
}

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
