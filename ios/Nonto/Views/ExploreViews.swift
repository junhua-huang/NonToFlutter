import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var submitted = ""
    @State private var kind = "posts"
    @State private var topics: [Topic] = []
    @State private var history: [String] = []
    @State private var error: String?
    @State private var queryError: String?
    var body: some View {
        VStack(spacing: 0) {
            if queryError != nil { ErrorBanner(text: queryError).padding(.horizontal) }
            if !submitted.isEmpty {
                TimelineTabs(title: "搜索类型", tabs: [("posts", "动态"), ("users", "用户"), ("topics", "话题")], selection: $kind)
                SearchResultsView(session: session, query: submitted, kind: kind).id(submitted + kind)
            } else {
                List {
                    Section {
                        RouteButton(.communities()) { Label("发现社群", systemImage: "person.3") }
                        RouteButton(.followedTopics) { Label("我的话题", systemImage: "number") }
                    }
                    if !history.isEmpty {
                        Section {
                            ForEach(history, id: \.self) { item in Button { query = item; search() } label: { Label(item, systemImage: "clock").foregroundStyle(.primary) } }
                            Button("清空搜索记录", role: .destructive) { Task { await clearHistory() } }
                        } header: { Text("最近搜索") }
                    }
                    Section {
                        ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                            RouteButton(.topic(topic)) {
                                HStack(alignment: .top, spacing: 16) {
                                    Text("\(index + 1)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                        .frame(width: 20, alignment: .leading).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("热门话题").font(.caption).foregroundStyle(.secondary)
                                        Text("#\(topic.name)").font(.body.bold()).foregroundStyle(.primary)
                                        Text("\(topic.raw["post_count"].int) 条动态").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                    } header: { Text("正在热议").font(.title3.bold()).foregroundStyle(.primary).textCase(nil) }
                    if error != nil { ErrorBanner(text: error) }
                }.timelineList().refreshable { await load() }
            }
        }.navigationTitle("发现").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索动态、用户和话题")
            .onSubmit(of: .search, search)
            .onChange(of: query) { _, value in
                queryError = nil
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submitted = "" }
            }
            .task { await load() }
    }
    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { queryError = "搜索关键词至少需要 2 个字符"; return }
        queryError = nil; submitted = text
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
                ForEach(posts.items) { PostCard(post: $0).timelinePostRow() }; ResourceFooter(resource: posts, emptyTitle: "没有找到相关动态", emptyDescription: "试试其他关键词，或切换搜索类型。", emptyIcon: "magnifyingglass")
            } else if kind == "users" {
                ForEach(users.items) { user in RouteButton(.profile(user.id)) { PersonRow(person: user) } }; ResourceFooter(resource: users, emptyTitle: "没有找到相关用户", emptyDescription: "试试用户名或显示名称。", emptyIcon: "person.crop.circle.badge.questionmark")
            } else {
                ForEach(topics.items) { topic in RouteButton(.topic(topic)) { Text("#\(topic.name)") } }; ResourceFooter(resource: topics, emptyTitle: "没有找到相关话题", emptyDescription: "试试其他关键词。", emptyIcon: "number")
            }
        }.timelineList().scrollDismissesKeyboard(.interactively).task { await load() }.refreshable { await load() }
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
            if error != nil { ErrorBanner(text: error) }
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
        List { ForEach(resource.items) { topic in RouteButton(.topic(topic)) { Text("#\(topic.name)") } }; ResourceFooter(resource: resource) }
            .navigationTitle("我的话题").task { await resource.loadIfNeeded() }.refreshable { await resource.load(reset: true) }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var resource: PagedResource<Notice>
    @ObservedObject private var socket: RealtimeClient
    @State private var error: String?
    @State private var readingAll = false
    @State private var removing = Set<Int>()
    init(session: AppSession) {
        _socket = ObservedObject(wrappedValue: session.socket)
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/notifications/", keys: ["notifications", "items"], userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            ErrorBanner(text: error)
            ForEach(resource.items) { notice in
                RouteButton(.notice(notice)) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(url: notice.sender.avatar, name: notice.sender.name, size: 42)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notice.title.isEmpty ? notice.sender.name : notice.title).font(.headline)
                            Text(notice.content).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            if let d = ServerDate.parse(notice.raw["created_at"]) { Text(d, format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if !notice.isRead { Circle().fill(Color.brand).frame(width: 8, height: 8) }
                    }.padding(.vertical, 10)
                }.disabled(removing.contains(notice.id)).swipeActions {
                    Button(role: .destructive) { Task { await remove(notice) } } label: { Label("删除", systemImage: "trash") }
                }.listRowBackground(notice.isRead ? Color.timelineBackground : Color.brand.opacity(0.045))
            }
            ResourceFooter(resource: resource, emptyTitle: "还没有通知", emptyDescription: "新的互动和提醒会出现在这里。", emptyIcon: "bell")
        }.navigationTitle("通知").navigationBarTitleDisplayMode(.inline).timelineList()
            .toolbar { Button("全部已读") { Task { await readAll() } }.disabled(readingAll || session.noticeUnread == 0) }
            .task { await resource.loadIfNeeded() }
            .refreshable { await resource.load(reset: true); await session.refreshCounts() }
            .onReceive(session.$noticeChange.dropFirst().compactMap { $0 }) { change in
                let patch: JSON = .object(["is_read": .bool(true)])
                if let id = change.id { resource.apply(id: id, patch: patch) }
                else { resource.applyAll(patch: patch) }
            }
            .onReceive(socket.$revision.dropFirst().debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in Task { await resource.load(reset: true); await session.refreshCounts() } }
    }
    private func readAll() async {
        guard !readingAll else { return }
        readingAll = true; error = nil; defer { readingAll = false }
        do {
            _ = try await session.api.request("/notifications/mark-all-read", method: "POST")
            session.noticeChange = NoticeChange(id: nil)
            await session.refreshCounts()
        }
        catch { self.error = error.localizedDescription }
    }
    private func remove(_ notice: Notice) async {
        guard removing.insert(notice.id).inserted else { return }
        error = nil; defer { removing.remove(notice.id) }
        do { _ = try await session.api.request("/notifications/\(notice.id)", method: "DELETE"); resource.apply(id: notice.id, patch: nil); await session.refreshCounts() }
        catch { self.error = error.localizedDescription }
    }
}

struct NoticeDestination: View {
    let notice: Notice
    @EnvironmentObject private var session: AppSession
    @State private var postID: Int?
    @State private var resolved = false
    @State private var error: String?
    var body: some View {
        Group {
            if notice.raw["notification_type"].or(notice.raw["type"]).string.hasPrefix("friend_") { FriendsView(session: session) }
            else if !resolved { ProgressView("正在打开通知…") }
            else if let postID { PostDetailView(session: session, postID: postID) }
            else if notice.raw["related_type"].string == "community" { CommunityDetailView(communityID: notice.raw["related_id"].int) }
            else { ScrollView { VStack(alignment: .leading, spacing: 16) { Text(notice.title).font(.title2.bold()); Text(notice.content); ErrorBanner(text: error) }.padding().frame(maxWidth: .infinity, alignment: .leading) } }
        }.task(id: notice.id) {
            postID = nil; resolved = false; error = nil
            defer { resolved = true }
            async let acknowledgement = try? session.api.request("/notifications/\(notice.id)/read", method: "POST")
            do {
                let type = notice.raw["related_type"].string
                if type == "post", notice.raw["related_id"].int > 0 { postID = notice.raw["related_id"].int }
                else if type == "comment" {
                    let j = try await session.api.request("/comments/\(notice.raw["related_id"].int)")
                    let id = j["comment"].or(j)["post_id"].int; if id > 0 { postID = id }
                }
            } catch { self.error = error.localizedDescription }
            if await acknowledgement != nil {
                session.noticeChange = NoticeChange(id: notice.id)
                await session.refreshCounts()
            }
        }
    }
}
