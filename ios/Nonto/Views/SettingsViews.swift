import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("nonto.native.appearance") private var appearance = "system"
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.blue
    @State private var error: String?
    @State private var confirmLogout = false
    @State private var cacheCleared = false
    @State private var loggingOut = false
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                AccentColorMenu(selection: $accent)
            }
            Section("账号") {
                RouteButton(.personalInformation) { Text("个人信息与权限") }
                RouteButton(.privacySettings) { Text("隐私设置") }
                RouteButton(.notificationSettings) { Text("消息提醒") }
                RouteButton(.password) { Text("修改密码") }
                RouteButton(.blockedUsers) { Text("屏蔽列表") }
                RouteButton(.identity) { Text("身份认证") }
            }
            Section("内容") {
                RouteButton(.followedTopics) { Text("我的话题") }
                RouteButton(.communities(mine: true)) { Text("我的社群") }
                RouteButton(.comics) { Text("漫展") }
                Button("清理本机缓存") {
                    do { try LocalCache.clear(userID: session.user?.id ?? 0); ImageRepository.shared.clear(); URLCache.shared.removeAllCachedResponses(); error = nil; cacheCleared = true }
                    catch { self.error = error.localizedDescription }
                }
            }
            Section("关于南图") {
                Link("官方网站", destination: ComplianceProfile.current.websiteURL)
                RouteButton(.contact) { Text("联系与投诉") }
                RouteButton(.policy("privacy")) { Text("隐私政策") }
                RouteButton(.policy("terms")) { Text("服务条款") }
                RouteButton(.policy("community")) { Text("社区规范") }
                NavigationLink("表情资源与许可") { NotoEmojiCreditsView() }
                Link("源代码", destination: URL(string: "https://github.com/junhua-huang/NonToFlutter/tree/ios")!)
                LabeledContent("版本", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            }
            FilingDisclosureSection()
            Section {
                if loggingOut { ProgressView("正在退出登录…") }
                Button("退出登录", role: .destructive) { confirmLogout = true }.disabled(loggingOut)
                    .alert("退出当前账号？", isPresented: $confirmLogout) {
                        Button("取消", role: .cancel) {}
                        Button("退出登录", role: .destructive) { Task { await logout() } }
                    } message: { Text("退出后需要重新登录才能继续使用账号功能。") }
                RouteButton(.deleteAccount) { Text("注销账号") }.foregroundStyle(.red)
            }
            ErrorBanner(text: error)
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .alert("本机缓存已清理", isPresented: $cacheCleared) { Button("好", role: .cancel) {} }
    }
    private func logout() async {
        guard !loggingOut else { return }
        loggingOut = true; defer { loggingOut = false }
        do { try await session.logout() } catch { self.error = error.localizedDescription }
    }
}

struct PrivacySettingsView: View {
    @Environment(\.appAccent) private var accent
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
            if saved { Text("已保存").foregroundStyle(accent.textColor) }
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
            session.defaultVisibility = visibility; saved = true; error = nil; try? await session.refreshProfile()
        } catch { self.error = error.localizedDescription }
    }
}
struct NotificationSettingsView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var push = APNsService.shared
    @State private var pushEnabled = false
    @State private var message = false
    @State private var sound = false
    @State private var loaded = false
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section("系统通知") {
                Text(push.status).foregroundStyle(.secondary)
                Button("重试推送连接") { push.retry() }
                ErrorBanner(text: push.error)
                Button("开启系统通知") { Task { do { try await NativeNotifications.shared.requestAuthorization() } catch { self.error = error.localizedDescription } } }
                Button("发送远程测试通知") { Task { do { try await push.testRemote() } catch { self.error = error.localizedDescription } } }.disabled(!push.bound)
                Button("发送本地测试通知") { Task { do { try await NativeNotifications.shared.test() } catch { self.error = error.localizedDescription } } }
                if let url = URL(string: UIApplication.openSettingsURLString) { Link("打开系统设置", destination: url) }
            }
            Section("提醒偏好") {
                Toggle("系统推送", isOn: $pushEnabled)
                Toggle("消息提醒", isOn: $message)
                Toggle("通知声音", isOn: $sound)
            }.disabled(!loaded || busy || loading)
            if loading { ProgressView("正在读取设置…") }
            if busy { ProgressView("正在保存…") }
            Button("保存") { Task { await save() } }.disabled(!loaded || busy)
            if saved { Text("已保存").foregroundStyle(accent.textColor) }
            ErrorBanner(text: error) { Task { await load() } }
        }.disabled(busy).navigationTitle("消息提醒").task { if !loaded { await load() } }
            .onChange(of: [pushEnabled, message, sound]) { _, _ in saved = false }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let j = try await session.api.request("/notifications/settings"); let s = j["settings"].or(j)
            pushEnabled = s["notify_push"].bool; message = s["notify_message"].bool; sound = s["notify_sound"].bool; loaded = true
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard !busy else { return }
        busy = true; saved = false; error = nil; defer { busy = false }
        do { _ = try await session.api.request("/notifications/settings", method: "PUT", body: .object(["notify_push": .bool(pushEnabled), "notify_message": .bool(message), "notify_sound": .bool(sound)])); NativeNotifications.shared.pushEnabled = pushEnabled; NativeNotifications.shared.messageEnabled = message; NativeNotifications.shared.soundEnabled = sound; session.syncPush(); saved = true }
        catch { self.error = error.localizedDescription }
    }
}
struct PasswordView: View {
    @Environment(\.appAccent) private var accent
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
            if saved { Text("密码已修改").foregroundStyle(accent.textColor) }
            Button("修改密码") { Task { await save() } }.disabled(busy || old.isEmpty || new.count < 8 || new != repeatPassword)
            if busy { ProgressView("正在修改…") }
        }.disabled(busy).scrollDismissesKeyboard(.interactively).navigationTitle("修改密码")
    }
    private func save() async {
        guard !busy else { return }
        busy = true; saved = false; error = nil; defer { busy = false }
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
            Section {
                Text("确认后将向服务器申请注销当前账号。与账号关联的信息、上传文件及依法保留的记录，按照隐私说明中的删除与保留规则处理；本机草稿、发送队列与账号缓存也会清理。注销操作无法撤销。")
                    .foregroundStyle(.secondary)
                RouteButton(.policy("privacy")) { Text("查看删除与保留说明") }
                TextField("请输入“注销”确认", text: $confirmation)
            }
            ErrorBanner(text: error)
            Button("永久注销账号", role: .destructive) { confirm = true }.disabled(confirmation != "注销" || busy)
            if busy { ProgressView("正在处理注销…") }
        }.disabled(busy).navigationTitle("注销账号").confirmationDialog("申请注销账号？此操作无法撤销。", isPresented: $confirm, titleVisibility: .visible) {
            Button("永久注销", role: .destructive) {
                Task {
                    busy = true; defer { busy = false }
                    do {
                        let userID = session.user?.id ?? 0
                        _ = try await session.api.request("/auth/account", method: "DELETE")
                        try await session.logout()
                        try? AccountLocalData.clear(userID: userID)
                    }
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
        }.navigationTitle("屏蔽列表").task { await resource.loadIfNeeded() }.refreshable { await resource.load(reset: true) }
    }
    private func unblock(_ id: Int) async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/blocks/\(id)", method: "DELETE"); resource.apply(id: id, patch: nil); session.postRevision += 1 }
        catch { self.error = error.localizedDescription }
    }
}
struct PolicyView: View {
    let kind: String
    var body: some View {
        let text = ComplianceProfile.current.document(kind)
        let document = LegalDocument(rawValue: kind)
        let sections = PolicySection.parse(text)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let document {
                        Text(document.summary).font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph).font(.body).lineSpacing(5).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).id(section.id)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(LegalDocument.allCases.filter { $0.rawValue != kind }) { related in
                            NavigationLink(related.title) { AnyView(PolicyView(kind: related.rawValue)) }
                        }
                        NavigationLink("联系与投诉") { AnyView(ContactAndComplaintsView()) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: 700, alignment: .leading).padding(24).frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(sections) { section in
                            Button(section.title) { withAnimation { proxy.scrollTo(section.id, anchor: .top) } }
                        }
                    } label: { Label("目录", systemImage: "list.bullet") }
                    ShareLink(item: text) { Label("分享全文", systemImage: "square.and.arrow.up") }
                }
            }
        }.navigationTitle(LegalDocument(rawValue: kind)?.title ?? "说明").navigationBarTitleDisplayMode(.inline)
    }
}
