import SwiftUI
import PhotosUI

struct CommunityListView: View {
    var mine: Bool
    @StateObject private var resource: PagedResource<Community>
    @State private var creating = false
    init(session: AppSession, mine: Bool = false) {
        self.mine = mine
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: mine ? "/communities/my" : "/communities", keys: ["communities", "items"], userID: session.user?.id ?? 0, paginated: !mine, usesOffset: true))
    }
    var body: some View {
        List {
            ForEach(resource.items) { community in
                RouteButton(.community(community.id)) {
                    HStack(spacing: 12) {
                        AvatarView(url: community.avatar, name: community.name, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(community.name).font(.headline)
                            Text(community.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(community.raw["member_count"].int) 位成员").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
            }
            ResourceFooter(resource: resource, emptyTitle: mine ? "还没有加入社群" : "还没有可见的社群", emptyDescription: "找到感兴趣的社群，或创建自己的社群。", emptyIcon: "person.3")
        }.buttonStyle(.plain).navigationTitle(mine ? "我的社群" : "发现社群")
            .toolbar { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("创建社群") }
            .sheet(isPresented: $creating, onDismiss: { Task { await resource.load(reset: true) } }) { CommunityEditor() }
            .task { await resource.loadIfNeeded() }.refreshable { await resource.load(reset: true) }
    }
}

struct CommunityDetailView: View {
    let communityID: Int
    @EnvironmentObject private var session: AppSession
    @State private var community: Community?
    @State private var error: String?
    @State private var busy = false
    @State private var compose = false
    @State private var editing = false
    @State private var leaving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let community {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AvatarView(url: community.avatar, name: community.name, size: 56)
                        VStack(alignment: .leading) { Text(community.name).font(.title2.bold()); Text("\(community.raw["member_count"].int) 位成员").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if !community.isMember { Button(community.raw["my_status"].string == "pending" ? "审核中" : "加入") { Task { await join() } }.buttonStyle(.glassProminent).disabled(busy || community.raw["my_status"].string == "pending") }
                    }
                    Text(community.description).font(.subheadline).lineLimit(4)
                    if !community.raw["rules"].string.isEmpty { Text("群规：\(community.raw["rules"].string)").font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    HStack {
                        RouteButton(.communityManage(community)) { Label(community.isManager ? "管理社群" : "成员和公告", systemImage: "person.3") }
                        Spacer()
                        if community.isMember {
                            RouteButton(.chat(Conversation(.object(["id": .id(0), "type": .text("community"), "community_id": .id(communityID), "community_name": .text(community.name), "community_avatar": .text(community.avatar)])))) { Label("群聊", systemImage: "bubble.left.and.bubble.right") }

                        }
                    }.font(.subheadline)
                }.padding()
                PostList(session: session, path: "/posts/", query: ["community_id": String(communityID)])
            } else if error == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            ErrorBanner(text: error) { Task { await load() } }
        }.navigationTitle("社群").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let community {
                    Menu {
                        if community.isMember { Button("发布动态") { compose = true } }
                        if community.isManager { Button("编辑社群") { editing = true } }
                        if community.isMember && community.raw["my_role"].string != "owner" { Button("退出社群", role: .destructive) { leaving = true } }
                    } label: { Image(systemName: "ellipsis") }
                }
            }.task { await load() }
            .sheet(isPresented: $compose) { PostComposer(communityID: communityID) }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { CommunityEditor(community: community) }
            .confirmationDialog("退出这个社群？", isPresented: $leaving) {
                Button("退出社群", role: .destructive) { Task { await leave() } }
            }
    }
    private func load() async {
        do { let j = try await session.api.request("/communities/\(communityID)"); community = Community(j["community"].or(j)); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func join() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/communities/\(communityID)/join", method: "POST", body: .object([:])); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func leave() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/communities/\(communityID)/members/me", method: "DELETE"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct CommunityEditor: View {
    var community: Community? = nil
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var rules = ""
    @State private var policy = "approval"
    @State private var avatar: PhotosPickerItem?
    @State private var banner: PhotosPickerItem?
    @State private var avatarURL = ""
    @State private var bannerURL = ""
    @State private var initialized = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("社群名称", text: $name)
                TextField("社群介绍", text: $description, axis: .vertical).lineLimit(3...8)
                TextField("群规", text: $rules, axis: .vertical).lineLimit(3...8)
                Picker("加入方式", selection: $policy) { Text("需要审核").tag("approval"); Text("自由加入").tag("open") }
                PhotosPicker("设置头像", selection: $avatar, matching: .images)
                if !avatarURL.isEmpty { AvatarView(url: avatarURL, name: name, size: 60) }
                PhotosPicker("设置封面", selection: $banner, matching: .images)
                if !bannerURL.isEmpty { Label("已设置封面", systemImage: "checkmark") }
                ErrorBanner(text: error)
                if busy { ProgressView() }
            }.disabled(busy).navigationTitle(community == nil ? "创建社群" : "编辑社群").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.interactiveDismissDisabled(busy)
                .onAppear { guard !initialized else { return }; initialized = true; if let community { name = community.name; description = community.description; rules = community.raw["rules"].string; policy = community.raw["join_policy"].string; avatarURL = community.avatar; bannerURL = community.raw["banner_url"].string } }
                .task(id: avatar) { if let avatar { await upload(avatar, isAvatar: true) } }
                .task(id: banner) { if let banner { await upload(banner, isAvatar: false) } }
        }
    }
    private func upload(_ item: PhotosPickerItem, isAvatar: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let m = try await MediaLoader.load(item); let url = try await session.api.upload(m.data, filename: m.name, mime: m.mime); if isAvatar { avatarURL = url } else { bannerURL = url } }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            _ = try await session.api.request(community.map { "/communities/\($0.id)" } ?? "/communities", method: community == nil ? "POST" : "PUT", body: .object([
                "name": .text(name), "description": .text(description), "rules": .text(rules), "join_policy": .text(policy), "avatar_url": .text(avatarURL), "banner_url": .text(bannerURL)]))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CommunityManageView: View {
    let community: Community
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "members"
    @State private var rows: [JSON] = []
    @State private var loading = false
    @State private var error: String?
    @State private var title = ""
    @State private var content = ""
    @State private var confirm = false
    @State private var acting = false
    @State private var actionPath = ""
    @State private var actionMethod = "DELETE"
    @State private var actionBody: JSON?
    @State private var offset = 0
    @State private var more = false
    private var base: String { "/communities/\(community.id)" }
    var body: some View {
        List {
            Picker("社群内容", selection: $tab) {
                Text("成员").tag("members"); Text("公告").tag("announcements")
                if community.isManager { Text("申请").tag("join-requests"); Text("黑名单").tag("bans") }
            }.pickerStyle(.segmented)
            ErrorBanner(text: error)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if tab == "announcements" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row["title"].string).font(.headline); Text(row["content"].string)
                        if community.isManager { Button("删除公告", role: .destructive) { prepare(base + "/announcements/\(row["id"].int)") } }
                    }
                } else {
                    let user = Person(row["user"].or(row["sender"]).or(row))
                    VStack(alignment: .leading, spacing: 8) {
                        RouteButton(.profile(user.id)) { PersonRow(person: user) }
                        if community.isManager {
                            HStack {
                                if tab == "join-requests" {
                                    Button("通过") { prepare(base + "/join-requests/\(row["id"].int)/approve", method: "POST") }
                                    Button("拒绝", role: .destructive) { prepare(base + "/join-requests/\(row["id"].int)/reject", method: "POST") }
                                } else if tab == "bans" { Button("解除封禁") { prepare(base + "/bans/\(row["user_id"].or(.id(user.id)).int)") } }
                                else if row["role"].string != "owner", user.id != session.user?.id {
                                    Menu("管理成员") {
                                        if community.raw["my_role"].string == "owner" { Button(row["role"].string == "admin" ? "撤销管理员" : "设为管理员") { prepare(base + "/members/\(user.id)", method: "PUT", body: .object(["role": .text(row["role"].string == "admin" ? "member" : "admin")])) } }
                                        Button("移出社群", role: .destructive) { prepare(base + "/members/\(user.id)") }
                                        Button("封禁", role: .destructive) { prepare(base + "/bans", method: "POST", body: .object(["user_id": .id(user.id)])) }
                                    }
                                }
                            }.font(.caption).buttonStyle(.glass)
                        }
                    }
                }
            }
            if more { Button("加载更多") { Task { await load(append: true) } }.disabled(loading) }
            if tab == "announcements" && community.isManager {
                Section("发布公告") {
                    TextField("标题", text: $title); TextField("公告内容", text: $content, axis: .vertical)
                    Button("发布") { Task { await announce() } }.disabled(title.isEmpty || loading)
                }
            }
            if community.raw["my_role"].string == "owner" { Button("解散社群", role: .destructive) { prepare(base) } }
            if loading { ProgressView() }
        }.buttonStyle(.plain).disabled(acting).navigationTitle("社群信息").task(id: tab) { await load() }.refreshable { await load() }
            .confirmationDialog("确定执行此操作？", isPresented: $confirm, titleVisibility: .visible) { Button("确定", role: actionMethod == "DELETE" ? .destructive : nil) { Task { await act() } } }
    }
    private func prepare(_ path: String, method: String = "DELETE", body: JSON? = nil) { guard !acting else { return }; actionPath = path; actionMethod = method; actionBody = body; confirm = true }
    private func load(append: Bool = false) async {
        loading = true; defer { loading = false }; let selection = tab
        do {
            let next = append ? offset + 50 : 0
            let j = try await session.api.request(base + "/" + selection, query: ["limit": "50", "offset": String(next)])
            guard selection == tab else { return }
            let values = j.list("members", "announcements", "requests", "join_requests", "bans", "items")
            rows = (append ? rows : []) + values; offset = next; more = values.count >= 50; error = nil
        } catch { if selection == tab { self.error = error.localizedDescription } }
    }
    private func act() async {
        guard !acting else { return }; acting = true; defer { acting = false }
        let path = actionPath, method = actionMethod, body = actionBody
        do { _ = try await session.api.request(path, method: method, body: body); if path == base { dismiss() } else { await load() } }
        catch { self.error = error.localizedDescription }
    }
    private func announce() async {
        loading = true
        do { _ = try await session.api.request(base + "/announcements", method: "POST", body: .object(["title": .text(title), "content": .text(content), "is_pinned": .bool(false)])); title = ""; content = ""; await load() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
