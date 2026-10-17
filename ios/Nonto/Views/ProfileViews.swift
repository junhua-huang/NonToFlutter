import SwiftUI
import PhotosUI

struct ProfileView: View {
    let userID: Int
    @EnvironmentObject private var session: AppSession
    @State private var person: Person?
    @State private var friendship: JSON = .null
    @State private var conversation: Conversation?
    @State private var editing = false
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var confirmUnfriend = false
    @State private var error: String?
    @State private var busy = false
    @State private var liked = false
    private var isOwn: Bool { session.user?.id == userID }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    if let user = person ?? (isOwn ? session.user : nil) {
                        if let url = URL(string: user.cover), !user.cover.isEmpty {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.brand.opacity(0.1) }.frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        HStack {
                            AvatarView(url: user.avatar, name: user.name, size: 72)
                            VStack(alignment: .leading, spacing: 5) { Text(user.name).font(.title2.bold()); Text("@\(user.username)").foregroundStyle(.secondary) }
                            Spacer()
                            if isOwn { Button("编辑") { editing = true }.buttonStyle(.glass) }
                        }
                        if !user.verifiedLabels.isEmpty { Label(user.verifiedLabels.joined(separator: " · "), systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.brand) }
                        if !user.bio.isEmpty { Text(user.bio).textSelection(.enabled) }
                        if let email = user.publicEmail, !email.isEmpty { Text(email).font(.caption).foregroundStyle(.secondary) }
                        if !isOwn {
                            HStack {
                                Button(friendLabel) { Task { await friendAction() } }.buttonStyle(.glassProminent).disabled(busy || friendship.isNull)
                                Button("私信") { Task { await chat() } }.buttonStyle(.glass).disabled(busy)
                            }
                        }
                    } else if error == nil { ProgressView() }
                    ErrorBanner(text: error) { Task { await load() } }
                }.padding()
            }.frame(maxHeight: 320)
            Picker("动态类型", selection: $liked) { Text("动态").tag(false); Text("赞过").tag(true) }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            PostList(session: session, path: "/posts/user/\(userID)\(liked ? "/liked" : "")").id(liked)
        }.navigationTitle(isOwn ? "我的主页" : "个人主页").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isOwn { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置") }
                else {
                    Menu {
                        Button("举报用户", systemImage: "flag") { reporting = true }
                        Button("屏蔽用户", systemImage: "person.slash", role: .destructive) { confirmBlock = true }
                        if friendship["status"].string == "accepted" { Button("删除好友", role: .destructive) { confirmUnfriend = true } }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .task { await load() }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { EditProfileView() }
            .sheet(isPresented: $reporting) { ReportView(kind: "user", targetID: userID) }
            .navigationDestination(item: $conversation) { ChatRoomView(conversation: $0) }
            .confirmationDialog("屏蔽后将减少彼此的互动，确定继续？", isPresented: $confirmBlock) {
                Button("屏蔽用户", role: .destructive) { Task { await block() } }
            }
            .confirmationDialog("删除这位好友？", isPresented: $confirmUnfriend) {
                Button("删除好友", role: .destructive) { Task { await unfriend() } }
            }
    }
    private var friendLabel: String {
        switch friendship["status"].string {
        case "accepted": return "已是好友"
        case "pending": return friendship["friendship"]["sender_id"].int == session.user?.id ? "取消申请" : "接受申请"
        default: return "添加好友"
        }
    }
    private func load() async {
        do {
            let j = try await session.api.request(isOwn ? "/auth/profile" : "/auth/users/\(userID)")
            person = Person(j["user"].or(j)); error = nil
            if !isOwn { friendship = try await session.api.request("/friends/status/\(userID)") }
        } catch { self.error = error.localizedDescription }
    }
    private func friendAction() async {
        busy = true; defer { busy = false }
        do {
            if friendship["status"].string == "accepted" { return }
            if friendship["status"].string == "pending" {
                let request = friendship["friendship"]
                if request["sender_id"].int == session.user?.id { _ = try await session.api.request("/friends/request/\(request["id"].int)", method: "DELETE") }
                else { _ = try await session.api.request("/friends/request/\(request["id"].int)/accept", method: "POST") }
            } else { _ = try await session.api.request("/friends/request", method: "POST", body: .object(["receiver_id": .id(userID)])) }
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func chat() async {
        busy = true; defer { busy = false }
        do {
            let j = try await session.api.request("/chat/conversations/\(userID)")
            var value = j["conversation"].or(j)
            if value["other_user"].isNull { value["other_user"] = person?.raw ?? .null }
            guard value["id"].int > 0 else { throw APIError(status: 0, message: "无法打开会话") }
            conversation = Conversation(value)
        } catch { self.error = error.localizedDescription }
    }
    private func block() async {
        do { _ = try await session.api.request("/blocks", method: "POST", body: .object(["user_id": .id(userID)])); session.postRevision += 1; error = "已屏蔽此用户" }
        catch { self.error = error.localizedDescription }
    }
    private func unfriend() async {
        do { _ = try await session.api.request("/friends/\(userID)", method: "DELETE"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

// Navigation values contain immutable wire snapshots; identity is the server ID.
extension Conversation: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct EditProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var avatar: PhotosPickerItem?
    @State private var cover: PhotosPickerItem?
    @State private var initialized = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") { TextField("显示名称", text: $name); TextField("介绍一下自己", text: $bio, axis: .vertical).lineLimit(3...8) }
                Section("照片") {
                    if let user = session.user { AvatarView(url: user.avatar, name: user.name, size: 72) }
                    PhotosPicker("更换头像", selection: $avatar, matching: .images)
                    PhotosPicker("更换封面", selection: $cover, matching: .images)
                }.disabled(busy)
                if busy { ProgressView("正在保存…") }
                ErrorBanner(text: error)
            }.navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy) }
                }.interactiveDismissDisabled(busy)
                .onAppear { if !initialized { initialized = true; name = session.user?.name ?? ""; bio = session.user?.bio ?? "" } }
                .task(id: avatar) { if let avatar { await upload(avatar, type: "avatar") } }
                .task(id: cover) { if let cover { await upload(cover, type: "cover") } }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/auth/profile", method: "PUT", body: .object(["display_name": .text(name), "bio": .text(bio)])); try await session.refreshProfile(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func upload(_ pick: PhotosPickerItem, type: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let media = try await MediaLoader.load(pick); _ = try await session.api.upload(media.data, filename: media.name, mime: media.mime, type: type); try await session.refreshProfile() }
        catch { self.error = error.localizedDescription }
    }
}

struct FriendRequestRecord: Record { var raw: JSON; init(_ raw: JSON) { self.raw = raw } }
struct FriendsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var friends: PagedResource<Person>
    @StateObject private var requests: PagedResource<FriendRequestRecord>
    @State private var error: String?
    @State private var busy = false
    init(session: AppSession) {
        let uid = session.user?.id ?? 0
        _friends = StateObject(wrappedValue: PagedResource(api: session.api, path: "/friends/", keys: ["friends", "users", "items"], userID: uid, paginated: false))
        _requests = StateObject(wrappedValue: PagedResource(api: session.api, path: "/friends/requests/pending", keys: ["requests", "items"], userID: uid, paginated: false))
    }
    var body: some View {
        List {
            ErrorBanner(text: error)
            Section("好友申请") {
                ForEach(requests.items) { item in
                    let sender = Person(item.raw["sender"])
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink { ProfileView(userID: sender.id) } label: { PersonRow(person: sender) }
                        HStack { Button("接受") { Task { await respond(item.id, accept: true) } }.buttonStyle(.glassProminent); Button("拒绝") { Task { await respond(item.id, accept: false) } }.buttonStyle(.glass) }.disabled(busy)
                    }
                }
                if requests.loading || requests.error != nil { ResourceFooter(resource: requests) }
            }
            Section("我的好友") {
                ForEach(friends.items) { person in NavigationLink { ProfileView(userID: person.id) } label: { PersonRow(person: person) } }
                ResourceFooter(resource: friends)
            }
        }.navigationTitle("好友").task { await load() }.refreshable { await load() }
    }
    private func load() async { await friends.load(reset: true); await requests.load(reset: true) }
    private func respond(_ id: Int, accept: Bool) async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/friends/request/\(id)/\(accept ? "accept" : "reject")", method: "POST"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct ReportView: View {
    let kind: String
    let targetID: Int
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("举报原因") { TextField("请描述需要反馈的问题", text: $reason, axis: .vertical).lineLimit(5...12) }
                ErrorBanner(text: error)
            }.navigationTitle("举报").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("提交") { Task { await submit() } }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.interactiveDismissDisabled(busy)
        }
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/reports/\(kind)", method: "POST", body: .object(["\(kind)_id": .id(targetID), "reason": .text(reason)])); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
