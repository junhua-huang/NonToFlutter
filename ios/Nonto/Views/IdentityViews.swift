import SwiftUI
import PhotosUI

struct IdentityCenterView: View {
    @EnvironmentObject private var session: AppSession
    @State private var applications: [JSON] = []
    @State private var applying = false
    @State private var error: String?
    @State private var loading = false
    @State private var page = 1
    @State private var more = false
    var body: some View {
        List {
            Section { Button("申请认证身份", systemImage: "checkmark.seal") { applying = true } }
            Section("申请记录") {
                ForEach(Array(applications.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(row["role_label"].or(row["role"]["label"]).string).font(.headline); Spacer(); Text(status(row["status"].string)).font(.caption).foregroundStyle(Color.brand) }
                        Text(row["application_text"].or(row["reason"]).string)
                        if !row["review_comment"].or(row["admin_reason"]).string.isEmpty { Text("审核意见：\(row["review_comment"].or(row["admin_reason"]).string)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                if more { Button("加载更多") { Task { await load(append: true) } }.disabled(loading) }
            }
            ErrorBanner(text: error)
            if loading { ProgressView() }
        }.navigationTitle("身份认证").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $applying, onDismiss: { Task { await load() } }) { IdentityApplicationView() }
    }
    private func status(_ s: String) -> String {
        switch s { case "approved", "verified": return "已认证"; case "rejected": return "未通过"; case "suspended": return "已暂停"; case "needs_more_info": return "需补充材料"; default: return "审核中" }
    }
    private func load(append: Bool = false) async {
        loading = true; defer { loading = false }
        do { let next = append ? page + 1 : 1; let j = try await session.api.request("/roles/applications", query: ["page": String(next), "per_page": "20"]); let rows = j.list("applications", "items"); applications = (append ? applications : []) + rows; page = next; more = rows.count >= 20; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
struct IdentityApplicationView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var roles: [JSON] = []
    @State private var role = ""
    @State private var reason = ""
    @State private var portfolio = ""
    @State private var contact = ""
    @State private var note = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("申请身份", selection: $role) { ForEach(Array(roles.enumerated()), id: \.offset) { _, row in Text(row["label"].string).tag(row["name"].string) } }
                TextField("申请说明", text: $reason, axis: .vertical).lineLimit(4...10)
                TextField("作品链接，每行一个", text: $portfolio, axis: .vertical).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("联系方式", text: $contact)
                TextField("补充说明", text: $note, axis: .vertical)
                PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .images) { Label("证明材料（\(picks.count)/9）", systemImage: "photo.on.rectangle") }
                ErrorBanner(text: error)
                if busy { ProgressView("正在提交…") }
            }.disabled(busy).navigationTitle("申请认证").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("提交") { Task { await submit() } }.disabled(busy || role.isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.interactiveDismissDisabled(busy).task {
                do { let j = try await session.api.request("/roles"); roles = j.list("roles", "items"); role = roles.first?["name"].string ?? "" }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do {
            let links = portfolio.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard links.allSatisfy({ guard let u = URL(string: $0) else { return false }; return ["https", "http"].contains(u.scheme ?? "") && u.host != nil }) else { throw APIError(status: 0, message: "请填写有效的作品网址") }
            var urls: [String] = []
            for pick in picks { let m = try await MediaLoader.load(pick); urls.append(try await session.api.upload(m.data, filename: m.name, mime: m.mime)) }
            _ = try await session.api.request("/roles/apply", method: "POST", body: .object([
                "role_name": .text(role), "application_text": .text(reason), "reason": .text(reason),
                "proof_images": .array(urls.map(JSON.text)), "portfolio_links": .array(links.map(JSON.text)),
                "contact_info": .text(contact), "extra_note": .text(note)]))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
