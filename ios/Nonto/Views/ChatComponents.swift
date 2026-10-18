import SwiftUI

struct ChatMessageRow: View {
    let row: ChatTimeline.Row
    let community: Bool
    let showsReceipt: Bool
    let onQuote: (ChatMessage) -> Void
    let onRecall: (ChatMessage) -> Void
    @EnvironmentObject private var session: AppSession
    private var message: ChatMessage { row.message }
    private var mine: Bool { message.senderID == session.user?.id }
    private var sender: Person { Person(message.raw["sender"].or(message.raw["user"])) }
    var body: some View {
        VStack(spacing: 6) {
            if row.showsTimestamp, let date = message.date {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            HStack(alignment: .top, spacing: 8) {
                if mine { Spacer(minLength: 48) }
                else if community {
                    if row.startsRun {
                        NavigationLink { ProfileView(userID: message.senderID) } label: {
                            AvatarView(url: sender.avatar, name: sender.name, size: 30)
                        }.accessibilityLabel("查看\(sender.name)的资料")
                    } else { Color.clear.frame(width: 30, height: 1).accessibilityHidden(true) }
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    if community && !mine && row.startsRun {
                        Text(sender.name.isEmpty ? "群成员" : sender.name).font(.caption).foregroundStyle(.secondary)
                    }
                    bubble.contextMenu {
                        if !message.recalled {
                            if !message.content.isEmpty {
                                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                            }
                            if community { Button("引用", systemImage: "quote.bubble") { onQuote(message) } }
                            if mine && community {
                                Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { onRecall(message) }
                            }
                        }
                        if let date = message.date { Text(date, format: .dateTime.year().month().day().hour().minute().second()) }
                    }
                    if mine && showsReceipt && !message.recalled {
                        Text(message.raw["is_read"].bool ? "已读" : "已发送").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
        }.padding(.horizontal).padding(.top, row.startsRun ? 6 : 0)
    }
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.raw["quote_preview"].string.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.brand).frame(width: 3)
                    Text(message.raw["quote_preview"].string).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if message.recalled { Text("消息已撤回").font(.caption).foregroundStyle(.secondary) }
            else if message.kind == "image" { MediaView(images: [message.media], video: "").frame(maxWidth: 230) }
            else if message.kind == "video" { MediaView(images: [], video: message.media).frame(maxWidth: 250) }
            else if message.kind == "post", message.raw["related_id"].int > 0 {
                NavigationLink { PostDetailView(session: session, postID: message.raw["related_id"].int) } label: {
                    Label(message.content.isEmpty ? "查看动态" : message.content, systemImage: "doc.richtext").lineLimit(4)
                }
            } else if message.kind == "file", let url = URL(string: message.media), url.scheme == "https" {
                Link(message.content.isEmpty ? "打开文件" : message.content, destination: url)
            } else { Text(message.content).textSelection(.enabled) }
            if !message.recalled && ["image", "video"].contains(message.kind) && !message.content.isEmpty {
                Text(message.content).textSelection(.enabled)
            }
        }.padding(12)
            .background(mine ? Color.brand.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ChatPendingRow: View {
    let item: PendingMessage
    let sending: Bool
    let blocked: Bool
    let retry: () -> Void
    let remove: () -> Void
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if let media = item.media, item.kind == "image" {
                    MediaView(images: [media], video: "").frame(maxWidth: 230)
                } else if item.kind == "video" { Label("视频", systemImage: "video").padding(12) }
                if !item.content.isEmpty { Text(item.content).font(.body).textSelection(.enabled).padding(12) }
                if let failure = item.failure {
                    Label("未发送", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(failure).foregroundStyle(.secondary)
                    HStack {
                        Button("重试", action: retry).buttonStyle(.glass)
                        Button("移除", role: .destructive, action: remove).buttonStyle(.glass)
                    }.controlSize(.small)
                } else if sending { ProgressView("正在发送…") }
                else {
                    Label(blocked ? "等待上一条消息重试" : "等待发送", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Button("取消发送", role: .destructive, action: remove)
                }
            }.font(.caption).padding(10)
                .background(Color.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }.padding(.horizontal).padding(.top, 6)
    }
}

/// Media stays local until Send; failed uploads retain the preview for retry.
struct ChatAttachmentSheet: View {
    let media: SelectedMedia
    let api: APIClient
    let store: ChatStore
    let quoteID: Int?
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var submitting = false
    @State private var error: String?
    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var uploadedURL: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if media.isVideo {
                        if let videoURL { NativeVideo(url: videoURL).frame(height: 300) }
                        else { ProgressView("正在准备视频…").frame(height: 300) }
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 380).accessibilityLabel("待发送的照片")
                    } else { ProgressView().frame(height: 200) }
                    TextField("添加说明（可选）", text: $caption, axis: .vertical).lineLimit(1...5)
                        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16)).disabled(submitting)
                    ErrorBanner(text: error)
                    if submitting { ProgressView("正在上传并发送…") }
                    Button { submitting = true } label: {
                        Label(error == nil ? "发送" : "重试发送", systemImage: "arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.glassProminent).disabled(submitting)
                }.padding()
            }.navigationTitle(media.isVideo ? "发送视频" : "发送照片").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .interactiveDismissDisabled(submitting)
                .task {
                    if media.isVideo {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(media.name)
                        do { try media.data.write(to: url, options: [.atomic, .completeFileProtection]); videoURL = url }
                        catch { self.error = "无法预览视频：\(error.localizedDescription)" }
                    } else { image = UIImage(data: media.data) }
                }
                .task(id: submitting) {
                    guard submitting else { return }
                    let epoch = api.generation
                    defer { submitting = false }
                    error = nil
                    do {
                        let url: String
                        if let uploadedURL { url = uploadedURL }
                        else {
                            url = try await api.upload(media.data, filename: media.name, mime: media.mime)
                            uploadedURL = url
                        }
                        try Task.checkCancellation()
                        guard epoch == api.generation else { return }
                        guard store.enqueue(content: caption, kind: media.isVideo ? "video" : "image", media: url, quoteID: quoteID) else {
                            throw APIError(status: 0, message: "无法加入发送队列，请重试")
                        }
                        onSent(); dismiss()
                    } catch {
                        if !Task.isCancelled, epoch == api.generation { self.error = error.localizedDescription }
                    }
                }
                .onDisappear { if let videoURL { try? FileManager.default.removeItem(at: videoURL) } }
        }
    }
}
