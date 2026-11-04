import Foundation

/// Account-scoped preferences apply to loaded rows, caches and late responses alike.
struct ContentSafety: Equatable {
    var blockedUsers = Set<Int>()
    var hiddenPosts: [Int: JSON] = [:]

    func visible(_ post: Post, depth: Int = 0) -> Post? {
        guard !blockedUsers.contains(post.userID), hiddenPosts[post.id] == nil else { return nil }
        var raw = post.raw
        if let quote = post.quoted {
            if depth < 12, let visible = visible(quote, depth: depth + 1) {
                raw["quoted_post"] = visible.raw
            } else {
                raw["quoted_post"] = .object(["unavailable": .bool(true)])
                raw["quoted_post_unavailable"] = .bool(true)
            }
            // Remove the legacy copy too, including all media and author data.
            raw["quote_post"] = .null
        }
        return Post(raw)
    }
}

extension AppSession {
    func restoreContentSafety(userID: Int) {
        guard safetyAccountID != userID else { return }
        safetyAccountID = userID
        let stored = contentDefaults.data(forKey: "nonto.safety.v1.\(userID)")
            .flatMap { try? JSON.decode($0) } ?? .null
        var value = ContentSafety()
        value.blockedUsers = Set(stored["blocked_users"].array.map(\.int).filter { $0 > 0 })
        for row in stored["hidden_posts"].array where row["id"].int > 0 { value.hiddenPosts[row["id"].int] = row }
        pendingPostHides = stored["pending_hides"].object.reduce(into: [:]) { result, entry in
            if let id = Int(entry.key), id > 0 { result[id] = entry.value.bool }
        }
        contentSafety = value
        contentSafetyError = nil
        safetyRevision += 1
    }

    func saveContentSafety() {
        guard safetyAccountID > 0 else { return }
        let json: JSON = .object([
            "blocked_users": .array(contentSafety.blockedUsers.sorted().map(JSON.id)),
            "hidden_posts": .array(contentSafety.hiddenPosts.values.sorted { $0["id"].int > $1["id"].int }),
            "pending_hides": .object(Dictionary(uniqueKeysWithValues: pendingPostHides.map { (String($0.key), JSON.bool($0.value)) }))
        ])
        if let data = try? json.encoded() { contentDefaults.set(data, forKey: "nonto.safety.v1.\(safetyAccountID)") }
    }

    /// Hiding stays effective offline; a durable outbox retries the account's choice.
    func setPostHidden(_ post: Post, hidden: Bool) async {
        guard let user, post.id > 0 else { return }
        restoreContentSafety(userID: user.id)
        var value = contentSafety
        if hidden {
            value.hiddenPosts[post.id] = .object([
                "id": .id(post.id), "user_id": .id(post.userID),
                "content": .text(String(post.content.prefix(160))),
                "author": .object(["id": .id(post.userID), "username": .text(post.author.username), "display_name": .text(post.author.name)])
            ])
        } else { value.hiddenPosts[post.id] = nil }
        pendingPostHides[post.id] = hidden
        safetyRevision += 1; contentSafety = value; saveContentSafety()
        if !hidden { postRevision += 1 }
        await syncPostHides()
    }

    func syncPostHides() async {
        guard user?.id == safetyAccountID, !safetySyncing, !pendingPostHides.isEmpty else { return }
        let epoch = api.generation, owner = safetyAccountID
        safetySyncing = true
        defer { if epoch == api.generation, owner == safetyAccountID { safetySyncing = false } }
        while let id = pendingPostHides.keys.sorted().first, let hidden = pendingPostHides[id] {
            do {
                _ = try await api.request("/post-hides/\(id)", method: hidden ? "PUT" : "DELETE")
                guard epoch == api.generation, owner == safetyAccountID else { return }
                if pendingPostHides[id] == hidden { pendingPostHides[id] = nil; safetyRevision += 1 }
                saveContentSafety(); contentSafetyError = nil
            } catch {
                guard epoch == api.generation, owner == safetyAccountID else { return }
                contentSafetyError = "帖子屏蔽设置已保存在本机，暂未同步到其他设备。请稍后在屏蔽列表中重试。"
                return
            }
        }
    }

    func refreshContentSafety() async {
        guard let user else { return }
        restoreContentSafety(userID: user.id)
        await syncPostHides()
        guard !safetySyncing, blockingUserIDs.isEmpty else { return }
        let epoch = api.generation, owner = user.id, revision = safetyRevision
        do {
            var blocks = Set<Int>(), page = 1
            while true {
                let result = try await api.request("/blocks/", query: ["page": String(page), "per_page": "100"])
                let rows = try PagedResource<BlockedRecord>.rows(result, keys: ["blocks", "blocked_users", "users"])
                blocks.formUnion(rows.map { BlockedRecord($0).id }.filter { $0 > 0 })
                if rows.count < 100 { break }; page += 1
                guard page <= 1000 else { throw APIError(status: 0, message: "屏蔽列表过长，请重试") }
            }
            guard epoch == api.generation, owner == safetyAccountID, revision == safetyRevision, blockingUserIDs.isEmpty else { return }
            var value = contentSafety; value.blockedUsers = blocks
            contentSafety = value; saveContentSafety()
            var hidden: [Int: JSON] = [:]; page = 1
            while true {
                let result = try await api.request("/post-hides/", query: ["page": String(page), "per_page": "100"])
                let rows = try PagedResource<Post>.rows(result, keys: ["posts", "items"])
                for row in rows where row["id"].int > 0 { hidden[row["id"].int] = row }
                if rows.count < 100 { break }; page += 1
                guard page <= 1000 else { throw APIError(status: 0, message: "屏蔽列表过长，请重试") }
            }
            guard epoch == api.generation, owner == safetyAccountID, revision == safetyRevision else { return }
            for (id, desired) in pendingPostHides {
                if desired { hidden[id] = contentSafety.hiddenPosts[id] }
                else { hidden[id] = nil }
            }
            value = contentSafety; value.hiddenPosts = hidden
            contentSafety = value; saveContentSafety()
            if pendingPostHides.isEmpty { contentSafetyError = nil }
        } catch {
            guard epoch == api.generation, owner == safetyAccountID, revision == safetyRevision else { return }
            contentSafetyError = "暂时无法刷新屏蔽设置，已保留本机设置。可下拉重试。"
        }
    }

    func setUserBlocked(_ id: Int, blocked: Bool, sourcePostID: Int? = nil) async throws {
        guard let user, id > 0, id != user.id, !blockingUserIDs.contains(id) else { return }
        restoreContentSafety(userID: user.id)
        let epoch = api.generation, owner = user.id, previous = contentSafety.blockedUsers.contains(id)
        blockingUserIDs.insert(id); safetyRevision += 1; contentSafetyError = nil
        var value = contentSafety
        if blocked { value.blockedUsers.insert(id) } else { value.blockedUsers.remove(id) }
        contentSafety = value; saveContentSafety()
        defer { if epoch == api.generation { blockingUserIDs.remove(id) } }
        do {
            var body: JSON = .object(["user_id": .id(id)])
            if let sourcePostID { body["post_id"] = .id(sourcePostID) }
            let result = try await api.request(blocked ? "/blocks" : "/blocks/\(id)", method: blocked ? "POST" : "DELETE", body: blocked ? body : nil)
            guard epoch == api.generation, owner == safetyAccountID else { return }
            // Older servers still receive a moderation case through their report API.
            if blocked && !result["moderation_notified"].bool {
                do {
                    _ = try await api.request("/reports/user", method: "POST", body: .object([
                        "user_id": .id(id), "reason": .text("用户通过屏蔽功能提交，请审核相关账号及内容。")
                    ]))
                } catch {
                    guard epoch == api.generation else { return }
                    contentSafetyError = "已屏蔽该用户，但审核通知提交失败。请通过举报入口补充提交。"
                }
            }
            if !blocked { postRevision += 1 }
        } catch {
            guard epoch == api.generation, owner == safetyAccountID else { return }
            var restored = contentSafety
            if previous { restored.blockedUsers.insert(id) } else { restored.blockedUsers.remove(id) }
            safetyRevision += 1; contentSafety = restored; saveContentSafety(); postRevision += 1
            contentSafetyError = "屏蔽设置未能保存，已恢复原状态。\(error.localizedDescription)"
            throw error
        }
    }
}
