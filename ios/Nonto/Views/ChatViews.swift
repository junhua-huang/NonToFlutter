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
                RouteButton(.chat(conversation)) {
                    HStack(spacing: 12) {
                        AvatarView(url: conversation.avatar, name: conversation.name, size: 50)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(conversation.name).font(.headline); Spacer(); if let d = conversation.last.date { Text(d, format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).font(.caption2).foregroundStyle(.secondary) } }
                            Text(conversation.last.recalled ? "消息已撤回" : preview(conversation.last))
                                .font(.subheadline.weight(conversation.unread > 0 ? .medium : .regular))
                                .foregroundStyle(conversation.unread > 0 ? Color.primary : Color.secondary).lineLimit(2)
                        }
                        if conversation.unread > 0 {
                            Text(conversation.unread > 99 ? "99+" : "\(conversation.unread)").font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 4).background(Color.brand.opacity(0.15), in: Capsule())
                                .foregroundStyle(.primary).accessibilityLabel("\(conversation.unread) 条未读消息")
                        }
                    }.padding(.vertical, 10)
                }
            }
            ResourceFooter(resource: resource, emptyTitle: "还没有会话", emptyDescription: "从右上角进入好友列表，或在社群中加入群聊。", emptyIcon: "bubble.left.and.bubble.right")
        }.timelineList().navigationTitle("私信").navigationBarTitleDisplayMode(.inline)
            .toolbar { RouteButton(.friends) { Image(systemName: "person.2") }.accessibilityLabel("好友和申请") }
            .task { await resource.loadIfNeeded() }
            .refreshable { await resource.load(reset: true); await session.refreshCounts() }
            .onReceive(socket.$revision.dropFirst().debounce(for: .milliseconds(450), scheduler: RunLoop.main)) { _ in Task { await resource.load(reset: true) } }
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
    @State private var picks: [PhotosPickerItem] = []
    @State private var preparingMedia = false
    @State private var attachment: ChatAttachments?
    @FocusState private var composerFocused: Bool
    @State private var position = ScrollPosition(idType: Int.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let gallery = ChatMediaTimeline.images(store.messages)
        let lastOutgoingID = store.messages.last(where: { $0.senderID == session.user?.id })?.id
        ScrollView {
            LazyVStack(spacing: 6) {
                if store.more && !store.messages.isEmpty {
                    Button { Task { await store.load(older: true) } } label: {
                        if store.loadingOlder { ProgressView("正在加载历史消息…") }
                        else { Label("更早的消息", systemImage: "clock.arrow.circlepath") }
                    }.font(.subheadline).disabled(store.loadingOlder).padding(.vertical, 12)
                }
                if !store.messages.isEmpty || !store.pending.isEmpty {
                    ErrorBanner(text: store.error) { Task { await store.load() } }.padding(.horizontal)
                }
                ForEach(ChatTimeline.rows(store.messages)) { row in
                    ChatMessageRow(row: row, community: communityID != nil,
                                   showsReceipt: row.id == lastOutgoingID,
                                   gallery: gallery,
                                   onQuote: { quote = $0; composerFocused = true },
                                   onRecall: { recall = $0; confirmRecall = true }).id(row.id)
                }
                ForEach(store.pending) { item in
                    ChatPendingRow(item: item, sending: store.sendingID == item.id,
                                   blocked: store.pending.first?.failure != nil && store.pending.first?.id != item.id,
                                   retry: { store.retry(item.id) }, remove: { store.remove(item.id) })
                }
                Color.clear.frame(height: 1).id(Int.min)
            }.scrollTargetLayout().padding(.vertical, 8)
        }
        .overlay {
            if store.messages.isEmpty && store.pending.isEmpty {
                ChatTimelinePlaceholder(loading: store.loading, error: store.error) { Task { await store.load() } }
            }
        }
        .background(Color.timelineBackground)
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.visibleRect.maxY < 100
        } action: { _, value in if !store.loadingOlder { store.reachedBottom(value) } }
        .onChange(of: store.scrollRequest) { _, _ in
            if reduceMotion { position.scrollTo(edge: .bottom) }
            else { withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) } }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.unread > 0 {
                Button { store.jumpToLatest() } label: { Label("\(store.unread) 条新消息", systemImage: "arrow.down") }
                    .buttonStyle(.glassProminent).padding().accessibilityHint("跳到最新消息")
            }
        }
        .navigationTitle(conversation.name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(url: conversation.avatar, name: conversation.name, size: 30)
                    Text(conversation.name).font(.headline).lineLimit(1)
                }.accessibilityElement(children: .combine)
            }
            if communityID == nil, conversation.other.id > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    RouteButton(.profile(conversation.other.id)) { Image(systemName: "info.circle") }
                    .accessibilityLabel("聊天对象资料、举报与屏蔽")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let quote {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.bubble").foregroundStyle(Color.brand)
                        Text(quote.content.isEmpty ? "引用媒体消息" : quote.content).lineLimit(2).font(.caption)
                        Spacer()
                        Button { self.quote = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("取消引用").frame(minWidth: 44, minHeight: 44)
                    }.padding(.horizontal)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "plus.circle").font(.title2).frame(width: 44, height: 44)
                    }.disabled(preparingMedia).accessibilityLabel("添加照片或视频")
                    TextField("发送消息…", text: $store.draft, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...5).padding(.vertical, 11)
                        .focused($composerFocused).accessibilityLabel("消息内容")
                    Button(action: sendText) {
                        Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44)
                    }.disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityLabel("发送消息")
                }.floatingGlass()
                if preparingMedia { ProgressView("正在准备预览…").font(.caption).padding(.horizontal) }
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
            if value == .active && visible { Task { if visible { await store.activate() } } } else { store.suspend() }
        }
        .onChange(of: store.draft) { _, _ in store.scheduleDraftSave() }
        .onChange(of: composerFocused) { _, focused in if focused && store.nearBottom { store.jumpToLatest() } }
        .sheet(item: $attachment) { media in
            ChatAttachmentSheet(media: media.items, api: session.api, store: store, quoteID: quote?.id) {
                quote = nil
            }
        }
        .onReceive(socket.$revision.dropFirst().debounce(for: .milliseconds(350), scheduler: RunLoop.main)) { _ in
            if visible && phase == .active { Task { if visible && phase == .active { await store.load() } } }
        }
        .task(id: picks) {
            let selection = picks
            guard !selection.isEmpty else { return }
            preparingMedia = true; defer { preparingMedia = false; self.picks = [] }
            let epoch = session.api.generation
            do {
                var prepared: [SelectedMedia] = []
                for pick in selection {
                    let media = try await MediaLoader.load(pick)
                    try Task.checkCancellation()
                    guard prepared.reduce(0, { $0 + $1.data.count }) + media.data.count <= 80 * 1024 * 1024 else {
                        throw APIError(status: 0, message: "一次选择的附件总大小不能超过 80 MB，请减少视频数量")
                    }
                    prepared.append(media)
                }
                guard epoch == session.api.generation, visible else { return }
                composerFocused = false
                attachment = ChatAttachments(items: prepared)
            } catch {
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled, epoch == session.api.generation { store.error = error.localizedDescription }
            }
        }
        .confirmationDialog("撤回这条消息？", isPresented: $confirmRecall) {
            Button("撤回", role: .destructive) { if let recall { Task { await store.recall(recall) } } }
        }
    }
    private func sendText() {
        if store.enqueue(content: store.draft, quoteID: quote?.id) {
            store.draft = ""; quote = nil; store.saveDraft()
        }
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
                .task { await resource.loadIfNeeded() }.interactiveDismissDisabled(sending)
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
