import Foundation
import Combine
import CryptoKit

struct PostChange {
    let postID: Int
    let patch: JSON? // nil means deleted
    let provisional: Bool
    init(postID: Int, patch: JSON?, provisional: Bool = false) {
        self.postID = postID; self.patch = patch; self.provisional = provisional
    }
}
struct NoticeChange {
    let id: Int? // nil marks all currently loaded notifications as read
}

@MainActor
final class AppSession: ObservableObject {
    let api: APIClient
    let socket: RealtimeClient
    private let consent: PrivacyConsent
    @Published var user: Person?
    @Published var restoring = true
    @Published var startupError: String?
    @Published var authenticationMessage: String?
    @Published var postRevision = 0
    @Published var postChange: PostChange?
    @Published var noticeChange: NoticeChange?
    @Published var noticeRevision = 0
    @Published var topicRevision = 0
    @Published var messageUnread = 0
    @Published var noticeUnread = 0
    @Published var defaultVisibility = "public"
    @Published var contentSafety = ContentSafety()
    @Published var contentSafetyError: String?
    @Published var safetySyncing = false
    let contentDefaults: UserDefaults
    var safetyAccountID = 0
    var safetyRevision = 0
    var pendingPostHides: [Int: Bool] = [:]
    var blockingUserIDs = Set<Int>()
    @Published private(set) var notificationAuthorizationReady = false
    private var foreground = true
    private var pendingPostLikes: [Int: (ticket: UUID, patch: JSON)] = [:]

    func pendingLikePatch(for id: Int) -> JSON { pendingPostLikes[id]?.patch ?? .object([:]) }
    var pendingLikePatches: [Int: JSON] { pendingPostLikes.mapValues { $0.patch } }

    func togglePostLike(_ post: Post) async throws {
        guard user != nil, post.id > 0, pendingPostLikes[post.id] == nil else { return }
        let epoch = api.generation, ticket = UUID(), liked = !post.liked
        let before: JSON = .object(["is_liked": .bool(post.liked), "like_count": .id(post.likes)])
        let optimistic: JSON = .object(["is_liked": .bool(liked), "like_count": .id(max(0, post.likes + (liked ? 1 : -1)))])
        pendingPostLikes[post.id] = (ticket, optimistic)
        postChange = PostChange(postID: post.id, patch: optimistic, provisional: true)
        defer { if pendingPostLikes[post.id]?.ticket == ticket { pendingPostLikes[post.id] = nil } }
        do {
            let response = try await api.request("/posts/\(post.id)/like", method: liked ? "POST" : "DELETE")
            guard api.generation == epoch, pendingPostLikes[post.id]?.ticket == ticket else { return }
            let result = response["post"].or(response)
            var confirmed = optimistic
            let serverLiked = result["is_liked"].or(result["liked"])
            if !serverLiked.isNull { confirmed["is_liked"] = .bool(serverLiked.bool) }
            if !result["like_count"].isNull { confirmed["like_count"] = .id(max(0, result["like_count"].int)) }
            pendingPostLikes[post.id] = nil
            postChange = PostChange(postID: post.id, patch: confirmed)
        } catch {
            guard api.generation == epoch, pendingPostLikes[post.id]?.ticket == ticket else { return }
            pendingPostLikes[post.id] = nil
            postChange = PostChange(postID: post.id, patch: before)
            throw error
        }
    }

    init(api: APIClient? = nil, consent: PrivacyConsent? = nil, contentDefaults: UserDefaults = .standard) {
        let api = api ?? APIClient()
        self.consent = consent ?? PrivacyConsent.shared
        self.contentDefaults = contentDefaults
        self.api = api; socket = RealtimeClient(api: api)
        APNsService.shared.attach(api: api)
        NativeNotifications.shared.onAuthorizationChanged = { [weak self] in self?.syncPush() }
        socket.onLiveEvent = { payload, seq in NativeNotifications.shared.receive(payload, seq: seq) }
        api.onSessionExpired = { [weak self] in self?.clearUI() }
        api.onTokenRefreshed = { [weak self] in
            guard let self, self.foreground, let id = self.user?.id else { return }
            self.socket.start(userID: id)
        }
    }
    func bootstrap() async {
        guard consent.accepted else { restoring = false; return }
        restoring = true; startupError = nil
        defer { restoring = false }
        do {
            try api.restore()
            guard api.token != nil else { APNsService.shared.setAccount(nil, enabled: false); return }
            try await refreshProfile()
            await loadPreferences()
        } catch {
            if api.token != nil { startupError = error.localizedDescription }
        }
    }
    func authenticate(email: String, password: String, code: String, username: String? = nil) async throws {
        guard consent.accepted else { throw APIError(status: 0, message: AppLocalization.string("请先阅读并决定是否同意隐私说明")) }
        var body: [String: JSON] = ["email": .text(email), "password": .text(password)]
        if !code.isEmpty { body["email_code"] = .text(code) }
        if let username { body["username"] = .text(username) }
        let result = try await api.request(username == nil ? "/auth/login" : "/auth/register", method: "POST", body: .object(body), authenticated: false)
        let token = result["access_token"].string
        guard !token.isEmpty else { throw APIError(status: 0, message: AppLocalization.string("登录响应缺少凭据，请重试")) }
        try api.setToken(token)
        do { try await refreshProfile() }
        catch {
            // Keep a valid freshly issued token when only profile loading fails offline.
            if api.token != nil { startupError = error.localizedDescription }
            throw error
        }
        await loadPreferences()
    }
    func refreshProfile() async throws {
        let result = try await api.request("/auth/profile")
        let profile = Person(result["user"].or(result))
        guard profile.id > 0 else { throw APIError(status: 0, message: AppLocalization.string("用户信息不完整，请重新登录")) }
        restoreContentSafety(userID: profile.id)
        user = profile
        NativeNotifications.shared.userID = profile.id
        if foreground { socket.start(userID: profile.id) }
        await refreshCounts()
    }
    func loadPreferences() async {
        notificationAuthorizationReady = false
        let epoch = api.generation
        await NativeNotifications.shared.refreshAuthorization()
        guard epoch == api.generation else { return }
        if let json = try? await api.request("/notifications/settings") {
            guard epoch == api.generation else { return }
            let settings = json["settings"].or(json)
            NativeNotifications.shared.pushEnabled = settings["notify_push"].bool
            NativeNotifications.shared.messageEnabled = settings["notify_message"].bool
            NativeNotifications.shared.soundEnabled = settings["notify_sound"].bool
        }
        guard epoch == api.generation else { return }
        syncPush()
        notificationAuthorizationReady = true
        if let privacy = try? await api.request("/auth/privacy") {
            guard epoch == api.generation else { return }
            defaultVisibility = ["friends", "friends_only"].contains(privacy["post_default_visibility"].string) ? "friends" : "public"
        }
        await refreshContentSafety()
    }
    func refreshCounts() async {
        guard foreground, user != nil else { return }
        let epoch = api.generation
        async let chat = try? api.request("/chat/unread-count")
        async let notice = try? api.request("/notifications/unread-count")
        let (c, n) = await (chat, notice)
        guard epoch == api.generation else { return }
        if let c { messageUnread = max(0, c["total_unread"].or(c["unread_count"]).or(c["count"]).int) }
        if let n { noticeUnread = max(0, n["unread_count"].or(n["count"]).int) }
        NativeNotifications.shared.setBadge(messageUnread + noticeUnread)
    }
    func syncPush() {
        APNsService.shared.setAccount(user?.id, enabled: NativeNotifications.shared.authorized && NativeNotifications.shared.pushEnabled)
    }
    func requestNotificationAuthorizationIfNeeded() async {
        guard consent.accepted, foreground, notificationAuthorizationReady, let userID = user?.id, api.token != nil else { return }
        let epoch = api.generation
        let notifications = NativeNotifications.shared
        await notifications.refreshAuthorization()
        guard !Task.isCancelled, consent.accepted, foreground, notificationAuthorizationReady,
              epoch == api.generation, user?.id == userID,
              notifications.authorizationStatus == .notDetermined else { return }
        // The home screen owns timing. A refusal is respected; errors remain
        // visible in notification settings without blocking entry to the app.
        try? await notifications.requestAuthorization()
    }
    func scene(active: Bool) {
        guard consent.accepted else { socket.stop(); return }
        foreground = active
        APNsService.shared.setForeground(active)
        if active {
            Task {
                await NativeNotifications.shared.refreshAuthorization()
                syncPush()
                await refreshCounts()
                await refreshContentSafety()
            }
        }
        if active, let id = user?.id { socket.start(userID: id) } else { socket.stop() }
    }
    func logout(message: String? = nil) async throws {
        APNsService.shared.setAccount(nil, enabled: false)
        await APNsService.shared.waitUntilIdle()
        try api.setToken(nil); clearUI(); authenticationMessage = message
    }
    func clearUI() {
        pendingPostLikes.removeAll()
        safetyAccountID = 0; safetyRevision += 1; pendingPostHides = [:]; blockingUserIDs = []
        contentSafety = ContentSafety(); contentSafetyError = nil; safetySyncing = false
        authenticationMessage = nil
        notificationAuthorizationReady = false
        APNsService.shared.setAccount(nil, enabled: false)
        socket.stop(); socket.resetRooms(); user = nil; messageUnread = 0; noticeUnread = 0
        NativeNotifications.shared.clear()
        startupError = nil; defaultVisibility = "public"; postChange = nil; noticeChange = nil; postRevision += 1
        URLCache.shared.removeAllCachedResponses()
    }
}

/// Cached responses are scoped to the verified server user ID and never shared
/// between accounts. Credentials are stored only in Keychain.
@MainActor
enum LocalCache {
    private static func url(userID: Int, key: String) -> URL? {
        guard userID > 0, let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = root.appendingPathComponent("Nonto/\(userID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Fixed length even for long search terms; query identity is canonicalized below.
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name + ".json")
    }
    static func read(userID: Int, key: String) -> JSON? {
        guard let url = url(userID: userID, key: key), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSON.decode(data)
    }
    static func write(_ json: JSON, userID: Int, key: String) {
        guard let url = url(userID: userID, key: key), let data = try? json.encoded() else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    static func clear(userID: Int) throws {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let folder = root.appendingPathComponent("Nonto/\(userID)")
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}

@MainActor
final class PagedResource<T: Record>: ObservableObject {
    @Published var items: [T] = []
    @Published var loading = false
    @Published var error: String?
    @Published var hasMore = true
    @Published private(set) var showingCache = false
    private(set) var page = 0
    private var lastLoadedAt: Date?
    private var failedReset = true
    private var emptyPageStreak = 0
    private var cursor: String?
    private var requestID = UUID()
    private var activeTask: Task<Void, Never>?
    private var activeReset = false
    private var pendingUpdates: [Int: JSON] = [:]
    private var pendingRemovals = Set<Int>()
    private var optimisticUpdates: [Int: JSON] = [:]
    private var postObservation: AnyCancellable?
    private var safetyObservation: AnyCancellable?
    private var visibilityFilter: ((T) -> T?)?
    private var sourceItems: [T]?
    private var seenPageIDs = Set<Int>()
    private var api: APIClient
    private let accountEpoch: UUID
    let path: String
    let keys: [String]
    let query: [String: String]
    let pageSize: Int
    let userID: Int
    let paginated: Bool
    let usesOffset: Bool
    let cacheEnabled: Bool
    var cacheKey: String {
        var components = URLComponents()
        components.path = path
        components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        return "resource.v2." + (components.string ?? path) + ":\(pageSize):\(paginated):\(usesOffset)"
    }

    init(api: APIClient, path: String, keys: [String], query: [String: String] = [:],
         userID: Int, pageSize: Int = 20, paginated: Bool = true, usesOffset: Bool = false, cacheEnabled: Bool = true) {
        self.api = api; accountEpoch = api.generation; self.path = path; self.keys = keys; self.query = query
        self.userID = userID; self.pageSize = pageSize; self.paginated = paginated; self.usesOffset = usesOffset
        self.cacheEnabled = cacheEnabled
        if cacheEnabled, let cache = LocalCache.read(userID: userID, key: cacheKey) {
            items = Records.unique(cache.array.map(T.init)); showingCache = !items.isEmpty
        }
    }
    func loadIfNeeded(maxAge: TimeInterval = 60) async {
        if error == nil, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < maxAge { return }
        await load(reset: true)
    }
    func retry() async { emptyPageStreak = 0; await load(reset: failedReset) }
    func applyAll(patch: JSON) {
        guard api.generation == accountEpoch else { return }
        if loading {
            for item in items { pendingUpdates[item.id] = (pendingUpdates[item.id] ?? .object([:])).merging(patch) }
        }
        let updated = (sourceItems ?? items).map { T($0.raw.merging(patch)) }
        if sourceItems != nil { sourceItems = updated }
        items = visibilityFilter.map { updated.compactMap($0) } ?? updated; persist()
    }
    func load(reset: Bool = false, superseding: Bool = false) async {
        guard api.generation == accountEpoch else { return }
        if let task = activeTask {
            // Coalesce refresh events; a refresh supersedes an older next-page request.
            if !superseding && (!reset || activeReset) { await task.value; return }
            task.cancel()
        } else if !reset && !hasMore { return }
        let ticket = UUID(); requestID = ticket
        pendingUpdates.removeAll(); pendingRemovals.removeAll()
        activeReset = reset; loading = true; error = nil
        let task = Task<Void, Never> { [weak self] in await self?.fetch(reset: reset, ticket: ticket) }
        activeTask = task
        await task.value
        if requestID == ticket { activeTask = nil; loading = false }
    }
    private func fetch(reset: Bool, ticket: UUID) async {
        guard requestID == ticket, api.generation == accountEpoch, !Task.isCancelled else { return }
        let epoch = accountEpoch, next = reset ? 1 : page + 1
        let previousCursor = reset ? nil : cursor
        do {
            var params = query
            if paginated {
                if usesOffset { params["offset"] = String((next - 1) * pageSize); params["limit"] = String(pageSize) }
                else { params["page"] = String(next); params["per_page"] = String(pageSize) }
                if let previousCursor { params["cursor"] = previousCursor }
            }
            let json = try await api.request(path, query: params)
            try Task.checkCancellation()
            guard requestID == ticket, api.generation == epoch else { return }
            let rows = try Self.rows(json, keys: keys)
            let parsed = Records.unique(rows.map(T.init))
            guard rows.isEmpty || !parsed.isEmpty else { throw APIError(status: 0, message: AppLocalization.string("服务器返回的列表缺少有效记录，请重试")) }
            let merged = parsed.filter { !pendingRemovals.contains($0.id) }.map { item in
                T(item.raw.merging(pendingUpdates[item.id] ?? .object([:]))
                    .merging(optimisticUpdates[item.id] ?? .object([:])))
            }
            let added = parsed.contains { reset || !seenPageIDs.contains($0.id) }
            if reset { seenPageIDs = [] }; seenPageIDs.formUnion(parsed.map(\.id))
            let updated = Records.unique((reset ? [] : (sourceItems ?? items)) + merged)
            if sourceItems != nil { sourceItems = updated }
            items = visibilityFilter.map { updated.compactMap($0) } ?? updated
            page = next
            lastLoadedAt = Date(); showingCache = false
            let nextCursor = json["next_cursor"].string
            cursor = nextCursor.isEmpty ? nil : nextCursor
            let inferredMore: Bool
            if cursor != nil { inferredMore = true }
            else if !json["total_pages"].isNull { inferredMore = next < json["total_pages"].int }
            else if !json["pages"].isNull { inferredMore = next < json["pages"].int }
            else { inferredMore = rows.count >= pageSize }
            hasMore = paginated && (json["has_more"].isNull ? (!parsed.isEmpty && inferredMore) : json["has_more"].bool)
            // Advancing cursors can legitimately return overlapping records or short pages.
            // Only a non-advancing cursor, or a repeated page without cursors, ends pagination.
            if !reset && next > 1 && ((cursor != nil && cursor == previousCursor) || (cursor == nil && !added && !parsed.isEmpty)) { hasMore = false }
            emptyPageStreak = hasMore && parsed.isEmpty ? (reset ? 1 : emptyPageStreak + 1) : 0
            if emptyPageStreak >= 5 {
                failedReset = false; error = AppLocalization.string("这一段暂无可见内容，可重试继续加载。")
            }
            persist()
        } catch is CancellationError {} catch {
            guard requestID == ticket, api.generation == epoch else { return }
            if (error as? URLError)?.code != .cancelled {
                if ["PROFILE_PRIVATE", "PROFILE_FRIENDS_ONLY"].contains((error as? APIError)?.code ?? "") {
                    items = []; sourceItems = sourceItems.map { _ in [] }; showingCache = false; hasMore = false
                    LocalCache.write(.array([]), userID: userID, key: cacheKey)
                }
                failedReset = reset; self.error = error.localizedDescription
            }
        }
    }
    static func rows(_ json: JSON, keys: [String]) throws -> [JSON] {
        if case .array(let rows) = json { return rows }
        for key in keys { if case .array(let rows) = json[key] { return rows } }
        throw APIError(status: 0, message: AppLocalization.string("服务器返回的列表不完整，请重试"))
    }
    func apply(id: Int, patch: JSON?, provisional: Bool = false) {
        guard api.generation == accountEpoch else { return }
        if provisional, let patch {
            optimisticUpdates[id] = (optimisticUpdates[id] ?? .object([:])).merging(patch)
        } else if let patch, var remaining = optimisticUpdates[id]?.object {
            // A comment count or edit must not settle an unrelated in-flight like.
            for key in patch.object.keys { remaining[key] = nil }
            optimisticUpdates[id] = remaining.isEmpty ? nil : .object(remaining)
        } else if patch == nil {
            optimisticUpdates[id] = nil
        }
        var updated = sourceItems ?? items
        if let patch {
            if loading { pendingUpdates[id] = (pendingUpdates[id] ?? .object([:])).merging(patch) }
            if let index = updated.firstIndex(where: { $0.id == id }) { updated[index] = T(updated[index].raw.merging(patch)) }
        } else {
            if loading { pendingRemovals.insert(id) }
            updated.removeAll { $0.id == id }
        }
        if sourceItems != nil { sourceItems = updated }
        items = visibilityFilter.map { updated.compactMap($0) } ?? updated
        persist()
    }
    private func persist() {
        guard cacheEnabled else { return }
        LocalCache.write(.array(Array(items.prefix(100)).map(\.raw)), userID: userID, key: cacheKey)
    }
}

extension PagedResource where T == Conversation {
    func markRead(_ conversation: Conversation) async throws {
        guard conversation.id > 0, conversation.unread > 0, api.generation == accountEpoch else { return }
        _ = try await api.request("/chat/conversations/\(conversation.id)/mark-read", method: "POST")

        // Let any overlapping fetch publish first so an unread count belonging
        // to a newer last message cannot be zeroed by this older action.
        while let task = activeTask {
            let ticket = requestID
            await task.value
            if requestID == ticket { break }
        }
        try Task.checkCancellation()
        guard let current = items.first(where: { $0.id == conversation.id }),
              current.last.id == conversation.last.id, current.unread > 0 else { return }
        apply(id: conversation.id, patch: .object(["unread_count": .id(0)]))
    }
}

extension PagedResource where T == Post {
    /// Keep the backing rows and their cache in sync even when no card is visible.
    func observePostChanges(in session: AppSession) {
        guard postObservation == nil else { return }
        visibilityFilter = { [weak session] post in session?.contentSafety.visible(post) }
        sourceItems = items
        items = items.compactMap { session.contentSafety.visible($0) }; persist()
        safetyObservation = session.$contentSafety.dropFirst().sink { [weak self] safety in
            guard let self, api.generation == accountEpoch else { return }
            items = (sourceItems ?? items).compactMap { safety.visible($0) }; persist()
        }
        for (id, patch) in session.pendingLikePatches {
            apply(id: id, patch: patch, provisional: true)
        }
        postObservation = session.$postChange.dropFirst().compactMap { $0 }.sink { [weak self] change in
            guard let self else { return }
            let removeUnliked = !change.provisional && path == "/posts/user/\(userID)/liked"
                && change.patch?["is_liked"] == .bool(false)
            apply(id: change.postID, patch: removeUnliked ? nil : change.patch, provisional: change.provisional)
        }
    }
}

/// A detail response can finish after a like, edit or deletion has been confirmed.
/// Retain only mutations made during that request, then overlay any still-pending like.
@MainActor
final class PostDetailResource: ObservableObject {
    @Published private(set) var post: Post?
    @Published private(set) var error: String?
    @Published private(set) var deleted = false
    @Published private(set) var hidden = false
    private let session: AppSession
    private let postID: Int
    private let accountEpoch: UUID
    private var requestID: UUID?
    private var changesDuringLoad: JSON = .object([:])
    private var observation: AnyCancellable?
    private var safetyObservation: AnyCancellable?

    init(session: AppSession, postID: Int, initial: Post? = nil) {
        self.session = session; self.postID = postID; accountEpoch = session.api.generation
        post = initial.flatMap { session.contentSafety.visible(Post($0.raw.merging(session.pendingLikePatch(for: postID)))) }
        hidden = session.contentSafety.hiddenPosts[postID] != nil || (initial != nil && post == nil)
        observation = session.$postChange.dropFirst().compactMap { $0 }.sink { [weak self] change in
            self?.apply(change)
        }
        safetyObservation = session.$contentSafety.dropFirst().sink { [weak self] safety in
            guard let self, session.api.generation == accountEpoch else { return }
            if let post { self.post = safety.visible(post); hidden = self.post == nil }
            if safety.hiddenPosts[postID] != nil { hidden = true; post = nil }
        }
    }
    private func apply(_ change: PostChange) {
        guard session.api.generation == accountEpoch, change.postID == postID else { return }
        guard let patch = change.patch else { deleted = true; post = nil; return }
        guard !deleted else { return }
        if requestID != nil { changesDuringLoad = changesDuringLoad.merging(patch) }
        if let post { self.post = session.contentSafety.visible(Post(post.raw.merging(patch))); hidden = self.post == nil }
    }
    func load() async {
        guard session.api.generation == accountEpoch, !deleted, !hidden else { return }
        let ticket = UUID(); requestID = ticket; changesDuringLoad = .object([:])
        defer { if requestID == ticket { requestID = nil } }
        do {
            let result = try await session.api.request("/posts/\(postID)")
            try Task.checkCancellation()
            guard session.api.generation == accountEpoch, requestID == ticket, !deleted, !hidden else { return }
            let value = result["post"].or(result).merging(changesDuringLoad)
                .merging(session.pendingLikePatch(for: postID))
            post = session.contentSafety.visible(Post(value)); hidden = post == nil; error = nil
        } catch {
            guard session.api.generation == accountEpoch, requestID == ticket, !deleted,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

