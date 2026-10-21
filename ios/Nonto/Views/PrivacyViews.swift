import SwiftUI
import UIKit

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
                    Text("请先阅读服务条款和隐私政策，再决定是否使用账号与社交服务。")
                    if !profile.reviewed {
                        Label("开发测试版：服务规则尚未完成审核，当前仅供开发测试。", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("账号服务会处理邮箱、账号资料、你主动发送的内容和服务安全信息。照片与视频仅在你选择时读取；通知在你开启时申请，不影响文字功能。")
                    NavigationLink("阅读隐私政策") { PolicyView(kind: "privacy") }
                    NavigationLink("阅读服务条款") { PolicyView(kind: "terms") }
                    NavigationLink("阅读社区规范") { PolicyView(kind: "community") }
                    NavigationLink("联系与投诉") { ContactAndComplaintsView() }
                    if declined {
                        Text("当前保留离线说明页面。你可以稍后重新决定是否继续。不会因此注销现有账号。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("重新查看使用说明") { declined = false }.buttonStyle(.glass)
                    } else {
                        Button { consent.accept() } label: {
                            Text(profile.reviewed ? "同意服务条款与隐私政策并继续" : "同意说明，继续开发测试").frame(maxWidth: .infinity).padding(.vertical, 6)
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
                DisclosureGroup("账号与资料") {
                    Text("邮箱、用户名、你填写的昵称、简介和头像，用于登录、安全验证和主页展示。")
                    Text("可在编辑资料和隐私设置中管理；邮箱是否公开由你选择。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DisclosureGroup("内容、聊天与互动") {
                    Text("动态、评论、私信、社群消息、搜索词及互动记录，用于发布、通信、搜索、推荐和未读同步。")
                    Text("私信由服务器处理，当前不提供端到端加密。请勿发送密码、验证码或无关证件。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DisclosureGroup("照片、视频与通知") {
                    Text("仅处理你选中的媒体；系统推送使用 Apple 推送令牌和随机安装标识。保存图片时才申请相册添加权限。")
                    Text("拒绝媒体或通知权限不影响不相关功能。可在系统设置和消息提醒页管理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DisclosureGroup("安全、举报与支持") {
                    Text("相关账号、内容编号、必要访问记录和你提交的说明，用于账号安全、问题排查、举报与权利请求处理。")
                    Text("角色认证材料请遮盖无关的身份证、银行卡、住址及他人敏感信息。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("查看和管理") {
                RouteButton(.policy("privacy")) { Text("隐私政策与信息处理规则") }
                RouteButton(.privacySettings) { Text("隐私与资料可见范围") }
                RouteButton(.notificationSettings) { Text("通知权限与提醒") }
                RouteButton(.reportHistory) { Text("举报处理记录") }
                RouteButton(.contact) { Text("查阅、复制、更正或删除信息申请") }
                RouteButton(.policy("community")) { Text("社区规范与申诉方式") }
            }
            Section {
                Button("撤回同意并退出登录", role: .destructive) { confirmWithdrawal = true }.disabled(busy)
                RouteButton(.deleteAccount) { Text("注销账号") }
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

struct ContactAndComplaintsView: View {
    @State private var kind = SupportRequestKind.support
    @State private var detail = ""
    @State private var copiedEmail = false
    private let profile = ComplianceProfile.current
    var body: some View {
        Form {
            Section("联系南图") {
                Text(profile.value("contactEmail")).lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                Text("使用反馈、举报投诉、个人信息申请和处置申诉，均可通过此邮箱联系。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("准备请求") {
                Picker("请求类型", selection: $kind) {
                    ForEach(SupportRequestKind.allCases) { item in Text(item.title).tag(item) }
                }
                Text(kind.guidance).font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $detail).frame(minHeight: 140)
                    .accessibilityLabel("问题描述或申请内容").accessibilityIdentifier("legal.contact.detail")
                Text("本页只在本机整理文字，不会自动提交，也不会自动附带账号、聊天记录或设备资料。请勿填写密码、验证码或无关敏感信息。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("发送方式") {
                if let url = profile.requestMailURL(kind: kind, detail: detail) {
                    Link(destination: url) { Label("打开邮件并检查后发送", systemImage: "envelope") }
                }
                if profile.contactURL != nil {
                    Button {
                        UIPasteboard.general.string = profile.value("contactEmail"); copiedEmail = true
                    } label: { Label("复制联系邮箱", systemImage: "doc.on.doc") }
                }
                ShareLink(item: kind.message(detail: detail)) { Label("分享或保存请求文字", systemImage: "square.and.arrow.up") }
                Text("没有配置系统邮件时，可复制邮箱到自己的邮件应用发送。打开邮件或分享不代表请求已经送达；请核对收件地址并完成发送。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("提交前了解") {
                Text("处理账号信息请求时，可能需要核验与你请求相称的身份信息。举报不代表投诉成立；如对结果有异议，可说明原编号和复核理由。")
                NavigationLink("查看个人信息处理规则") { AnyView(PolicyView(kind: "privacy")) }
                NavigationLink("查看社区规范") { AnyView(PolicyView(kind: "community")) }
            }
        }.navigationTitle("联系与投诉").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .alert("联系邮箱已复制", isPresented: $copiedEmail) { Button("好", role: .cancel) {} }
    }
}

/// The website's public disclosure is never presented as an APP filing.
struct FilingDisclosureSection: View {
    private let profile = ComplianceProfile.current
    var body: some View {
        Section {
            if !profile.value("appFilingNumber").isEmpty {
                Link("APP 备案：\(profile.value("appFilingNumber"))", destination: URL(string: "https://beian.miit.gov.cn/")!)
            } else {
                LabeledContent("APP 备案", value: "尚未核实")
            }
            let website = profile.values["websiteFiling"] ?? .null
            if !website["number"].string.isEmpty {
                Link(destination: URL(string: "https://beian.miit.gov.cn/")!) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("官网公示的网站备案")
                        Text(website["number"].string).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("备案信息") } footer: {
            Text("网站公示号码尚未完成官方核验，不代表南图 APP 已完成备案。可前往工信部系统查询。")
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
