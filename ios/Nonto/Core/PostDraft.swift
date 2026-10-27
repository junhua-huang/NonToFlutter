import Foundation

enum ComposerReferenceKind: String, Identifiable {
    case mention, topic
    var id: String { rawValue }
    var marker: String { self == .mention ? "@" : "#" }
    var title: String { self == .mention ? "艾特好友" : "引用话题" }
}

enum ComposerReferenceInsertion {
    struct Result { let text: String; let caretUTF16: Int }
    private static func characterRange(_ selection: NSRange?, in text: String) -> Range<String.Index>? {
        let count = text.utf16.count
        guard let selection, selection.location >= 0, selection.length >= 0,
              selection.location <= count, selection.length <= count - selection.location else { return nil }
        let end = selection.location + selection.length
        var offset = 0, index = text.startIndex
        var lower: String.Index?, upper: String.Index?
        // Foundation's Range(NSRange, in:) can accept the middle of a surrogate pair.
        // Build endpoints from this buffer's actual Character indices instead.
        while true {
            if offset == selection.location { lower = index }
            if offset == end { upper = index }
            if offset >= end || index == text.endIndex { break }
            offset += String(text[index]).utf16.count
            index = text.index(after: index)
        }
        guard let lower, let upper else { return nil }
        return lower..<upper
    }
    static func safeSelection(_ selection: NSRange?, in text: String) -> NSRange {
        guard let selection, characterRange(selection, in: text) != nil else {
            return NSRange(location: text.utf16.count, length: 0)
        }
        return selection
    }
    /// Convert bounded offsets against this exact buffer; never keep String.Index across edits.
    static func insert(_ value: String, kind: ComposerReferenceKind, into text: String, selection: NSRange?) -> Result {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Result(text: text, caretUTF16: text.utf16.count) }
        var range = characterRange(selection, in: text) ?? text.endIndex..<text.endIndex
        if range.lowerBound > text.startIndex {
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

struct PostDraft: Codable, Equatable, Sendable {
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
        if defaults.bool(forKey: key + ".discarded") { return PostDraft(visibility: defaultVisibility) }
        if let data = defaults.data(forKey: key + ".v2"), let saved = try? JSONDecoder().decode(PostDraft.self, from: data) {
            return PostDraft(text: saved.text, visibility: saved.visibility, role: saved.role)
        }
        return PostDraft(text: defaults.string(forKey: key) ?? "", visibility: defaultVisibility)
    }
    func save(_ draft: PostDraft, userID: Int, communityID: Int = 0, quoteID: Int = 0) {
        guard userID > 0, let data = try? JSONEncoder().encode(draft) else { return }
        let key = key(userID, communityID, quoteID)
        defaults.removeObject(forKey: key + ".discarded")
        defaults.set(data, forKey: key + ".v2"); defaults.removeObject(forKey: key)
    }
    func remove(userID: Int, communityID: Int = 0, quoteID: Int = 0) {
        guard userID > 0 else { return }
        let key = key(userID, communityID, quoteID)
        defaults.set(true, forKey: key + ".discarded")
        defaults.removeObject(forKey: key); defaults.removeObject(forKey: key + ".v2")
    }
    func isDiscarded(userID: Int, communityID: Int, quoteID: Int) -> Bool {
        defaults.bool(forKey: key(userID, communityID, quoteID) + ".discarded")
    }
}
