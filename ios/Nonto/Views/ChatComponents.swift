import SwiftUI
import AVKit

enum ImageMessageCaption {
    private static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    static func text(_ content: String, media: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = media.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            let sourceURL = URL(string: source)
            for match in (links?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).reversed() {
                guard let url = match.url, let sourceURL,
                      url.path == sourceURL.path,
                      sourceURL.host == nil || url.host?.lowercased() == sourceURL.host?.lowercased(),
                      let range = Range(match.range, in: text) else { continue }
                text.removeSubrange(range)
            }
            text = text.replacingOccurrences(of: source, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

enum ChatQuoteSummary {
    static func text(_ message: ChatMessage) -> String {
        guard ["image", "video"].contains(message.kind) else { return message.content }
        let kind = message.kind == "image" ? "[图片]" : "[视频]"
        let caption = ImageMessageCaption.text(message.content, media: message.media)
        return caption.isEmpty ? kind : kind + " " + caption
    }
}

/// Status occupies the visible chat viewport, independent of the bottom-anchored message stack.
struct ChatTimelinePlaceholder: View {
    let loading: Bool
    let error: String?
    let retry: () -> Void
    var body: some View {
        Group {
            if loading { ProgressView("正在加载消息…") }
            else if let error {
                ContentUnavailableView {
                    Label("消息加载失败", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("重试", action: retry).buttonStyle(.glass)
                }
            } else {
                ContentUnavailableView("开始聊天", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("发一条消息，开启对话吧"))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChatMessageRow: View {
    let row: ChatTimeline.Row
    let community: Bool
    let showsReceipt: Bool
    var galleryImages: [String] = []
    var galleryIndex: Int? = nil
    var onMediaPresentation: (Bool) -> Void = { _ in }
    let onQuote: (ChatMessage) -> Void
    let onRecall: (ChatMessage) -> Void
    @EnvironmentObject private var session: AppSession
    @State private var reporting = false
    private var message: ChatMessage { row.message }
    private var caption: String { ["image", "video"].contains(message.kind) ? ImageMessageCaption.text(message.content, media: message.media) : message.content }
    private var bareMedia: Bool { !message.recalled && ["image", "video"].contains(message.kind) }
    private var mine: Bool { message.senderID == session.user?.id }
    private var sender: Person { Person(message.raw["sender"].or(message.raw["user"])) }
    var body: some View {
        VStack(spacing: 6) {
            if row.showsTimestamp, let date = row.date {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            HStack(alignment: .top, spacing: 8) {
                if mine { Spacer(minLength: 48) }
                else if community {
                    if row.startsRun {
                        RouteButton(.profile(message.senderID)) {
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
                            if !caption.isEmpty {
                                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = caption }
                            }
                            Button("引用", systemImage: "quote.bubble") { onQuote(message) }
                            if mine, let date = row.date, Date().timeIntervalSince(date) < 120 {
                                Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { onRecall(message) }
                            }
                            if !mine && message.senderID > 0 {
                                Button("举报消息发送者", systemImage: "flag") { reporting = true }
                            }
                        }
                        if let date = row.date { Text(date, format: .dateTime.year().month().day().hour().minute().second()) }
                    }
                    if mine && showsReceipt && !message.recalled {
                        Text(message.raw["is_read"].bool ? "已读" : "已发送").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
        }.padding(.horizontal).padding(.top, row.startsRun ? 6 : 0)
            .sheet(isPresented: $reporting) {
                ReportView(kind: "user", targetID: message.senderID, context: "聊天消息 #\(message.id)：\n")
            }
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
            else if message.kind == "image" { MediaView(images: [message.media], video: "", thumbnailHeight: 190,
                          galleryImages: galleryImages.isEmpty ? nil : galleryImages,
                          galleryIndex: galleryIndex, fitImage: true,
                          onPresentationChange: onMediaPresentation).frame(maxWidth: 250) }
            else if message.kind == "video" { MediaView(images: [], video: message.media, thumbnailHeight: 190, fitImage: true,
                          onPresentationChange: onMediaPresentation).frame(maxWidth: 250) }
            else if message.kind == "post", message.raw["related_id"].int > 0 {
                RouteButton(.post(message.raw["related_id"].int)) {
                    Label(message.content.isEmpty ? "查看动态" : message.content, systemImage: "doc.richtext").lineLimit(4)
                }
            } else if message.kind == "file", let url = URL(string: message.media), url.scheme == "https" {
                Link(message.content.isEmpty ? "打开文件" : message.content, destination: url)
            } else { Text(message.content).textSelection(.enabled) }
            if !message.recalled && ["image", "video"].contains(message.kind) && !caption.isEmpty {
                Text(caption).textSelection(.enabled)
            }
        }.modifier(ChatBubbleSurface(media: bareMedia, mine: mine))
            .frame(maxWidth: bareMedia ? 250 : nil, alignment: mine ? .trailing : .leading)
    }
}

struct ChatVideoPreview: View {
    let url: URL
    let height: CGFloat
    var onPresentationChange: (Bool) -> Void = { _ in }
    @State private var poster: UIImage?
    @State private var presented = false
    var body: some View {
        Button {
            onPresentationChange(true); presented = true
        } label: {
            ZStack {
                Color.black
                if let poster { Image(uiImage: poster).resizable().scaledToFill() }
                Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 5)
            }.frame(height: height).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.2), lineWidth: 0.5))
        }.buttonStyle(.plain).accessibilityLabel("播放视频").accessibilityHint("全屏播放")
            .task(id: url) {
                poster = nil
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 960, height: 960)
                if let (image, _) = try? await generator.image(at: .zero), !Task.isCancelled { poster = UIImage(cgImage: image) }
            }
            .fullScreenCover(isPresented: $presented, onDismiss: { onPresentationChange(false) }) {
                NavigationStack {
                    NativeVideo(url: url, autoplay: true).background(.black).ignoresSafeArea(edges: .bottom)
                        .navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { presented = false } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭视频")
                            }
                        }
                }
            }
    }
}

/// Media keeps its own rounded viewport; only text messages have a chat bubble.
private struct ChatBubbleSurface: ViewModifier {
    let media: Bool
    let mine: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if media { content }
        else {
            content.padding(.horizontal, 14).padding(.vertical, 11)
                .background(mine ? Color.brand.opacity(0.16) : Color(uiColor: .secondarySystemBackground),
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6,
                                                       bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20))
        }
    }
}

struct ChatPendingRow: View {
    let item: PendingMessage
    let sending: Bool
    let blocked: Bool
    let retry: () -> Void
    let remove: () -> Void
    var checkDelivery: () -> Void = { }
    var onMediaPresentation: (Bool) -> Void = { _ in }
    @State private var confirmResend = false
    private var bareMedia: Bool { ["image", "video"].contains(item.kind) && item.media != nil }
    private var caption: String { bareMedia ? ImageMessageCaption.text(item.content, media: item.media ?? "") : item.content }
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if bareMedia, let media = item.media {
                    MediaView(images: item.kind == "image" ? [media] : [], video: item.kind == "video" ? media : "",
                              thumbnailHeight: 190, fitImage: true, onPresentationChange: onMediaPresentation)
                        .frame(maxWidth: 250)
                    if !caption.isEmpty { Text(caption).font(.body).textSelection(.enabled).frame(maxWidth: 250, alignment: .trailing) }
                } else {
                    Text(caption).font(.body).textSelection(.enabled)
                        .modifier(ChatBubbleSurface(media: false, mine: true))
                }
                deliveryStatus
            }
        }.padding(.horizontal).padding(.top, 6)
            .confirmationDialog("这条消息可能已经送达", isPresented: $confirmResend, titleVisibility: .visible) {
                Button("检查最新消息", action: checkDelivery)
                Button("仍然重新发送", action: retry)
                Button("取消", role: .cancel) { }
            } message: {
                Text("服务器未返回确认，重新发送可能产生重复消息。请先检查会话中的最新消息。")
            }
    }
    private var deliveryStatus: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let failure = item.failure {
                HStack(spacing: 12) {
                    Label(item.deliveryUncertain == true ? "结果待确认" : "未发送", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Button(item.deliveryUncertain == true ? "重新发送" : "重试") {
                        if item.deliveryUncertain == true { confirmResend = true } else { retry() }
                    }.frame(minHeight: 44)
                    Button("移除", role: .destructive, action: remove).frame(minHeight: 44)
                }.buttonStyle(.plain)
                if item.deliveryUncertain == true {
                    Button("检查最新消息", action: checkDelivery).frame(minHeight: 44).buttonStyle(.plain)
                }
                Text(failure).foregroundStyle(.secondary).lineLimit(3)
            } else if sending {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("正在发送…") }.foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Label(blocked ? "等待上一条消息重试" : "等待发送", systemImage: "clock").foregroundStyle(.secondary)
                    Button("取消", role: .destructive, action: remove).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }.font(.caption)
    }
}

struct ChatAttachments: Identifiable {
    let id = UUID()
    let items: [SelectedMedia]
}

/// Keep the complete selection local until Send; reuse successful uploads on retry.
struct ChatAttachmentSheet: View {
    let media: [SelectedMedia]
    let api: APIClient
    let store: ChatStore
    let quoteID: Int?
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var submitting = false
    @State private var cancelled = false
    @State private var error: String?
    @State private var images: [UUID: UIImage] = [:]
    @State private var videoURLs: [UUID: URL] = [:]
    @State private var uploaded: [UUID: String] = [:]
    @State private var excluded = Set<UUID>()
    @State private var selected = 0
    @State private var completed = 0
    @State private var uploadProgress: Double = 0
    private var selection: [SelectedMedia] { media.filter { !excluded.contains($0.id) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if selection.indices.contains(selected) {
                        let item = selection[selected]
                        if item.isVideo {
                            if let url = videoURLs[item.id] { NativeVideo(url: url).frame(height: 320) }
                            else { ProgressView("正在准备视频…").frame(height: 320) }
                        } else if let image = images[item.id] {
                            ZoomImageSurface(image: image).frame(height: 360).accessibilityLabel("待发送图片，可缩放预览")
                        } else { ProgressView().frame(height: 200) }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(selection.enumerated()), id: \.element.id) { index, item in
                                VStack(spacing: 2) {
                                    Button { selected = index } label: {
                                        ZStack {
                                            if let image = images[item.id] {
                                                Image(uiImage: image).resizable().scaledToFill().frame(width: 66, height: 66).clipped()
                                            } else { Image(systemName: "video.fill").frame(width: 66, height: 66) }
                                        }.clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == index ? Color.brand : .clear, lineWidth: 2))
                                    }.buttonStyle(.plain).accessibilityLabel("预览第 \(index + 1) 个附件")
                                    Button("移除", role: .destructive) {
                                        let currentID = selection.indices.contains(selected) ? selection[selected].id : nil
                                        excluded.insert(item.id)
                                        selected = selection.firstIndex { $0.id == currentID } ?? GalleryPosition.clamped(selected, count: selection.count)
                                    }.font(.caption).frame(minWidth: 66, minHeight: 44).disabled(submitting)
                                }
                            }
                        }.padding(3)
                    }
                    TextField("添加说明（可选）", text: $caption, axis: .vertical).lineLimit(1...5)
                        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16)).disabled(submitting)
                    ErrorBanner(text: error)
                    if submitting {
                        ProgressView(value: uploadProgress) {
                            Text("正在上传 \(min(completed + 1, selection.count))/\(selection.count) · \(Int(uploadProgress * 100))%")
                        }
                    } else if error != nil && !uploaded.isEmpty {
                        Text("已上传的附件会保留，重试将继续发送。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { submitting = true } label: {
                        Label(error == nil ? "发送 \(selection.count) 个附件" : "重试发送", systemImage: "arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.glassProminent).disabled(submitting || selection.isEmpty)
                }.padding()
            }.navigationTitle("发送照片与视频").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { cancelled = true; submitting = false; dismiss() }
                    }
                }.interactiveDismissDisabled(submitting)
                .task {
                    for item in media {
                        if item.isVideo {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-preview-" + item.name)
                            do { try item.data.write(to: url, options: [.atomic, .completeFileProtection]); videoURLs[item.id] = url }
                            catch { self.error = "无法预览视频" }
                        } else { images[item.id] = UIImage(data: item.data) }
                    }
                }
                .task(id: submitting) {
                    guard submitting, !cancelled else { return }
                    let epoch = api.generation, batch = selection
                    defer { submitting = false }
                    error = nil; completed = 0; uploadProgress = 0
                    do {
                        let totalBytes = max(1, batch.reduce(0) { $0 + $1.data.count })
                        var sentBytes = 0
                        var attachments: [(url: String, kind: String)] = []
                        for item in batch {
                            let url: String
                            if let cached = uploaded[item.id] { url = cached }
                            else {
                                let before = sentBytes, bytes = item.data.count
                                url = try await api.upload(item.data, filename: item.name, mime: item.mime) { value in
                                    guard submitting, !cancelled, epoch == api.generation else { return }
                                    let fraction = (Double(before) + Double(bytes) * min(value, 0.98)) / Double(totalBytes)
                                    if abs(uploadProgress - fraction) >= 0.01 { uploadProgress = fraction }
                                }
                                uploaded[item.id] = url
                            }
                            try Task.checkCancellation()
                            guard !cancelled, epoch == api.generation else { return }
                            if let image = images[item.id] { ImageRepository.shared.rememberUploadedPreview(image, at: url) }
                            attachments.append((url, item.isVideo ? "video" : "image")); completed += 1
                            sentBytes += item.data.count; uploadProgress = Double(sentBytes) / Double(totalBytes)
                        }
                        guard store.enqueueMedia(attachments, caption: caption, quoteID: quoteID) else {
                            throw APIError(status: 0, message: "无法加入发送队列，请重试")
                        }
                        onSent(); dismiss()
                    } catch {
                        if !cancelled, !Task.isCancelled, epoch == api.generation { self.error = error.localizedDescription }
                    }
                }
                .onDisappear { for url in videoURLs.values { try? FileManager.default.removeItem(at: url) } }
        }
    }
}
