import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var submitted = ""
    @State private var kind = "posts"
    @State private var topics: [Topic] = []
    @State private var history: [String] = []
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            if !submitted.isEmpty {
                Picker("搜索类型", selection: $kind) { Text("动态").tag("posts"); Text("用户").tag("users"); Text("话题").tag("topics") }.pickerStyle(.segmented).padding()
                SearchResultsView(session: session, query: submitted, kind: kind).id(submitted + kind)
            } else {
                List {
                    Section {
                        NavigationLink { CommunityListView(session: session) } label: { Label("发现社群", systemImage: "person.3") }
                        NavigationLink { FollowedTopicsView(session: session) } label: { Label("我的话题", systemImage: "number") }
                    }
                    if !history.isEmpty {
                        Section {
                            ForEach(history, id: \.self) { item in Button { query = item; search() } label: { Label(item, systemImage: "clock").foregroundStyle(.primary) } }
                            Button("清空搜索记录", role: .destructive) { Task { await clearHistory() } }
                        } header: { Text("最近搜索") }
                    }
                    Section("热门话题") {
                        ForEach(topics) { topic in NavigationLink { TopicDetailView(topic: topic) } label: { HStack { Image(systemName: "number").foregroundStyle(Color.brand); Text(topic.name); Spacer(); Text("\(topic.raw["post_count"].int) 动态").font(.caption).foregroundStyle(.secondary) } } }
                    }
                    ErrorBanner(text: error)
                }.listStyle(.insetGrouped).refreshable { await load() }
            }
        }.navigationTitle("发现")
            .searchable(text: $query, prompt: "搜索动态、用户和话题")
            .onSubmit(of: .search, search)
            .onChange(of: query) { _, value in if value.isEmpty { submitted = "" } }
            .task { await load() }
    }
    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { error = "搜索关键词至少需要 2 个字符"; return }
        submitted = text
        Task {
            _ = try? await session.api.request("/search/history", method: "POST", body: .object(["query": .text(text), "type": .text(kind)]))
            await load()
        }
    }
    private func load() async {
        do {
            let result = try await session.api.request("/topics/trending", query: ["limit": "20"])
            topics = Records.unique(result.list("topics", "items").map(Topic.init)); error = nil
            if let j = try? await session.api.request("/search/history", query: ["limit": "20"]) {
                var seen = Set<String>()
                history = j.list("history", "items").map { $0["query"].or($0).string }.filter { !$0.isEmpty && seen.insert($0).inserted }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func clearHistory() async {
        do { _ = try await session.api.request("/search/history", method: "DELETE"); history = [] }
        catch { self.error = error.localizedDescription }
    }
}

struct SearchResultsView: View {
    let kind: String
    @StateObject private var posts: PagedResource<Post>
    @StateObject private var users: PagedResource<Person>
    @StateObject private var topics: PagedResource<Topic>
    init(session: AppSession, query: String, kind: String) {
        self.kind = kind
        let uid = session.user?.id ?? 0
        _posts = StateObject(wrappedValue: PagedResource(api: session.api, path: "/search/posts", keys: ["posts", "items"], query: ["q": query], userID: uid))
        _users = StateObject(wrappedValue: PagedResource(api: session.api, path: "/search/users", keys: ["users", "items"], query: ["q": query], userID: uid))
        _topics = StateObject(wrappedValue: PagedResource(api: session.api, path: "/search/topics", keys: ["topics", "items"], query: ["q": query], userID: uid))
    }
    var body: some View {
        List {
            if kind == "posts" {
                ForEach(posts.items) { PostCard(post: $0).listRowSeparator(.hidden) }; ResourceFooter(resource: posts)
            } else if kind == "users" {
                ForEach(users.items) { user in NavigationLink { ProfileView(userID: user.id) } label: { PersonRow(person: user) } }; ResourceFooter(resource: users)
            } else {
                ForEach(topics.items) { topic in NavigationLink("#\(topic.name)") { TopicDetailView(topic: topic) } }; ResourceFooter(resource: topics)
            }
        }.listStyle(.plain).task { await load() }.refreshable { await load() }
    }
    private func load() async {
        if kind == "posts" { await posts.load(reset: true) }
        else if kind == "users" { await users.load(reset: true) }
        else { await topics.load(reset: true) }
    }
}

struct TopicDetailView: View {
    let topic: Topic
    @EnvironmentObject private var session: AppSession
    @State private var following = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(spacing: 0) {
            if !topic.raw["description"].string.isEmpty { Text(topic.raw["description"].string).font(.subheadline).foregroundStyle(.secondary).padding() }
            ErrorBanner(text: error)
            PostList(session: session, path: "/topics/\(topic.id)/posts")
        }.navigationTitle("#\(topic.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(following ? "已关注" : "关注") { Task { await toggle() } }.disabled(busy) }
            .task {
                following = topic.raw["is_following"].bool
                if let j = try? await session.api.request("/topics/\(topic.id)") { following = j["topic"].or(j)["is_following"].bool }
            }
    }
    private func toggle() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/topics/\(topic.id)/\(following ? "unfollow" : "follow")", method: "POST"); following.toggle() }
        catch { self.error = error.localizedDescription }
    }
}

struct FollowedTopicsView: View {
    @StateObject private var resource: PagedResource<Topic>
    init(session: AppSession) { _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/topics/followed", keys: ["topics", "items"], userID: session.user?.id ?? 0)) }
    var body: some View {
        List { ForEach(resource.items) { topic in NavigationLink("#\(topic.name)") { TopicDetailView(topic: topic) } }; ResourceFooter(resource: resource) }
            .navigationTitle("我的话题").task { await resource.load(reset: true) }.refreshable { await resource.load(reset: true) }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var resource: PagedResource<Notice>
    @ObservedObject private var socket: RealtimeClient
    @State private var error: String?
    init(session: AppSession) {
        _socket = ObservedObject(wrappedValue: session.socket)
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/notifications/", keys: ["notifications", "items"], userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            ErrorBanner(text: error)
            ForEach(resource.items) { notice in
                NavigationLink { NoticeDestination(notice: notice) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(url: notice.sender.avatar, name: notice.sender.name)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notice.title.isEmpty ? notice.sender.name : notice.title).font(.headline)
                            Text(notice.content).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            if let d = ServerDate.parse(notice.raw["created_at"]) { Text(d, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if !notice.isRead { Circle().fill(Color.brand).frame(width: 8, height: 8) }
                    }.padding(.vertical, 6)
                }.swipeActions {
                    Button(role: .destructive) { Task { await remove(notice) } } label: { Label("删除", systemImage: "trash") }
                }
            }
            ResourceFooter(resource: resource)
        }.navigationTitle("通知").listStyle(.plain)
            .toolbar { Button("全部已读") { Task { await readAll() } }.disabled(session.noticeUnread == 0) }
            .task { await resource.load(reset: true) }
            .refreshable { await resource.load(reset: true); await session.refreshCounts() }
            .onReceive(socket.$revision.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in Task { await resource.load(reset: true); await session.refreshCounts() } }
    }
    private func readAll() async {
        do { _ = try await session.api.request("/notifications/mark-all-read", method: "POST"); await resource.load(reset: true); await session.refreshCounts() }
        catch { self.error = error.localizedDescription }
    }
    private func remove(_ notice: Notice) async {
        do { _ = try await session.api.request("/notifications/\(notice.id)", method: "DELETE"); resource.items.removeAll { $0.id == notice.id }; await session.refreshCounts() }
        catch { self.error = error.localizedDescription }
    }
}

struct NoticeDestination: View {
    let notice: Notice
    @EnvironmentObject private var session: AppSession
    @State private var postID: Int?
    @State private var error: String?
    var body: some View {
        Group {
            if notice.raw["notification_type"].or(notice.raw["type"]).string.hasPrefix("friend_") { FriendsView(session: session) }
            else if let postID { PostDetailView(session: session, postID: postID) }
            else if notice.raw["related_type"].string == "community" { CommunityDetailView(communityID: notice.raw["related_id"].int) }
            else { ScrollView { VStack(alignment: .leading, spacing: 16) { Text(notice.title).font(.title2.bold()); Text(notice.content); ErrorBanner(text: error) }.padding().frame(maxWidth: .infinity, alignment: .leading) } }
        }.task {
            do {
                _ = try await session.api.request("/notifications/\(notice.id)/read", method: "POST"); await session.refreshCounts()
                let type = notice.raw["related_type"].string
                if type == "post" { postID = notice.raw["related_id"].int }
                else if type == "comment" {
                    let j = try await session.api.request("/comments/\(notice.raw["related_id"].int)")
                    let id = j["comment"].or(j)["post_id"].int; if id > 0 { postID = id }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
