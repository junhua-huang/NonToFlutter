import SwiftUI
import PhotosUI

struct MessagesView: View {
    @StateObject private var resource: PagedResource<Conversation>
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var socket: RealtimeClient
    init(session: AppSession) {
        _socket = ObservedObject(wrappedValue: session.socket)
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/chat/sessions", keys: ["sessions", "conversations", "items"], userID: session.user?.id ?? 0, pageSize: 30))
    }
    var body: some View {
        List {
            ForEach(resource.items) { conversation in
                NavigationLink { ChatRoomView(conversation: conversation) } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: conversation.avatar, name: conversation.name)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(conversation.name).font(.headline); Spacer(); if let d = conversation.last.date { Text(d, style: .relative).font(.caption2).foregroundStyle(.secondary) } }
                            Text(conversation.last.recalled ? "消息已撤回" : preview(conversation.last)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if conversation.unread > 0 { Text("\(conversation.unread)").font(.caption.bold()).padding(6).background(Color.brand, in: Capsule()).foregroundStyle(.white) }
                    }.padding(.vertical, 6)
                }
            }
            ResourceFooter(resource: resource)
        }.listStyle(.plain).navigationTitle("消息")
            .toolbar { NavigationLink { FriendsView(session: session) } label: { Image(systemName: "person.2") }.accessibilityLabel("好友和申请") }
            .task { await resource.load(reset: true) }
            .refreshable { await resource.load(reset: true); await session.refreshCounts() }
            .onReceive(socket.$revision.debounce(for: .milliseconds(450), scheduler: RunLoop.main)) { _ in Task { await resource.load(reset: true) } }
    }
    private func preview(_ message: ChatMessage) -> String {
        switch message.kind { case "image": return "[图片]"; case "video": return "[视频]"; case "post": return "[动态]"; case "file": return "[文件]"; default: return message.content }
    }
}

struct ChatRoomView: View {
    let conversation: Conversation
    @EnvironmentObject private var session: AppSession
    var body: some View { ChatRoomContent(session: session, conversation: conversation) }
}

private struct ChatRoomContent: View {
    let conversation: Conversation
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @StateObject private var store: ChatStore
    @ObservedObject private var socket: RealtimeClient
    @State private var quote: ChatMessage?
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var recall: ChatMessage?
    @State private var confirmRecall = false
    @State private var visible = false
    private var communityID: Int? { conversation.isCommunity ? conversation.communityID : nil }
    init(session: AppSession, conversation: Conversation) {
        self.conversation = conversation
        _store = StateObject(wrappedValue: ChatStore(api: session.api, conversation: conversation, userID: session.user?.id ?? 0, socket: session.socket))
        _socket = ObservedObject(wrappedValue: session.socket)
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.more { Button(store.loading ? "正在加载…" : "加载更早的消息") { Task { await store.load(older: true) } }.disabled(store.loading).padding(.top) }
                    if store.loading && store.messages.isEmpty { ProgressView("正在加载消息…") }
                    ErrorBanner(text: store.error) { Task { await store.load() } }.padding(.horizontal)
                    ForEach(store.messages) { message in messageRow(message).id(message.id) }
                    ForEach(store.pending) { item in
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(item.content.isEmpty ? "[媒体消息]" : item.content).padding(12).background(Color.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                            if let failure = item.failure {
                                Text(failure).font(.caption).foregroundStyle(.red)
                                HStack {
                                    Button("重试") { store.retry(item.id) }.disabled(store.sending)
                                    if !item.content.isEmpty { Button("复制") { UIPasteboard.general.string = item.content } }
                                    Button("移除", role: .destructive) { store.remove(item.id) }
                                }.font(.caption)
                            } else { ProgressView("待发送").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.bottom)
            }.scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 100
                } action: { _, value in store.reachedBottom(value) }
                .onChange(of: store.scrollRequest) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .overlay(alignment: .bottomTrailing) {
                    if store.unread > 0 {
                        Button { store.jumpToLatest() } label: { Label("\(store.unread) 条新消息", systemImage: "arrow.down") }
                            .buttonStyle(.glassProminent).padding()
                    }
                }
        }
        .navigationTitle(conversation.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let quote { HStack { Text("引用：\(quote.content)").lineLimit(1).font(.caption); Spacer(); Button("取消") { self.quote = nil } }.padding(.horizontal) }
                HStack(alignment: .bottom) {
                    PhotosPicker(selection: $pick, matching: .any(of: [.images, .videos])) { Image(systemName: "plus.circle").font(.title2) }.disabled(uploading).accessibilityLabel("添加照片或视频")
                    TextField("发送消息…", text: $store.draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                    Button {
                        if store.enqueue(content: store.draft, quoteID: quote?.id) { store.draft = ""; quote = nil; store.saveDraft() }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(uploading || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送消息")
                }.floatingGlass()
                if uploading { ProgressView("正在上传…").font(.caption).padding(.horizontal) }
            }.padding(.top, 8)
        }
        .task {
            visible = true
            if phase == .active { await store.activate() }
            // Socket events drive updates; slow polling recovers missed server events.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
                if visible && phase == .active { await store.load() }
            }
        }
        .onDisappear { visible = false; store.suspend(); Task { await session.refreshCounts() } }
        .onChange(of: phase) { _, value in
            if value == .active && visible { Task { await store.activate() } } else { store.suspend() }
        }
        .onChange(of: store.draft) { _, _ in store.saveDraft() }
        .onReceive(socket.$revision.dropFirst().debounce(for: .milliseconds(350), scheduler: RunLoop.main)) { _ in
            if visible && phase == .active { Task { await store.load() } }
        }
        .task(id: pick) {
            guard let pick else { return }
            uploading = true; defer { uploading = false; self.pick = nil }
            let epoch = session.api.generation
            do {
                let media = try await MediaLoader.load(pick)
                try Task.checkCancellation()
                let url = try await session.api.upload(media.data, filename: media.name, mime: media.mime)
                try Task.checkCancellation()
                guard epoch == session.api.generation else { return }
                store.enqueue(content: "", kind: media.isVideo ? "video" : "image", media: url)
            } catch {
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled, epoch == session.api.generation { store.error = error.localizedDescription }
            }
        }
        .confirmationDialog("撤回这条消息？", isPresented: $confirmRecall) {
            Button("撤回", role: .destructive) { if let recall { Task { await store.recall(recall) } } }
        }
    }
    @ViewBuilder private func messageRow(_ message: ChatMessage) -> some View {
        let mine = message.senderID == session.user?.id
        VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
            if let date = message.date { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            HStack(alignment: .top, spacing: 8) {
                if mine { Spacer(minLength: 40) }
                else if communityID != nil {
                    let sender = Person(message.raw["sender"].or(message.raw["user"]))
                    NavigationLink { ProfileView(userID: message.senderID) } label: { AvatarView(url: sender.avatar, name: sender.name, size: 30) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !message.raw["quote_preview"].string.isEmpty { Text(message.raw["quote_preview"].string).font(.caption).foregroundStyle(.secondary) }
                    if message.recalled { Text("消息已撤回").font(.caption).foregroundStyle(.secondary) }
                    else if message.kind == "image" { MediaView(images: [message.media], video: "").frame(maxWidth: 230) }
                    else if message.kind == "video" { MediaView(images: [], video: message.media).frame(maxWidth: 250) }
                    else if message.kind == "post", message.raw["related_id"].int > 0 {
                        NavigationLink { PostDetailView(session: session, postID: message.raw["related_id"].int) } label: { Label(message.content.isEmpty ? "查看动态" : message.content, systemImage: "doc.richtext").lineLimit(4) }
                    } else if message.kind == "file", let url = URL(string: message.media), url.scheme == "https" { Link(message.content.isEmpty ? "打开文件" : message.content, destination: url) }
                    else { Text(message.content).textSelection(.enabled) }
                    if mine && message.raw["is_read"].bool { Text("已读").font(.caption2).foregroundStyle(.secondary) }
                }.padding(12).background(mine ? Color.brand.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .contextMenu {
                        if !message.recalled {
                            Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                            if communityID != nil { Button("引用", systemImage: "quote.bubble") { quote = message } }
                            if mine, communityID != nil { Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { recall = message; confirmRecall = true } }
                        }
                    }
                if !mine { Spacer(minLength: 40) }
            }
        }.padding(.horizontal)
    }
}

struct SharePostView: View {
    let post: Post
    @StateObject private var resource: PagedResource<Conversation>
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var error: String?
    @State private var requestIDs: [Int: String] = [:]
    init(session: AppSession, post: Post) {
        self.post = post
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: "/chat/sessions", keys: ["sessions", "conversations", "items"], userID: session.user?.id ?? 0, pageSize: 30))
    }
    var body: some View {
        NavigationStack {
            List {
                ErrorBanner(text: error)
                ForEach(resource.items) { conv in
                    Button { Task { await share(conv) } } label: { HStack { AvatarView(url: conv.avatar, name: conv.name); Text(conv.name) } }.disabled(sending)
                }
                ResourceFooter(resource: resource)
            }.navigationTitle("分享动态").toolbar { Button("取消") { dismiss() }.disabled(sending) }
                .task { await resource.load(reset: true) }.interactiveDismissDisabled(sending)
        }
    }
    private func share(_ conv: Conversation) async {
        sending = true; defer { sending = false }
        let requestID = requestIDs[conv.id] ?? UUID().uuidString
        requestIDs[conv.id] = requestID
        do {
            let path = conv.isCommunity ? "/communities/\(conv.communityID ?? 0)/chat/messages" : "/chat/conversations/\(conv.id)/messages"
            _ = try await session.api.request(path, method: "POST", body: .object([
                "content": .text(post.content), "message_type": .text("post"), "related_id": .id(post.id),
                conv.isCommunity ? "client_msg_id" : "request_id": .text(requestID)]))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
