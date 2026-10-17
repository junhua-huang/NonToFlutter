import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("nonto.native.appearance") private var appearance = "system"
    @State private var error: String?
    @State private var confirmLogout = false
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            }
            Section("账号") {
                NavigationLink("隐私设置") { PrivacySettingsView() }
                NavigationLink("消息提醒") { NotificationSettingsView() }
                NavigationLink("修改密码") { PasswordView() }
                NavigationLink("屏蔽列表") { BlockedUsersView(session: session) }
                NavigationLink("身份认证") { IdentityCenterView() }
            }
            Section("内容") {
                NavigationLink("我的话题") { FollowedTopicsView(session: session) }
                NavigationLink("我的社群") { CommunityListView(session: session, mine: true) }
                NavigationLink("漫展") { ComicListView() }
                Button("清理本机缓存") {
                    do { try LocalCache.clear(userID: session.user?.id ?? 0); error = "本机缓存已清理" }
                    catch { self.error = error.localizedDescription }
                }
            }
            Section("关于南图") {
                NavigationLink("隐私政策") { PolicyView(kind: "privacy") }
                NavigationLink("用户协议") { PolicyView(kind: "terms") }
                Link("源代码", destination: URL(string: "https://github.com/junhua-huang/NonToFlutter/tree/ios")!)
                LabeledContent("版本", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            }
            Section {
                Button("退出登录", role: .destructive) { confirmLogout = true }
                NavigationLink("注销账号") { DeleteAccountView() }.foregroundStyle(.red)
            }
            ErrorBanner(text: error)
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("退出当前账号？", isPresented: $confirmLogout) { Button("退出登录", role: .destructive) { do { try session.logout() } catch { self.error = error.localizedDescription } } }
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var profile = "public"
    @State private var visibility = "public"
    @State private var email = false
    @State private var searchable = true
    @State private var requests = "everyone"
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section {
                Picker("主页可见范围", selection: $profile) { Text("公开").tag("public"); Text("好友").tag("friends_only"); Text("仅自己").tag("private") }
                Picker("默认动态范围", selection: $visibility) { Text("公开").tag("public"); Text("仅好友").tag("friends") }
                Toggle("展示邮箱", isOn: $email)
                Toggle("允许被搜索", isOn: $searchable)
                Picker("好友申请", selection: $requests) { Text("所有人").tag("everyone"); Text("好友的好友").tag("friends_of_friends"); Text("不允许").tag("none") }
            }.disabled(!loaded || busy)
            if !loaded && error == nil { ProgressView() }
            ErrorBanner(text: error) { Task { await load() } }
            if saved { Text("已保存").foregroundStyle(Color.brand) }
            Button("保存设置") { Task { await save() } }.disabled(!loaded || busy)
        }.navigationTitle("隐私设置").task { await load() }
    }
    private func load() async {
        do {
            let j = try await session.api.request("/auth/privacy")
            profile = j["profile_visibility"].string.isEmpty ? "public" : j["profile_visibility"].string
            visibility = ["friends", "friends_only"].contains(j["post_default_visibility"].string) ? "friends" : "public"
            email = j["show_email"].bool; searchable = j["allow_search"].isNull || j["allow_search"].bool
            requests = j["allow_friend_requests"].string.isEmpty ? "everyone" : j["allow_friend_requests"].string
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; saved = false; defer { busy = false }
        do {
            _ = try await session.api.request("/auth/privacy", method: "PUT", body: .object([
                "profile_visibility": .text(profile), "post_default_visibility": .text(visibility),
                "show_email": .bool(email), "allow_search": .bool(searchable), "allow_friend_requests": .text(requests)]))
            session.defaultVisibility = visibility; try await session.refreshProfile(); saved = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
struct NotificationSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var message = false
    @State private var sound = false
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section("系统通知") {
                Button("开启系统通知") { Task { do { try await NativeNotifications.shared.requestAuthorization() } catch { self.error = error.localizedDescription } } }
                Button("发送测试通知") { Task { do { try await NativeNotifications.shared.test() } catch { self.error = error.localizedDescription } } }
                if let url = URL(string: UIApplication.openSettingsURLString) { Link("打开系统设置", destination: url) }
            }
            Toggle("消息提醒", isOn: $message)
            Toggle("通知声音", isOn: $sound)
            Button("保存") { Task { await save() } }.disabled(!loaded || busy)
            if saved { Text("已保存").foregroundStyle(Color.brand) }
            ErrorBanner(text: error)
        }.disabled(!loaded || busy).navigationTitle("消息提醒").task {
            do { let j = try await session.api.request("/notifications/settings"); let s = j["settings"].or(j); message = s["notify_message"].bool; sound = s["notify_sound"].bool; loaded = true }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/notifications/settings", method: "PUT", body: .object(["notify_message": .bool(message), "notify_sound": .bool(sound)])); NativeNotifications.shared.messageEnabled = message; NativeNotifications.shared.soundEnabled = sound; saved = true }
        catch { self.error = error.localizedDescription }
    }
}
struct PasswordView: View {
    @EnvironmentObject private var session: AppSession
    @State private var old = ""
    @State private var new = ""
    @State private var repeatPassword = ""
    @State private var error: String?
    @State private var busy = false
    @State private var saved = false
    var body: some View {
        Form {
            SecureField("当前密码", text: $old).textContentType(.password)
            SecureField("新密码（至少 8 位）", text: $new).textContentType(.newPassword)
            SecureField("确认新密码", text: $repeatPassword).textContentType(.newPassword)
            ErrorBanner(text: error)
            if saved { Text("密码已修改").foregroundStyle(Color.brand) }
            Button("修改密码") { Task { await save() } }.disabled(busy || old.isEmpty || new.count < 8 || new != repeatPassword)
        }.navigationTitle("修改密码")
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/auth/change-password", method: "POST", body: .object(["old_password": .text(old), "new_password": .text(new)])); old = ""; new = ""; repeatPassword = ""; saved = true }
        catch { self.error = error.localizedDescription }
    }
}
struct DeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @State private var confirmation = ""
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section { Text("注销会永久删除账号和相关数据，无法撤销。").foregroundStyle(.red); TextField("请输入“注销”确认", text: $confirmation) }
            ErrorBanner(text: error)
            Button("永久注销账号", role: .destructive) { confirm = true }.disabled(confirmation != "注销" || busy)
        }.navigationTitle("注销账号").confirmationDialog("永久删除账号和相关数据？此操作无法撤销。", isPresented: $confirm, titleVisibility: .visible) {
            Button("永久注销", role: .destructive) {
                Task {
                    busy = true; defer { busy = false }
                    do { _ = try await session.api.request("/auth/account", method: "DELETE"); try LocalCache.clear(userID: session.user?.id ?? 0); try session.logout() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
}
struct BlockedRecord: Record {
    var raw: JSON
    init(_ raw: JSON) { self.raw = raw["user"].or(raw) }
}
struct BlockedUsersView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var resource: PagedResource<BlockedRecord>
    @State private var error: String?
    @State private var busy = false
    init(session: AppSession) { _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/blocks", keys: ["blocked_users", "blocks", "users"], userID: session.user?.id ?? 0)) }
    var body: some View {
        List {
            ErrorBanner(text: error)
            ForEach(resource.items) { item in
                HStack { PersonRow(person: Person(item.raw)); Spacer(); Button("解除屏蔽") { Task { await unblock(item.id) } }.disabled(busy).buttonStyle(.glass) }
            }
            ResourceFooter(resource: resource)
        }.navigationTitle("屏蔽列表").task { await resource.load(reset: true) }.refreshable { await resource.load(reset: true) }
    }
    private func unblock(_ id: Int) async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/blocks/\(id)", method: "DELETE"); resource.items.removeAll { $0.id == id }; session.postRevision += 1 }
        catch { self.error = error.localizedDescription }
    }
}
struct PolicyView: View {
    let kind: String
    var body: some View {
        ScrollView {
            Text(text).frame(maxWidth: 700, alignment: .leading).padding(24).textSelection(.enabled)
        }.navigationTitle(kind == "privacy" ? "隐私政策" : "用户协议").navigationBarTitleDisplayMode(.inline)
    }
    private var text: String {
        guard let url = Bundle.main.url(forResource: kind, withExtension: "txt"), let s = try? String(contentsOf: url, encoding: .utf8) else { return "暂时无法读取，请稍后重试。" }
        return s
    }
}
