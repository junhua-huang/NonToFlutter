import SwiftUI
import PhotosUI

private struct ChatTabBarVisibility: ViewModifier {
    let managedByMessages: Bool
    let compact: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if managedByMessages { content }
        else { content.toolbarVisibility(compact ? .hidden : .automatic, for: .tabBar) }
    }
}

struct MessagesView: View {
    @StateObject private var resource: PagedResource<Conversation>
    @EnvironmentObject private var session: AppSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let socket: RealtimeClient
    private let selectedRouteKey: String?
    init(session: AppSession, selectedRouteKey: String? = nil) {
        self.selectedRouteKey = selectedRouteKey
        socket = session.socket
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
                // A retained split-view selection is not a selected row when
                // the phone has popped back to its single-column list.
                .listRowBackground(horizontalSizeClass == .regular && selectedRouteKey == AppRoute.chat(conversation).key ? Color.brand.opacity(0.10) : Color.timelineBackground)
                .accessibilityAddTraits(horizontalSizeClass == .regular && selectedRouteKey == AppRoute.chat(conversation).key ? .isSelected : [])
                .listRowSeparator(.hidden)
            }
            ResourceFooter(resource: resource, emptyTitle: "还没有会话", emptyDescription: "从右上角进入好友列表，或在社群中加入群聊。", emptyIcon: "bubble.left.and.bubble.right")
        }.timelineList().navigationTitle("私信").navigationBarTitleDisplayMode(.inline)
            .toolbar { RouteButton(.friends) { Image(systemName: "person.2") }.accessibilityLabel("好友和申请") }
            .task { await resource.loadIfNeeded() }
            .refreshable { await resource.load(reset: true); await session.refreshCounts() }
            .onReceive(socket.events.filter { ChatRealtimeEvent($0).affectsConversationList }
                .debounce(for: .milliseconds(450), scheduler: RunLoop.main)) { _ in Task { await resource.load(reset: true) } }
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

struct ChatRoomContent: View {
    let conversation: Conversation
    private let onMessageFrame: ((String, CGRect) -> Void)?
    private let onViewportMetrics: ((ChatViewportMetrics) -> Void)?
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.messagesOwnsTabBar) private var messagesOwnsTabBar
    @State private var store: ChatStore
    private let socket: RealtimeClient
    @State private var quote: ChatMessage?
    @State private var picks: [PhotosPickerItem] = []
    @State private var preparingMedia = false
    @State private var attachment: ChatAttachments?
    @FocusState private var composerFocused: Bool
    @State private var position = ScrollPosition(idType: String.self)
    @State private var viewport = ChatViewportMemory()
    @State private var recall: ChatMessage?
    @State private var confirmRecall = false
    @State private var visible = false
    @State private var quoteContext: ChatQuoteTarget?
    @State private var highlightedMessage: Int?
    @State private var quoteReturnID: String?
    @State private var highlightTask: Task<Void, Never>?
    private var communityID: Int? { conversation.isCommunity ? conversation.communityID : nil }
    init(session: AppSession, conversation: Conversation, store: ChatStore? = nil,
         onMessageFrame: ((String, CGRect) -> Void)? = nil,
         onViewportMetrics: ((ChatViewportMetrics) -> Void)? = nil) {
        self.conversation = conversation
        self.onMessageFrame = onMessageFrame
        self.onViewportMetrics = onViewportMetrics
        _store = State(initialValue: store ?? ChatStore(api: session.api, conversation: conversation, userID: session.user?.id ?? 0, socket: session.socket))
        socket = session.socket
    }
    var body: some View {
        let timeline = store.timeline
        GeometryReader { _ in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if store.more && !store.messages.isEmpty {
                        Button { Task { await loadOlder() } } label: {
                            if store.loadingOlder { ProgressView("正在加载历史消息…") }
                            else { Label("更早的消息", systemImage: "clock.arrow.circlepath") }
                        }.font(.subheadline).disabled(store.loadingOlder).padding(.vertical, 12)
                    }
                    ForEach(timeline.entries) { entry in
                        ChatMessageRow(row: entry.row, community: communityID != nil,
                                       showsReceipt: entry.row.id == timeline.lastOutgoingID,
                                       galleryImages: entry.pending == nil ? timeline.gallery : [],
                                       galleryIndex: timeline.galleryIndexes[entry.row.id], onMediaPresentation: mediaPresentationChanged,
                                       pending: entry.pending, sending: store.sendingID == entry.pending?.id,
                                       blocked: store.pending.first?.failure != nil && store.pending.first?.id != entry.pending?.id,
                                       retry: { if let item = entry.pending { store.retry(item.id) } },
                                       remove: { if let item = entry.pending { store.remove(item.id) } },
                                       checkDelivery: { Task { await store.load() } },
                                       highlighted: highlightedMessage == entry.row.id,
                                       onJumpToQuote: { jumpToQuote($0, from: entry.id) },
                                       onQuote: { quote = $0; composerFocused = true },
                                       onRecall: { recall = $0; confirmRecall = true })
                            .modifier(ChatMessageFrameObservation(id: entry.id, report: onMessageFrame)).id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }.scrollTargetLayout().padding(.vertical, 8)
            }
            .overlay {
                if store.messages.isEmpty && store.pending.isEmpty {
                    ChatTimelinePlaceholder(loading: store.loading, error: store.error) { Task { await store.load() } }
                }
            }
            .background(Color.timelineBackground)
            .overlay(alignment: .top) {
                if let error = store.error, !store.messages.isEmpty || !store.pending.isEmpty {
                    ChatSyncNotice(error: error, retry: { Task { await store.load() } }, dismiss: { store.error = nil })
                        .padding(.horizontal).padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            // Align only underflowing content; width/keyboard changes still use
            // measured offsets rather than a persistent bottom-edge position.
            .defaultScrollAnchor(.bottom, for: .alignment)
            .onScrollGeometryChange(for: ChatViewportMetrics.self) { geometry in
                ChatViewportMetrics(offset: geometry.contentOffset.y, contentHeight: geometry.contentSize.height,
                                    visibleHeight: geometry.containerSize.height, topInset: geometry.contentInsets.top,
                                    bottomInset: geometry.contentInsets.bottom, visibleWidth: geometry.containerSize.width)
            } action: { previous, value in
                onViewportMetrics?(value)
                if let y = viewport.record(value) { position.scrollTo(y: y) }
                else if abs(previous.visibleWidth - value.visibleWidth) > 1,
                        store.nearBottom, !viewport.userScrolling,
                        !viewport.preservingHistory, !viewport.presentingMedia {
                    // Keep the concrete final row anchored while lazy cells reflow.
                    followLatest()
                }
                else if abs(previous.visibleHeight - value.visibleHeight) > 1
                        || abs(previous.bottomInset - value.bottomInset) > 1
                        || abs(previous.topInset - value.topInset) > 1,
                        store.nearBottom, !viewport.userScrolling,
                        !viewport.preservingHistory, !viewport.presentingMedia {
                    followLatest(in: value)
                }
                if !store.loadingOlder && !viewport.preservingHistory && !viewport.presentingMedia {
                    if value.nearBottom || viewport.userScrolling { store.reachedBottom(value.nearBottom) }
                    if value.shouldLoadHistory(userScrolling: viewport.userScrolling), store.more {
                        Task { await loadOlder() }
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                viewport.userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                if phase == .idle, let metrics = viewport.metrics, !store.loadingOlder, !viewport.presentingMedia {
                    store.reachedBottom(metrics.nearBottom)
                }
            }
            .onChange(of: store.scrollRequest) { _, _ in
                viewport.clearPreservation()
                quoteReturnID = nil; highlightedMessage = nil
                followLatest()
            }
            .onChange(of: timeline.entries.last?.id) { _, _ in
                if store.nearBottom, !viewport.preservingHistory, !viewport.presentingMedia { followLatest() }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    if let returnID = quoteReturnID {
                        Button {
                            quoteReturnID = nil; highlightedMessage = nil
                            withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: returnID, anchor: .center) }
                        } label: { Label("回到引用处", systemImage: "arrow.uturn.down") }
                            .buttonStyle(.glass).accessibilityHint("返回刚才阅读的消息")
                    }
                    if !store.nearBottom && !store.messages.isEmpty {
                        Button { store.jumpToLatest() } label: {
                            Label(store.unread > 0 ? "\(store.unread) 条新消息" : "回到最新", systemImage: "arrow.down")
                        }.buttonStyle(.glassProminent).accessibilityHint("跳到最新消息")
                    }
                }.padding()
            }
        }
        .frame(maxWidth: 820).frame(maxWidth: .infinity)
        .background(Color.timelineBackground)
        .navigationTitle(conversation.name).navigationBarTitleDisplayMode(.inline)
        .modifier(ChatTabBarVisibility(managedByMessages: messagesOwnsTabBar, compact: horizontalSizeClass == .compact))
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposerInput(store: store, quote: $quote, picks: $picks, preparingMedia: preparingMedia, focus: $composerFocused)
                .frame(maxWidth: 820).frame(maxWidth: .infinity)
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
        .onDisappear { visible = false; highlightTask?.cancel(); store.suspend(); Task { await session.refreshCounts() } }
        .onChange(of: phase) { _, value in
            if value == .active && visible { Task { if visible { await store.activate() } } } else { store.suspend() }
        }
        .sheet(item: $attachment) { media in
            ChatAttachmentSheet(media: media.items, api: session.api, store: store, quoteID: quote?.id) {
                quote = nil
            }
        }
        .sheet(item: $quoteContext, onDismiss: { mediaPresentationChanged(false) }) { target in
            ChatQuoteContextView(targetID: target.id, store: store, conversation: conversation, socket: socket)
        }
        .onReceive(socket.events) { payload in
            if visible && phase == .active, store.receive(payload) {
                Task { if visible && phase == .active { await store.load() } }
            }
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
    private func followLatest(in geometry: ChatViewportMetrics? = nil) {
        // Follow one concrete content target during keyboard layout instead of
        // combining an edge scroll request with automatic size-change anchoring.
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let geometry { position.scrollTo(y: geometry.clamped(.greatestFiniteMagnitude)) }
            else { position.scrollTo(id: "chat-bottom", anchor: .bottom) }
        }
    }
    private func loadOlder() async {
        guard !store.loadingOlder, !viewport.preservingHistory, store.more, visible else { return }
        let first = store.messages.first?.id
        viewport.beginHistory()
        await store.load(older: true)
        guard visible, !Task.isCancelled else { return }
        if let y = viewport.finishHistory(addedRows: store.messages.first?.id != first) { position.scrollTo(y: y) }
    }
    private func jumpToQuote(_ id: Int, from entryID: String) {
        guard id > 0 else { return }
        composerFocused = false
        guard let target = store.timeline.entries.first(where: { $0.row.id == id }) else {
            mediaPresentationChanged(true)
            quoteContext = ChatQuoteTarget(id: id)
            return
        }
        viewport.clearPreservation(); store.reachedBottom(false)
        quoteReturnID = entryID; highlightedMessage = id
        withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: target.id, anchor: .center) }
        highlightTask?.cancel()
        highlightTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            highlightedMessage = nil
        }
    }
    private func mediaPresentationChanged(_ presented: Bool) {
        if presented {
            viewport.beginMedia()
            // Refreshes while a gallery is open must not move the reading position.
            store.reachedBottom(false)
            composerFocused = false
        } else if let y = viewport.endMedia() {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { position.scrollTo(y: y) }
        }
    }

}

/// The production path has no frame observer. Interaction tests can inspect
/// actual row placement as well as pixels, including rows behind the keyboard.
private struct ChatMessageFrameObservation: ViewModifier {
    let id: String
    let report: ((String, CGRect) -> Void)?
    @ViewBuilder func body(content: Content) -> some View {
        if let report {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report(id, $0) }
        } else { content }
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
            let result = try await session.api.request(path, method: "POST", body: .object([
                "content": .text(post.content), "message_type": .text("post"), "related_id": .id(post.id),
                conv.isCommunity ? "client_msg_id" : "request_id": .text(requestID)]))
            guard ChatMessage.confirmation(result) != nil else { throw APIError(status: 0, message: "未收到分享确认，请先检查会话中的消息") }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Draft changes invalidate the input bar only, keeping the timeline out of the typing hot path.
private struct ChatComposerInput: View {
    @Bindable var store: ChatStore
    @Binding var quote: ChatMessage?
    @Binding var picks: [PhotosPickerItem]
    let preparingMedia: Bool
    let focus: FocusState<Bool>.Binding
    @EnvironmentObject private var session: AppSession
    @State private var showingEmoji = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote {
                HStack(spacing: 8) {
                    Image(systemName: "quote.bubble").foregroundStyle(Color.brand)
                    Text(ChatQuoteSummary.text(quote).isEmpty ? "引用消息" : ChatQuoteSummary.text(quote))
                        .lineLimit(2).font(.caption)
                    Spacer()
                    Button { self.quote = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("取消引用").frame(minWidth: 44, minHeight: 44)
                }.padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "plus.circle").font(.title2).frame(width: 44, height: 44)
                }.disabled(preparingMedia).accessibilityLabel("添加照片或视频")
                Button {
                    focus.wrappedValue = false; showingEmoji = true
                } label: {
                    Image(systemName: "face.smiling").font(.title2).frame(width: 44, height: 44)
                }.disabled(preparingMedia).accessibilityLabel("动态表情").accessibilityIdentifier("chat.emoji.open")
                TextField("发送消息…", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...5).padding(.vertical, 11)
                    .focused(focus).accessibilityLabel("消息内容")
                Button {
                    if store.enqueue(content: store.draft, quoteID: quote?.id) {
                        store.draft = ""; quote = nil; store.saveDraft()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44)
                }.disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command).accessibilityLabel("发送消息")
            }.floatingGlass()
            if preparingMedia { ProgressView("正在准备预览…").font(.caption).padding(.horizontal) }
        }.padding(.top, 6)
            .onChange(of: store.draft) { _, _ in store.scheduleDraftSave() }
            .sheet(isPresented: $showingEmoji) {
                NotoEmojiPicker(accountID: session.user?.id ?? 0) { item in
                    guard store.enqueue(content: item.emoji, quoteID: quote?.id) else { return false }
                    quote = nil
                    return true
                }
            }
    }
}
