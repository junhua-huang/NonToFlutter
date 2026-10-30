import Foundation
import Observation

struct CommentThread: Identifiable {
    var root: Comment
    var replies: [Comment]
    var page: Int
    var hasMore: Bool
    var expanded = false
    var id: Int { root.id }
    init(_ root: Comment) {
        self.root = root
        replies = Records.unique(root.replies)
        page = max(1, root.raw["replies_page"].int)
        hasMore = root.raw["replies_has_more"].isNull
            ? root.raw["reply_count"].int > replies.count : root.raw["replies_has_more"].bool
    }
    var visibleReplies: [Comment] { expanded ? replies : Array(replies.prefix(2)) }
}

@MainActor @Observable final class CommentsStore {
    private(set) var threads: [CommentThread] = []
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var hasMore = true
    private(set) var page = 0
    private(set) var loadError: String?
    private(set) var sending = false
    private(set) var busyIDs: Set<Int> = []
    private(set) var loadingReplies: Set<Int> = []
    private(set) var replyErrors: [Int: String] = [:]
    private(set) var commentCount: Int?
    private(set) var scrollTarget: Int?
    var sendError: String?
    var actionError: String?
    private(set) var actionErrors: [Int: String] = [:]
    var notice: String?
    var text = "" { didSet { scheduleDraft() } }
    var reply: Comment? { didSet { scheduleDraft() } }
    let postID: Int
    let userID: Int
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let accountEpoch: UUID
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let draftKey: String
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var deletedIDs: Set<Int> = []
    @ObservationIgnored private var sentReplies: [Int: Comment] = [:]

    init(api: APIClient, postID: Int, userID: Int, defaults: UserDefaults = .standard) {
        self.api = api; self.postID = postID; self.userID = userID
        accountEpoch = api.generation; self.defaults = defaults
        draftKey = "nonto.native.comment-draft.\(userID).\(postID)"
        if userID > 0, let data = defaults.data(forKey: draftKey), let draft = try? JSON.decode(data) {
            text = draft["text"].string
            if draft["reply"]["id"].int > 0 { reply = Comment(draft["reply"]) }
        }
    }
    private var current: Bool { api.generation == accountEpoch }
    var canSend: Bool { !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func flushDraft() {
        draftTask?.cancel(); draftTask = nil
        guard current, userID > 0 else { return }
        if text.isEmpty && reply == nil { defaults.removeObject(forKey: draftKey); return }
        // Persist only the reply address and preview needed to restore this composer.
        var target: JSON = .null
        if let reply {
            target = .object(["id": .id(reply.id), "parent_id": reply.parentID.map(JSON.id) ?? .null,
                "user_id": .id(reply.userID), "content": .text(String(reply.content.prefix(120))),
                "author": .object(["id": .id(reply.author.id), "username": .text(reply.author.username),
                                    "display_name": .text(reply.author.name)])])
        }
        if let data = try? JSON.object(["text": .text(text), "reply": target]).encoded() { defaults.set(data, forKey: draftKey) }
    }
    private func scheduleDraft() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flushDraft()
        }
    }

    func load(reset: Bool = false) async {
        guard current, !loading, reset || hasMore else { return }
        loading = true; loadError = nil
        let ticket = revision, next = reset ? 1 : page + 1
        do {
            let json = try await api.request("/posts/\(postID)/comments", query: ["page": String(next), "per_page": "20"])
            guard current else { loading = false; return }
            // A response started before a local mutation must not resurrect a deletion
            // or overwrite a confirmed like/reply. Retry the same page, keeping rows visible.
            if ticket != revision { loading = false; await load(reset: reset); return }
            let rows = try PagedResource<Comment>.rows(json, keys: ["comments", "items"])
            let incoming = Records.unique(rows.map(Comment.init)).filter { !deletedIDs.contains($0.id) }
            guard rows.isEmpty || !incoming.isEmpty || rows.allSatisfy({ deletedIDs.contains($0["id"].int) }) else {
                throw APIError(status: 502, message: "评论数据不完整，请重试")
            }
            let old = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            let merged = incoming.map { root -> CommentThread in
                var thread = CommentThread(preservingBusyLike(root))
                thread.replies = thread.replies.map(preservingBusyLike)
                if let previous = old[root.id] {
                    thread.expanded = previous.expanded
                    if previous.page > 1 {
                        thread.replies = merge(thread.replies, previous.replies, preferIncoming: false)
                        thread.page = previous.page; thread.hasMore = previous.hasMore
                    }
                }
                thread.replies = merge(thread.replies, sentReplies.values.filter { $0.parentID == root.id }.sorted { $0.id < $1.id }, preferIncoming: false)
                thread.replies.removeAll { deletedIDs.contains($0.id) }
                return thread
            }
            let known = Set(threads.map(\.id))
            if reset { threads = merged }
            else {
                for thread in merged {
                    if let index = threads.firstIndex(where: { $0.id == thread.id }) { threads[index] = thread }
                    else { threads.append(thread) }
                }
            }
            page = next; loaded = true
            if !json["has_more"].isNull { hasMore = json["has_more"].bool }
            else if !json["total"].isNull { hasMore = next * 20 < json["total"].int }
            else { hasMore = rows.count >= 20 }
            if rows.isEmpty || (!reset && !incoming.contains(where: { !known.contains($0.id) })) { hasMore = false }
        } catch { if current { loadError = error.localizedDescription } }
        loading = false
    }

    func expandReplies(_ rootID: Int) async {
        guard current, let index = threads.firstIndex(where: { $0.id == rootID }), !loadingReplies.contains(rootID) else { return }
        if !threads[index].expanded {
            threads[index].expanded = true
            if threads[index].replies.count > 2 { return }
        }
        guard threads[index].hasMore else { return }
        loadingReplies.insert(rootID); replyErrors[rootID] = nil
        defer { loadingReplies.remove(rootID) }
        let ticket = revision, next = threads[index].page + 1
        do {
            let json = try await api.request("/posts/\(postID)/comments", query: ["parent_id": String(rootID), "page": String(next), "per_page": "10"])
            guard current, let index = threads.firstIndex(where: { $0.id == rootID }) else { return }
            if ticket != revision { return } // Keep the page available for a clean retry.
            let rows = try PagedResource<Comment>.rows(json, keys: ["comments", "items"])
            let replies = Records.unique(rows.map(Comment.init)).filter { !deletedIDs.contains($0.id) }
            threads[index].replies = merge(threads[index].replies, replies.map(preservingBusyLike))
            threads[index].page = next
            threads[index].hasMore = !rows.isEmpty && (json["has_more"].isNull ? rows.count >= 10 : json["has_more"].bool)
        } catch { if current { replyErrors[rootID] = error.localizedDescription } }
    }
    func collapseReplies(_ rootID: Int) {
        if let index = threads.firstIndex(where: { $0.id == rootID }) { threads[index].expanded = false }
    }

    func send() async {
        guard current, canSend else { return }
        let submittedText = text, target = reply
        sending = true; sendError = nil; notice = nil
        defer { sending = false }
        do {
            var body: [String: JSON] = ["content": .text(submittedText.trimmingCharacters(in: .whitespacesAndNewlines))]
            if let target {
                body["parent_id"] = .id(target.rootID)
                if target.userID > 0 { body["reply_to_user_id"] = .id(target.userID) }
            }
            let result = try await api.request("/posts/\(postID)/comments", method: "POST", body: .object(body))
            guard current else { return }
            if text == submittedText && reply?.id == target?.id { text = ""; reply = nil; flushDraft() }
            var confirmed = Comment(result["comment"].or(result["data"]))
            if confirmed.parentID == nil, let target { confirmed.raw["parent_id"] = .id(target.rootID) }
            if confirmed.id > 0 {
                revision += 1
                if let parent = confirmed.parentID ?? target?.rootID,
                   let index = threads.firstIndex(where: { $0.id == parent }) {
                    threads[index].replies = merge(threads[index].replies, [confirmed])
                    sentReplies[confirmed.id] = confirmed
                    threads[index].expanded = true
                    var root = threads[index].root.raw
                    root["reply_count"] = .id(max(root["reply_count"].int + 1, threads[index].replies.count))
                    threads[index].root = Comment(root)
                } else if target == nil {
                    threads.removeAll { $0.id == confirmed.id }; threads.insert(CommentThread(confirmed), at: 0)
                } else if let target {
                    // A restored reply draft may address a thread beyond the first page.
                    // Fetch that thread without presenting a confirmed write as a failure.
                    if let detail = try? await api.request("/comments/\(target.rootID)", query: ["per_page": "10"]), current,
                       detail["comment"]["id"].int > 0 {
                        var root = detail["comment"]
                        root["replies"] = detail["replies"]
                        root["replies_has_more"] = .bool(detail["reply_total"].int > detail["replies"].array.count)
                        var thread = CommentThread(Comment(root))
                        thread.replies = merge(thread.replies, [confirmed]); thread.expanded = true
                        threads.removeAll { $0.id == thread.id }; threads.insert(thread, at: 0)
                        sentReplies[confirmed.id] = confirmed
                    }
                }
                guard current else { return }
                scrollTarget = confirmed.id
            }
            if !result["comment_count"].isNull { commentCount = max(0, result["comment_count"].int) }
            notice = "已发送"
            // Do not treat a successful write with an older response envelope as a failure
            // that invites duplicate sending. Recover the list separately instead.
            if confirmed.id <= 0 { await load(reset: true) }
        } catch { if current { sendError = error.localizedDescription; flushDraft() } }
    }

    func toggleLike(_ item: Comment) async {
        guard current, !busyIDs.contains(item.id), let before = find(item.id) else { return }
        busyIDs.insert(item.id); actionError = nil; actionErrors[item.id] = nil
        defer { busyIDs.remove(item.id) }
        let liked = !before.liked
        patch(item.id, .object(["is_liked": .bool(liked), "like_count": .id(max(0, before.likes + (liked ? 1 : -1)))]))
        do {
            let result = try await api.request("/comments/\(item.id)/like", method: liked ? "POST" : "DELETE")
            guard current else { return }
            patch(item.id, .object(["is_liked": result["liked"].isNull ? .bool(liked) : result["liked"],
                                   "like_count": result["like_count"].isNull ? .id(max(0, before.likes + (liked ? 1 : -1))) : result["like_count"]]))
        } catch {
            guard current else { return }
            patch(item.id, .object(["is_liked": .bool(before.liked), "like_count": .id(before.likes)]))
            actionError = error.localizedDescription
            actionErrors[item.id] = error.localizedDescription
        }
    }

    func delete(_ item: Comment) async {
        guard current, !busyIDs.contains(item.id) else { return }
        busyIDs.insert(item.id); actionError = nil; actionErrors[item.id] = nil
        defer { busyIDs.remove(item.id) }
        do {
            let result = try await api.request("/comments/\(item.id)", method: "DELETE")
            guard current else { return }
            revision += 1; deletedIDs.insert(item.id)
            sentReplies[item.id] = nil
            threads.removeAll { $0.id == item.id }
            for index in threads.indices {
                let previousCount = threads[index].replies.count
                threads[index].replies.removeAll { $0.id == item.id }
                if threads[index].replies.count < previousCount {
                    var root = threads[index].root.raw
                    root["reply_count"] = .id(max(0, root["reply_count"].int - 1)); threads[index].root = Comment(root)
                }
            }
            if reply?.id == item.id || reply?.rootID == item.id { reply = nil; flushDraft() }
            if !result["comment_count"].isNull { commentCount = max(0, result["comment_count"].int) }
            // The server may retain a removed parent's replies as top-level comments.
            // Refresh this structural deletion instead of claiming those replies were deleted.
            if item.parentID == nil { await load(reset: true) }
        } catch { if current { actionError = error.localizedDescription; actionErrors[item.id] = error.localizedDescription } }
    }

    private func find(_ id: Int) -> Comment? {
        for thread in threads {
            if thread.id == id { return thread.root }
            if let reply = thread.replies.first(where: { $0.id == id }) { return reply }
        }
        return nil
    }
    private func patch(_ id: Int, _ patch: JSON) {
        revision += 1
        if let sent = sentReplies[id] { sentReplies[id] = Comment(sent.raw.merging(patch)) }
        for index in threads.indices {
            if threads[index].id == id { threads[index].root = Comment(threads[index].root.raw.merging(patch)) }
            if let child = threads[index].replies.firstIndex(where: { $0.id == id }) {
                threads[index].replies[child] = Comment(threads[index].replies[child].raw.merging(patch))
            }
        }
    }
    private func preservingBusyLike(_ item: Comment) -> Comment {
        guard busyIDs.contains(item.id), let previous = find(item.id) else { return item }
        return Comment(item.raw.merging(.object(["is_liked": .bool(previous.liked), "like_count": .id(previous.likes)])))
    }
    private func merge(_ existing: [Comment], _ incoming: [Comment], preferIncoming: Bool = true) -> [Comment] {
        var result = existing
        for item in incoming {
            if let index = result.firstIndex(where: { $0.id == item.id }) { if preferIncoming { result[index] = item } }
            else { result.append(item) }
        }
        return result
    }
}

