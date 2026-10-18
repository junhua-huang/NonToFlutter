import SwiftUI

struct PrivacyWelcomeView: View {
    @EnvironmentObject private var consent: PrivacyConsent
    @State private var declined = false
    private let profile = ComplianceProfile.current
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "hand.raised.circle").font(.system(size: 48)).foregroundStyle(Color.brand)
                    Text(declined ? "你可以先了解南图" : "欢迎使用南图").font(.largeTitle.bold())
                    Text("请先阅读用户协议和隐私说明，再决定是否使用账号与社交服务。")
                    if !profile.reviewed {
                        Label("开发测试版：运营主体与服务器规则待补全，不应向公众提供服务。", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("账号服务会处理邮箱、账号资料、你主动发送的内容和服务安全信息。照片与视频仅在你选择时读取；通知在你开启时申请，不影响文字功能。")
                    NavigationLink("阅读隐私说明") { PolicyView(kind: "privacy") }
                    NavigationLink("阅读用户协议") { PolicyView(kind: "terms") }
                    if let contact = profile.contactURL { Link("联系运营者", destination: contact) }
                    if declined {
                        Text("当前保留离线说明页面。你可以稍后重新决定是否继续。不会因此注销现有账号。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("重新查看使用说明") { declined = false }.buttonStyle(.glass)
                    } else {
                        Button { consent.accept() } label: {
                            Text(profile.reviewed ? "同意协议与隐私说明并继续" : "同意说明，继续开发测试").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.glassProminent)
                        Button("暂不同意，仅查看说明") { declined = true }.buttonStyle(.glass).frame(maxWidth: .infinity)
                    }
                }.padding(28).frame(maxWidth: 560)
            }.frame(maxWidth: .infinity)
        }
    }
}

struct PersonalInformationView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var consent: PrivacyConsent
    @State private var confirmWithdrawal = false
    @State private var busy = false
    @State private var error: String?
    private let profile = ComplianceProfile.current
    var body: some View {
        Form {
            Section("个人信息与使用目的") {
                LabeledContent("账号", value: "邮箱、用户名、资料")
                LabeledContent("社交", value: "动态、评论、消息、搜索与互动")
                LabeledContent("可选功能", value: "选中的媒体、认证材料、推送标识")
                Text("只提供完成当前功能需要的信息。认证材料请勿包含无关的身份证、银行卡或他人敏感信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("查看和管理") {
                NavigationLink("隐私说明与服务提供方") { PolicyView(kind: "privacy") }
                NavigationLink("隐私与资料可见范围") { PrivacySettingsView() }
                NavigationLink("通知权限与提醒") { NotificationSettingsView() }
                NavigationLink("举报处理记录") { ReportHistoryView(session: session) }
                if let contact = profile.contactURL { Link("申请查阅、复制、更正或删除信息", destination: contact) }
                else { Text("运营者的权利申请联系方式尚未配置，本版本尚不具备正式发布条件。").font(.caption).foregroundStyle(.secondary) }
                if let filing = profile.values["appFilingNumber"], !filing.string.isEmpty {
                    Link(filing.string, destination: URL(string: "https://beian.miit.gov.cn/")!)
                }
            }
            Section {
                Button("撤回同意并退出登录", role: .destructive) { confirmWithdrawal = true }.disabled(busy)
                NavigationLink("注销账号") { DeleteAccountView() }
                Text("撤回后停止使用当前账号服务，并返回离线说明页；不会自动删除服务器账号。注销请使用单独的账号注销入口。")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView("正在退出并关闭账号服务…") }
                ErrorBanner(text: error)
            }
        }.navigationTitle("个人信息与权限").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("撤回同意并退出？", isPresented: $confirmWithdrawal, titleVisibility: .visible) {
                Button("撤回并退出", role: .destructive) {
                    Task {
                        guard !busy else { return }; busy = true; defer { busy = false }
                        do { try await session.logout(); consent.revoke() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
    }
}

struct ReportRecord: Record { var raw: JSON; init(_ raw: JSON) { self.raw = raw } }
struct ReportHistoryView: View {
    @StateObject private var resource: PagedResource<ReportRecord>
    init(session: AppSession) {
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/reports/", keys: ["reports", "items"], userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            ForEach(resource.items) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("举报 #\(record.id)").font(.headline)
                        Spacer()
                        Text(status(record.raw["status"].string)).font(.caption).foregroundStyle(Color.brand)
                    }
                    Text(record.raw["reason"].string).textSelection(.enabled)
                    if !record.raw["resolution_note"].string.isEmpty {
                        Text("处理反馈：\(record.raw["resolution_note"].string)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let date = ServerDate.parse(record.raw["created_at"]) { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
            }
            ResourceFooter(resource: resource, emptyTitle: "还没有举报记录", emptyDescription: "你提交的举报和服务端处理状态会显示在这里。", emptyIcon: "flag")
        }.navigationTitle("举报处理记录").task { await resource.loadIfNeeded() }.refreshable { await resource.load(reset: true) }
    }
    private func status(_ value: String) -> String {
        switch value { case "pending": return "待处理"; case "resolved": return "已处理"; case "rejected", "dismissed": return "未采纳"; default: return "处理中" }
    }
}
