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
        if message.isSticker { return ChatSticker.messageContent }
        guard ["image", "video"].contains(message.kind) else { return message.content }
        let kind = message.kind == "image" ? "[图片]" : "[视频]"
        let caption = ImageMessageCaption.text(message.content, media: message.media)
        return caption.isEmpty ? kind : kind + " " + caption
    }
    /// Match the server's compact reply preview so acknowledgement doesn't resize it.
    static func preview(_ message: ChatMessage) -> String {
        if message.recalled { return "消息已撤回" }
        if message.isSticker { return ChatSticker.messageContent }
        switch message.kind {
        case "image": return "[图片]"
        case "video": return "[视频]"
        case "post":
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = content.isEmpty ? "帖子 #\(message.id)" : String(content.prefix(30)) + (content.count > 30 ? "..." : "")
            return "[帖子] " + head
        default:
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(content.prefix(50)) + (content.count > 50 ? "..." : "")
        }
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
    var pending: PendingMessage? = nil
    var sending = false
    var blocked = false
    var retry: () -> Void = { }
    var remove: () -> Void = { }
    var checkDelivery: () -> Void = { }
    var highlighted = false
    var onJumpToQuote: ((Int) -> Void)? = nil
    var allowsActions = true
    let onQuote: (ChatMessage) -> Void
    let onRecall: (ChatMessage) -> Void
    @EnvironmentObject private var session: AppSession
    @State private var reporting = false
    @State private var stickerFeedback: String?
    private var message: ChatMessage { row.message }
    private var caption: String { message.isSticker ? "" : (["image", "video"].contains(message.kind) ? ImageMessageCaption.text(message.content, media: message.media) : message.content) }
    private var bareMedia: Bool { !message.recalled && (["image", "video"].contains(message.kind) || message.notoEmoji != nil) }
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
                            if pending == nil, message.kind == "image", ChatSticker.validURL(message.media) {
                                Button("添加到贴纸", systemImage: "square.on.circle") { saveSticker() }
                            }
                            if pending == nil && allowsActions { Button("引用", systemImage: "quote.bubble") { onQuote(message) } }
                            if pending != nil && !sending { Button("取消发送", role: .destructive, action: remove) }
                            if allowsActions, pending == nil, mine, let date = row.date, Date().timeIntervalSince(date) < 120 {
                                Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { onRecall(message) }
                            }
                            if !mine && message.senderID > 0 {
                                Button("举报消息发送者", systemImage: "flag") { reporting = true }
                            }
                        }
                        if let date = row.date { Text(date, format: .dateTime.year().month().day().hour().minute().second()) }
                    }
                    if mine {
                        // Keep the same status slot when this bubble is acknowledged
                        // or another outgoing bubble becomes the latest receipt.
                        Group {
                            if let pending {
                                ChatPendingStatus(item: pending, sending: sending, blocked: blocked,
                                                  retry: retry, remove: remove, checkDelivery: checkDelivery)
                            } else {
                                Text(message.raw["is_read"].bool ? "已读" : "已发送")
                                    .foregroundStyle(.secondary)
                                    .opacity(showsReceipt && !message.recalled ? 1 : 0)
                                    .accessibilityHidden(!showsReceipt || message.recalled)
                            }
                        }.font(.caption2).frame(minHeight: 16, alignment: .trailing)
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
        }.padding(.horizontal).padding(.top, row.startsRun ? 6 : 0)
            .background(Color.brand.opacity(highlighted ? 0.10 : 0))
            .sheet(isPresented: $reporting) {
                ReportView(kind: "user", targetID: message.senderID, context: "聊天消息 #\(message.id)：\n")
            }
            .alert("贴纸", isPresented: Binding(get: { stickerFeedback != nil }, set: { if !$0 { stickerFeedback = nil } })) {
                Button("好", role: .cancel) { stickerFeedback = nil }
            } message: { Text(stickerFeedback ?? "") }
    }
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.raw["quote_preview"].string.isEmpty {
                if let onJumpToQuote, message.raw["quote_message_id"].int > 0 {
                    Button { onJumpToQuote(message.raw["quote_message_id"].int) } label: { quotePreview }
                        .buttonStyle(.plain).frame(minHeight: 44, alignment: .leading).accessibilityLabel("查看引用的原消息")
                } else { quotePreview }
            }
            if message.recalled { Text("消息已撤回").font(.caption).foregroundStyle(.secondary) }
            else if message.isSticker {
                ChatStickerImage(url: message.media).frame(width: 160, height: 160)
                    .accessibilityIdentifier("chat.sticker.message.\(message.id)")
            }
            else if let emoji = message.notoEmoji {
                let size: CGFloat = emoji.count == 1 ? 136 : (emoji.count == 2 ? 104 : 76)
                HStack(spacing: 4) {
                    // Slot identity supports deliberate repetitions of the same emoji.
                    ForEach(Array(zip(["first", "second", "third"], emoji)), id: \.0) { _, item in
                        NotoEmojiAnimation(item: item).frame(width: size, height: size)
                    }
                }.frame(maxWidth: 250, alignment: mine ? .trailing : .leading)
            }
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
            if !message.recalled && (["image", "video"].contains(message.kind) || message.notoEmoji != nil) && !caption.isEmpty {
                Text(caption).textSelection(.enabled)
            }
        }.modifier(ChatBubbleSurface(media: bareMedia, mine: mine))
            .frame(maxWidth: bareMedia ? 250 : nil, alignment: mine ? .trailing : .leading)
    }
    private func saveSticker() {
        do {
            try ChatStickerLibrary(accountID: session.user?.id ?? 0).add(url: message.media)
            stickerFeedback = "已添加到贴纸，可在聊天“＋”中找到。"
        } catch { stickerFeedback = error.localizedDescription }
    }
    private var quotePreview: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Color.brand).frame(width: 3)
            Text(message.raw["quote_preview"].string).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if onJumpToQuote != nil, message.raw["quote_message_id"].int > 0 {
                Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
    }
}

/// The banner floats above the timeline, so a polling error cannot insert a row.
struct ChatSyncNotice: View {
    let error: String
    let retry: () -> Void
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingDetails = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
            Button { showingDetails = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("聊天提示").font(.caption.weight(.semibold)).lineLimit(1)
                    Text(typeSize.isAccessibilitySize ? "点按查看详情" : error)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).multilineTextAlignment(.leading)
            }.buttonStyle(.plain).accessibilityLabel("聊天提示，查看详情").accessibilityHint(error)
            Button("刷新", action: retry).font(.caption.weight(.semibold)).fixedSize().frame(minWidth: 44, minHeight: 44)
            Button(action: dismiss) { Image(systemName: "xmark") }.frame(width: 44, height: 44)
                .accessibilityLabel("收起同步提示")
        }.padding(.leading, 12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .alert("聊天提示", isPresented: $showingDetails) {
                Button("刷新消息", action: retry)
                Button("关闭", role: .cancel) { }
            } message: { Text(error) }
    }
}

struct ChatQuoteTarget: Identifiable { let id: Int }

/// A separately fetched quote window never changes the main chat's loaded pages.
struct ChatQuoteContextView: View {
    let targetID: Int
    let store: ChatStore
    let conversation: Conversation
    let socket: RealtimeClient
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var messages: [ChatMessage] = []
    @State private var loading = true
    @State private var error: String?
    @State private var position = ScrollPosition(idType: Int.self)
    var body: some View {
        AppNavigationStack {
            ScrollView {
                LazyVStack(spacing: 6) {
                    if !messages.isEmpty {
                        Text("引用消息及前后上下文").font(.caption).foregroundStyle(.secondary).padding()
                    }
                    ForEach(ChatTimeline.rows(messages)) { row in
                        ChatMessageRow(row: row, community: conversation.isCommunity, showsReceipt: false,
                                       highlighted: row.id == targetID, allowsActions: false,
                                       onQuote: { _ in }, onRecall: { _ in }).id(row.id)
                    }
                }.scrollTargetLayout().padding(.vertical, 8)
            }.scrollPosition($position).background(Color.timelineBackground)
                .overlay {
                    if messages.isEmpty { ChatTimelinePlaceholder(loading: loading, error: error) { Task { await load() } } }
                }
                .navigationTitle("引用的消息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .task { await load() }
                .onReceive(socket.events) { payload in
                    let event = ChatRealtimeEvent(payload)
                    guard event.name == "message_recalled",
                          event.conversationID == store.roomID || (conversation.communityID != nil && event.communityID == conversation.communityID) else { return }
                    let id = event.data["message_id"].or(event.data["id"]).int
                    if id > 0 { messages = ChatMessageReferences.redactingRecalls(messages, known: [id]) }
                }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            messages = try await store.quoteContext(targetID)
            try Task.checkCancellation()
            position.scrollTo(id: targetID, anchor: .center)
        } catch {
            if !Task.isCancelled {
                if let error = error as? APIError, [403, 404].contains(error.status) {
                    self.error = "原消息已删除，或当前账号无权查看"
                } else { self.error = error.localizedDescription }
            }
        }
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

/// Standalone previews use the same bubble as the unified live timeline.
struct ChatPendingRow: View {
    let item: PendingMessage
    let sending: Bool
    let blocked: Bool
    let retry: () -> Void
    let remove: () -> Void
    var checkDelivery: () -> Void = { }
    var onMediaPresentation: (Bool) -> Void = { _ in }
    @EnvironmentObject private var session: AppSession
    var body: some View {
        if let entry = ChatPresentation(userID: session.user?.id ?? 0, pending: [item]).entries.first {
            ChatMessageRow(row: entry.row, community: false, showsReceipt: false,
                           onMediaPresentation: onMediaPresentation,
                           pending: item, sending: sending, blocked: blocked, retry: retry, remove: remove,
                           checkDelivery: checkDelivery, onQuote: { _ in }, onRecall: { _ in })
        }
    }
}

struct ChatPendingStatus: View {
    let item: PendingMessage
    let sending: Bool
    let blocked: Bool
    let retry: () -> Void
    let remove: () -> Void
    var checkDelivery: () -> Void = { }
    @State private var confirmResend = false
    var body: some View {
        deliveryStatus
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
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { failureLabel; retryButton; removeButton }.fixedSize()
                    VStack(alignment: .trailing, spacing: 4) {
                        failureLabel
                        HStack(spacing: 12) { retryButton; removeButton }
                    }
                }.buttonStyle(.plain)
                if item.deliveryUncertain == true {
                    Button("检查最新消息", action: checkDelivery).frame(minHeight: 44).buttonStyle(.plain)
                }
                if item.retryWhenOnline == true { Text("连接恢复后自动重试").foregroundStyle(.secondary) }
                Text(failure).foregroundStyle(.secondary).lineLimit(3)
            } else {
                Label(sending ? "正在发送…" : (blocked ? "等待上一条消息重试" : "等待发送"),
                      systemImage: sending ? "arrow.up.circle" : "clock")
                    .foregroundStyle(.secondary)
                    .contextMenu { if !sending { Button("取消发送", role: .destructive, action: remove) } }
            }
        }
    }
    private var failureLabel: some View {
        Label(item.deliveryUncertain == true ? "结果待确认" : "未发送", systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(item.deliveryUncertain == true ? Color.orange : Color.red)
    }
    private var retryButton: some View {
        Button(item.deliveryUncertain == true ? "重新发送" : "重试") {
            if item.deliveryUncertain == true { confirmResend = true } else { retry() }
        }.frame(minHeight: 44)
    }
    private var removeButton: some View { Button("移除", role: .destructive, action: remove).frame(minHeight: 44) }
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
    @State private var selectedPreview: (id: UUID, image: UIImage)?
    @State private var videoURLs: [UUID: URL] = [:]
    @State private var uploaded: [UUID: String] = [:]
    @State private var excluded = Set<UUID>()
    @State private var selected = 0
    @State private var completed = 0
    @State private var uploadProgress: Double = 0
    private var selection: [SelectedMedia] { media.filter { !excluded.contains($0.id) } }
    private var selectedMedia: SelectedMedia? { selection.indices.contains(selected) ? selection[selected] : nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if selection.indices.contains(selected) {
                        let item = selection[selected]
                        if item.isVideo {
                            if let url = videoURLs[item.id] { NativeVideo(url: url).frame(height: 320) }
                            else { ProgressView("正在准备视频…").frame(height: 320) }
                        } else if let image = (selectedPreview?.id == item.id ? selectedPreview?.image : nil) ?? images[item.id] {
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
                        guard !Task.isCancelled else { return }
                        if item.isVideo {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-preview-" + item.name)
                            do {
                                try await Task.detached(priority: .userInitiated) {
                                    try item.data.write(to: url, options: [.atomic, .completeFileProtection])
                                }.value
                                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
                                videoURLs[item.id] = url
                            }
                            catch { self.error = "无法预览视频" }
                        } else if let image = try? await Task.detached(priority: .userInitiated, operation: {
                            try ImageRepository.decode(item.data, maxPixelSize: 960)
                        }).value, !Task.isCancelled { images[item.id] = image }
                    }
                }
                .task(id: selectedMedia?.id) {
                    selectedPreview = nil
                    guard let item = selectedMedia, !item.isVideo else { return }
                    let image = try? await Task.detached(priority: .userInitiated) {
                        try ImageRepository.decode(item.data, maxPixelSize: 1536)
                    }.value
                    if !Task.isCancelled, selectedMedia?.id == item.id, let image { selectedPreview = (item.id, image) }
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
                                url = try await api.upload(item.data, filename: item.name, mime: item.mime, type: "chat") { value in
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
