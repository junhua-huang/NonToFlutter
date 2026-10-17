import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    let api: APIClient
    let socket: RealtimeClient
    @Published var user: Person?
    @Published var restoring = true
    @Published var startupError: String?
    @Published var postRevision = 0
    @Published var messageUnread = 0
    @Published var noticeUnread = 0
    @Published var defaultVisibility = "public"
    private var foreground = true

    init(api: APIClient? = nil) {
        let api = api ?? APIClient()
        self.api = api; socket = RealtimeClient(api: api)
        socket.onLiveEvent = { payload, seq in NativeNotifications.shared.receive(payload, seq: seq) }
        api.onSessionExpired = { [weak self] in self?.clearUI() }
        api.onTokenRefreshed = { [weak self] in
            guard let self, self.foreground, let id = self.user?.id else { return }
            self.socket.start(userID: id)
        }
    }
    func bootstrap() async {
        restoring = true; startupError = nil
        defer { restoring = false }
        do {
            try api.restore()
            guard api.token != nil else { return }
            try await refreshProfile()
            await loadPreferences()
        } catch {
            if api.token != nil { startupError = error.localizedDescription }
        }
    }
    func authenticate(email: String, password: String, code: String, username: String? = nil) async throws {
        var body: [String: JSON] = ["email": .text(email), "password": .text(password)]
        if !code.isEmpty { body["email_code"] = .text(code) }
        if let username { body["username"] = .text(username) }
        let result = try await api.request(username == nil ? "/auth/login" : "/auth/register", method: "POST", body: .object(body), authenticated: false)
        let token = result["access_token"].string
        guard !token.isEmpty else { throw APIError(status: 0, message: "登录响应缺少凭据，请重试") }
        try api.setToken(token)
        do { try await refreshProfile() }
        catch { try? api.setToken(nil); clearUI(); throw error }
        await loadPreferences()
    }
    func refreshProfile() async throws {
        let result = try await api.request("/auth/profile")
        let profile = Person(result["user"].or(result))
        guard profile.id > 0 else { throw APIError(status: 0, message: "用户信息不完整，请重新登录") }
        user = profile
        NativeNotifications.shared.userID = profile.id
        if foreground { socket.start(userID: profile.id) }
        await refreshCounts()
    }
    func loadPreferences() async {
        await NativeNotifications.shared.refreshAuthorization()
        if let json = try? await api.request("/notifications/settings") {
            let settings = json["settings"].or(json)
            NativeNotifications.shared.messageEnabled = settings["notify_message"].bool
            NativeNotifications.shared.soundEnabled = settings["notify_sound"].bool
        }
        if let privacy = try? await api.request("/auth/privacy") {
            defaultVisibility = ["friends", "friends_only"].contains(privacy["post_default_visibility"].string) ? "friends" : "public"
        }
    }
    func refreshCounts() async {
        let epoch = api.generation
        async let chat = try? api.request("/chat/unread-count")
        async let notice = try? api.request("/notifications/unread-count")
        let (c, n) = await (chat, notice)
        guard epoch == api.generation else { return }
        if let c { messageUnread = c["unread_count"].or(c["count"]).int }
        if let n { noticeUnread = n["unread_count"].or(n["count"]).int }
        NativeNotifications.shared.setBadge(messageUnread + noticeUnread)
    }
    func scene(active: Bool) {
        foreground = active
        if active, let id = user?.id { socket.start(userID: id) } else { socket.stop() }
    }
    func logout() throws { try api.setToken(nil); clearUI() }
    func clearUI() {
        socket.stop(); socket.resetRooms(); user = nil; messageUnread = 0; noticeUnread = 0
        NativeNotifications.shared.clear()
        startupError = nil; defaultVisibility = "public"; postRevision += 1
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
        // Reversible, collision-free filename for the resource identifier.
        let name = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        guard name.count < 220 else { return nil }
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
    private(set) var page = 0
    private var cursor: String?
    private var requestID = UUID()
    private var api: APIClient
    let path: String
    let keys: [String]
    let query: [String: String]
    let pageSize: Int
    let userID: Int
    let paginated: Bool
    let usesOffset: Bool
    var cacheKey: String { path + query.keys.sorted().map { "\($0)=\(query[$0]!)" }.joined(separator: "&") }

    init(api: APIClient, path: String, keys: [String], query: [String: String] = [:],
         userID: Int, pageSize: Int = 20, paginated: Bool = true, usesOffset: Bool = false) {
        self.api = api; self.path = path; self.keys = keys; self.query = query
        self.userID = userID; self.pageSize = pageSize; self.paginated = paginated; self.usesOffset = usesOffset
        if let cache = LocalCache.read(userID: userID, key: cacheKey) { items = Records.unique(cache.array.map(T.init)) }
    }
    func load(reset: Bool = false) async {
        guard reset || (!loading && hasMore) else { return }
        let ticket = UUID(); requestID = ticket
        let epoch = api.generation, next = reset ? 1 : page + 1
        loading = true; error = nil
        defer { if requestID == ticket { loading = false } }
        do {
            var params = query
            if paginated {
                if usesOffset { params["offset"] = String((next - 1) * pageSize); params["limit"] = String(pageSize) }
                else { params["page"] = String(next); params["per_page"] = String(pageSize) }
                if !reset, let cursor { params["cursor"] = cursor }
            }
            let json = try await api.request(path, query: params)
            guard requestID == ticket, api.generation == epoch else { return }
            let rows: [JSON]
            if case .array = json { rows = json.array }
            else { rows = keys.compactMap { key -> [JSON]? in if case .array = json[key] { return json[key].array }; return nil }.first ?? [] }
            items = Records.unique((reset ? [] : items) + rows.map(T.init))
            page = next
            cursor = json["next_cursor"].string.isEmpty ? nil : json["next_cursor"].string
            hasMore = paginated && (json["has_more"].isNull ? rows.count >= pageSize : json["has_more"].bool)
            if !json["total_pages"].isNull { hasMore = next < json["total_pages"].int }
            LocalCache.write(.array(Array(items.prefix(100)).map(\.raw)), userID: userID, key: cacheKey)
        } catch is CancellationError {} catch {
            guard requestID == ticket, api.generation == epoch else { return }
            if (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
    }
}
