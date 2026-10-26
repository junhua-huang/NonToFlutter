import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

private struct ChatTabBarVisibility: ViewModifier {
    let managedByMessages: Bool
    let compact: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if managedByMessages { content }
        else { content.toolbarVisibility(compact ? .hidden : .automatic, for: .tabBar) }
    }
}

struct MessagesView: View {
    @Environment(\.appAccent) private var accent
    @StateObject private var resource: PagedResource<Conversation>
    @EnvironmentObject private var session: AppSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let socket: RealtimeClient
    private let selectedRouteKey: String?
    private let splitSelectionVisible: Bool?
    private var showsSelection: Bool { splitSelectionVisible ?? (horizontalSizeClass == .regular) }
    init(session: AppSession, selectedRouteKey: String? = nil, splitSelectionVisible: Bool? = nil) {
        self.selectedRouteKey = selectedRouteKey
        self.splitSelectionVisible = splitSelectionVisible
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
                                .padding(.horizontal, 7).padding(.vertical, 4).background(accent.color.opacity(0.15), in: Capsule())
                                .foregroundStyle(.primary).accessibilityLabel("\(conversation.unread) 条未读消息")
                        }
                    }.padding(.vertical, 10)
                }
                // A retained split-view selection is not a selected row when
                // the phone has popped back to its single-column list.
                .listRowBackground(showsSelection && selectedRouteKey == AppRoute.chat(conversation).key ? accent.color.opacity(0.10) : Color.timelineBackground)
                .accessibilityAddTraits(showsSelection && selectedRouteKey == AppRoute.chat(conversation).key ? .isSelected : [])
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
        if message.isSticker { return ChatSticker.messageContent }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: ChatStore
    @State private var stickerSender: ChatStickerSender
    @State private var availableHeight: CGFloat = 700
    private let composerEpoch: UUID
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
    @State private var attachmentMenuVisible = false
    @State private var pendingAttachmentAction: ChatAttachmentAction?
    @Namespace private var attachmentNamespace
    @State private var attachmentRequest: ChatAttachmentRequest?
    @State private var inputDismissal = 0
    @State private var farFromLatest = false
    @State private var showingCamera = false
    @State private var capturedPhoto: Data?
    @State private var captureFailed = false
    @State private var cameraError: String?
    @State private var cameraTask: Task<Void, Never>?
    @State private var highlightTask: Task<Void, Never>?
    private var communityID: Int? { conversation.isCommunity ? conversation.communityID : nil }
    init(session: AppSession, conversation: Conversation, store: ChatStore? = nil,
         onMessageFrame: ((String, CGRect) -> Void)? = nil,
         onViewportMetrics: ((ChatViewportMetrics) -> Void)? = nil) {
        self.conversation = conversation
        self.onMessageFrame = onMessageFrame
        self.onViewportMetrics = onViewportMetrics
        _store = State(initialValue: store ?? ChatStore(api: session.api, conversation: conversation, userID: session.user?.id ?? 0, socket: session.socket))
        _stickerSender = State(initialValue: ChatStickerSender(accountID: session.user?.id ?? 0))
        composerEpoch = session.api.generation
        socket = session.socket
    }
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            chatContent.overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        if attachmentMenuVisible {
                            ChatAttachmentMenu(availableHeight: max(0, geometry.size.height - 24),
                                               onSelect: selectAttachment, onDismiss: { setAttachmentMenu(false) })
                                .disabled(preparingMedia || stickerSender.busy || pendingAttachmentAction != nil)
                                .frame(width: min(320, max(0, geometry.size.width - 24)))
                                .glassEffectID("chat.attachments", in: attachmentNamespace)
                                .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
                                .padding(.leading, 12).padding(.bottom, 6)
                        }
                    }
                    .frame(maxWidth: 820, maxHeight: .infinity, alignment: .bottomLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    @ViewBuilder private var chatContent: some View {
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
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { dismissInput() })
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
                else if !value.hasSameLayout(as: previous),
                        store.nearBottom, !viewport.userScrolling,
                        !viewport.preservingHistory, !viewport.presentingMedia {
                    followLatest(in: value)
                }
                if !store.loadingOlder && !viewport.preservingHistory && !viewport.presentingMedia {
                    if value.nearBottom { store.reachedBottom(true) }
                    else if viewport.userScrolling && viewport.userMoved && value.hasSameLayout(as: previous) {
                        store.reachedBottom(false)
                    }
                    if farFromLatest != value.farFromBottom { farFromLatest = value.farFromBottom }
                    if value.shouldLoadHistory(userScrolling: viewport.userScrolling), store.more {
                        Task { await loadOlder() }
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                let didScroll = viewport.userScrolling && viewport.userMoved
                viewport.userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                if phase == .interacting { dismissInput() }
                // Programmatic scrolling and keyboard layout also end in idle.
                // Only a real timeline pan can switch off following the latest row.
                if phase == .idle, didScroll, let metrics = viewport.metrics,
                   !store.loadingOlder, !viewport.preservingHistory, !viewport.presentingMedia {
                    store.reachedBottom(metrics.nearBottom)
                    if farFromLatest != metrics.farFromBottom { farFromLatest = metrics.farFromBottom }
                }
            }
            .onChange(of: store.scrollRequest) { _, _ in
                viewport.clearPreservation()
                quoteReturnID = nil; highlightedMessage = nil
                farFromLatest = false
                followLatest()
            }
            .onChange(of: timeline.entries.last?.id) { _, _ in
                if store.nearBottom, !viewport.preservingHistory, !viewport.presentingMedia { followLatest() }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    if let returnID = quoteReturnID, !attachmentMenuVisible {
                        Button {
                            quoteReturnID = nil; highlightedMessage = nil
                            withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: returnID, anchor: .center) }
                        } label: { Label("回到引用处", systemImage: "arrow.uturn.down") }
                            .buttonStyle(.glass).accessibilityHint("返回刚才阅读的消息")
                    }
                    if !store.nearBottom && (farFromLatest || store.unread > 0)
                        && !store.messages.isEmpty && !attachmentMenuVisible && !viewport.presentingMedia {
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
            ChatComposerInput(store: store, stickerSender: stickerSender, accountEpoch: composerEpoch, availableHeight: availableHeight,
                              quote: $quote, picks: $picks, preparingMedia: preparingMedia, focus: $composerFocused,
                              attachmentRequest: attachmentRequest, inputDismissal: inputDismissal,
                              attachmentMenu: Binding(get: { attachmentMenuVisible }, set: setAttachmentMenu),
                              attachmentNamespace: attachmentNamespace)
                .frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
        .task {
            visible = true
            if phase == .active { await store.activate() }
            // Socket events drive updates; slow polling recovers missed server events.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
                if visible && phase == .active { await store.load() }
            }
        }
        .onDisappear { visible = false; pendingAttachmentAction = nil; attachmentMenuVisible = false; highlightTask?.cancel(); cameraTask?.cancel(); stickerSender.cancel(); store.suspend(); Task { await session.refreshCounts() } }
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
        .fullScreenCover(isPresented: $showingCamera, onDismiss: prepareCapturedPhoto) {
            ChatCameraCapture(onCapture: { data in capturedPhoto = data; showingCamera = false },
                              onCancel: { showingCamera = false },
                              onError: { captureFailed = true; showingCamera = false })
                .ignoresSafeArea()
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
        .alert("无法使用相机", isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
            Button("好", role: .cancel) { cameraError = nil }
        } message: { Text(cameraError ?? "") }
    }
    private func dismissInput() {
        composerFocused = false
        setAttachmentMenu(false)
        inputDismissal &+= 1
    }
    private var attachmentAnimation: Animation? { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86) }
    private func setAttachmentMenu(_ presented: Bool) {
        pendingAttachmentAction = nil
        guard attachmentMenuVisible != presented else { return }
        withAnimation(attachmentAnimation) { attachmentMenuVisible = presented }
    }
    private func selectAttachment(_ action: ChatAttachmentAction) {
        guard attachmentMenuVisible, pendingAttachmentAction == nil, !preparingMedia, !stickerSender.busy else { return }
        pendingAttachmentAction = action
        // Finish returning the glass to its source before presenting the picker.
        // An outside tap, navigation, or a new presentation cancels this action.
        withAnimation(attachmentAnimation, completionCriteria: .logicallyComplete) {
            attachmentMenuVisible = false
        } completion: {
            guard pendingAttachmentAction == action, !attachmentMenuVisible, !composerFocused,
                  visible, phase == .active, composerEpoch == session.api.generation, session.api.token != nil else { return }
            pendingAttachmentAction = nil
            if action == .camera { openCamera() }
            attachmentRequest = ChatAttachmentRequest(action: action)
        }
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraError = "当前设备无法使用相机。"; return
        }
        guard cameraTask == nil else { return }
        cameraTask = Task {
            defer { cameraTask = nil }
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard !Task.isCancelled, composerEpoch == session.api.generation, visible else { return }
            if allowed { showingCamera = true }
            else { cameraError = "请在系统设置中允许南图访问相机后再拍照。" }
        }
    }
    private func prepareCapturedPhoto() {
        if captureFailed {
            captureFailed = false; cameraError = "无法读取拍摄的照片，请重试。"; return
        }
        guard let data = capturedPhoto else { return }
        capturedPhoto = nil
        cameraTask?.cancel()
        cameraTask = Task {
            preparingMedia = true
            defer { preparingMedia = false; cameraTask = nil }
            do {
                let photo = try await Task.detached(priority: .userInitiated) { try SelectedMedia.image(data) }.value
                try Task.checkCancellation()
                guard composerEpoch == session.api.generation, session.api.token != nil else { return }
                attachment = ChatAttachments(items: [photo])
            } catch {
                if !Task.isCancelled, composerEpoch == session.api.generation { cameraError = error.localizedDescription }
            }
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

private enum ChatComposerDrawer: Identifiable {
    case photos
    case expressions(ChatExpressionTab)

    var id: String {
        switch self {
        case .photos: return "photos"
        case .expressions(let tab): return "expressions.\(tab.id)"
        }
    }
}

/// Only this subtree observes keystrokes and attachment selection.
struct ChatComposerInput: View {
    @Environment(\.appAccent) private var accent
    @Bindable var store: ChatStore
    @Bindable var stickerSender: ChatStickerSender
    let accountEpoch: UUID
    let availableHeight: CGFloat
    let pickerDefaults: UserDefaults
    @Binding var quote: ChatMessage?
    @Binding var picks: [PhotosPickerItem]
    let preparingMedia: Bool
    let focus: FocusState<Bool>.Binding
    let attachmentRequest: ChatAttachmentRequest?
    let inputDismissal: Int
    let attachmentNamespace: Namespace.ID?
    @Binding private var showingAttachments: Bool
    @EnvironmentObject private var session: AppSession
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawer: ChatComposerDrawer?
    @State private var drawerDetent: PresentationDetent
    @State private var pendingPhotos: [PhotosPickerItem] = []
    @State private var stagedSticker: StagedChatSticker?
    @State private var selection: TextSelection?
    @State private var caret: NSRange?
    @Namespace private var localAttachmentNamespace
    @State private var sendTask: Task<Void, Never>?
    @State private var composerHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var inputControlHeight: CGFloat = 52

    // Optional values are one-time preview seeds; live edits stay in this input bar.
    init(store: ChatStore, stickerSender: ChatStickerSender, accountEpoch: UUID, availableHeight: CGFloat,
         quote: Binding<ChatMessage?>, picks: Binding<[PhotosPickerItem]>, preparingMedia: Bool,
         focus: FocusState<Bool>.Binding, attachmentRequest: ChatAttachmentRequest? = nil, inputDismissal: Int = 0,
         attachmentMenu: Binding<Bool> = .constant(false), attachmentNamespace: Namespace.ID? = nil,
         initialPicker: ChatExpressionTab? = nil,
         initialSticker: StagedChatSticker? = nil, pickerDefaults: UserDefaults = .standard) {
        _store = Bindable(wrappedValue: store); _stickerSender = Bindable(wrappedValue: stickerSender)
        self.accountEpoch = accountEpoch; self.availableHeight = availableHeight
        self.pickerDefaults = pickerDefaults
        _quote = quote; _picks = picks; self.preparingMedia = preparingMedia; self.focus = focus
        self.attachmentRequest = attachmentRequest; self.inputDismissal = inputDismissal
        _showingAttachments = attachmentMenu; self.attachmentNamespace = attachmentNamespace
        _drawer = State(initialValue: initialPicker.map { .expressions($0) })
        _drawerDetent = State(initialValue: .height(min(320, max(110, availableHeight - 56 - 30))))
        _stagedSticker = State(initialValue: initialSticker)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            composerContent
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
            if drawer != nil {
                // Keep the composer above the resting sheet. Expanding the sheet
                // covers the composer instead of pushing it beyond the navigation bar.
                Color.clear.frame(height: compactDrawerHeight).allowsHitTesting(false).accessibilityHidden(true)
            }
        }.padding(.top, 6)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0), value: drawer != nil)
            .sheet(item: $drawer, onDismiss: drawerDismissed) { panel in
                drawerContent(panel)
                    .presentationDetents([compactDrawerDetent, .large], selection: $drawerDetent)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
                    .presentationBackgroundInteraction(.enabled(upThrough: compactDrawerDetent))
                    .presentationCornerRadius(32)
            }
            .onChange(of: store.draft) { _, _ in store.scheduleDraftSave() }
            .onChange(of: focus.wrappedValue) { _, value in if value { drawer = nil; showingAttachments = false } }
            .onChange(of: picks) { _, value in if !value.isEmpty { showingAttachments = false } }
            .onChange(of: attachmentRequest?.id) { _, _ in
                guard let request = attachmentRequest else { return }
                focus.wrappedValue = false; showingAttachments = false
                switch request.action {
                case .camera: drawer = nil
                case .photos: open(.photos)
                case .emoji: open(.emoji)
                case .stickers: open(.stickers)
                }
            }
            .onChange(of: inputDismissal) { _, _ in
                focus.wrappedValue = false; showingAttachments = false; drawer = nil
            }
            .onChange(of: compactDrawerHeight) { _, _ in
                if drawerDetent != .large { drawerDetent = compactDrawerDetent }
            }
            .onChange(of: dynamicType, initial: true) { _, value in if value.isAccessibilitySize { drawerDetent = .large } }
            .onDisappear { showingAttachments = false; sendTask?.cancel(); stickerSender.cancel() }
    }
    @ViewBuilder private func drawerContent(_ panel: ChatComposerDrawer) -> some View {
        switch panel {
        case .photos:
            ChatPhotoDrawer(onAdd: { items in
                pendingPhotos = items; drawer = nil
            }, onClose: { drawer = nil })
                .disabled(preparingMedia || stickerSender.busy)
        case .expressions(let mode):
            ChatExpressionDrawer(accountID: session.user?.id ?? 0, api: session.api, initialTab: mode,
                                 selection: stagedSticker, expanded: drawerExpanded, disabled: stickerSender.busy, defaults: pickerDefaults,
                                 onInsertEmoji: insertEmoji, onStageSticker: stageSticker,
                                 onClose: { drawer = nil })
        }
    }
    private var drawerExpanded: Binding<Bool> {
        Binding(get: { drawerDetent == .large }, set: { value in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                drawerDetent = value ? .large : compactDrawerDetent
            }
        })
    }
    private func drawerDismissed() {
        // Present the existing media preview only after the library sheet has
        // finished dismissing; two presentations must not compete.
        guard !pendingPhotos.isEmpty else { return }
        let items = pendingPhotos; pendingPhotos = []
        guard session.api.generation == accountEpoch, session.api.token != nil else { return }
        picks = items
    }
    private func stageSticker(_ sticker: StagedChatSticker) {
        stagedSticker = sticker; stickerSender.error = nil
        drawerExpanded.wrappedValue = false
    }
    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote {
                HStack(spacing: 8) {
                    Image(systemName: "quote.bubble").foregroundStyle(accent.textColor)
                    Text(ChatQuoteSummary.text(quote).isEmpty ? "引用消息" : ChatQuoteSummary.text(quote)).lineLimit(2).font(.caption)
                    Spacer()
                    Button { self.quote = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("取消引用").frame(minWidth: 44, minHeight: 44).disabled(stickerSender.busy)
                }.padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 10) {
                attachmentButton
                VStack(spacing: 0) {
                    if let stagedSticker {
                        ZStack(alignment: .topTrailing) {
                            ChatStagedStickerImage(sticker: stagedSticker)
                                .frame(width: verticalSize == .compact ? 48 : 96, height: verticalSize == .compact ? 48 : 96)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .accessibilityLabel("待发送贴纸：\(stagedSticker.name)")
                            Button(action: cancelSticker) { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel("取消待发送贴纸").accessibilityIdentifier("chat.sticker.cancel")
                        }
                        Divider().padding(.horizontal, 12)
                    }
                    composerRow
                }
                .padding(.horizontal, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: inputControlHeight / 2))
                .glassEffectID("chat.composer", in: attachmentNamespace ?? localAttachmentNamespace)
            }.padding(.horizontal, 12).padding(.bottom, 6)
            if let error = stickerSender.error { ErrorBanner(text: error).padding(.horizontal, 12) }
            if preparingMedia { ProgressView("正在准备预览…").font(.caption).padding(.horizontal) }
        }
    }
    private var compactDrawerHeight: CGFloat { min(320, max(110, availableHeight - composerHeight - 30)) }
    private var compactDrawerDetent: PresentationDetent { .height(compactDrawerHeight) }
    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(stagedSticker == nil ? "发送消息…" : "添加文字或发送", text: $store.draft, selection: textSelection, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...5).padding(.vertical, 12).focused(focus)
                .frame(minHeight: inputControlHeight)
                .disabled(stickerSender.busy).accessibilityLabel("消息内容")
            Button(action: send) {
                Group {
                    if stickerSender.busy { ProgressView() }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: min(inputControlHeight * 0.62, 40))) }
                }.frame(width: inputControlHeight - 8, height: inputControlHeight - 8)
            }.disabled(stickerSender.busy || (stagedSticker == nil && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .padding(.bottom, 4)
                .keyboardShortcut(.return, modifiers: .command).accessibilityLabel("发送消息").accessibilityIdentifier("chat.composer.send")
        }
    }
    @ViewBuilder private var attachmentButton: some View {
        if showingAttachments {
            // Preserve the input layout while its circle becomes the menu.
            Color.clear.frame(width: inputControlHeight, height: inputControlHeight).accessibilityHidden(true)
        } else {
            Button {
                focus.wrappedValue = false; drawer = nil; showingAttachments = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: min(inputControlHeight * 0.44, 32), weight: .medium)).foregroundStyle(accent.color)
                    .frame(width: inputControlHeight, height: inputControlHeight)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("chat.attachments", in: attachmentNamespace ?? localAttachmentNamespace)
                    .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
            }.buttonStyle(.plain).disabled(preparingMedia || stickerSender.busy)
                .accessibilityLabel("相机、照片、贴纸或表情")
                .accessibilityIdentifier("chat.attachments.open")
        }
    }
    private var textSelection: Binding<TextSelection?> {
        Binding(get: { selection }, set: { value in
            selection = value
            if let value, case .selection(let range) = value.indices {
                let boundaries = Set(store.draft.indices).union([store.draft.endIndex])
                if boundaries.contains(range.lowerBound), boundaries.contains(range.upperBound) {
                    caret = NSRange(range, in: store.draft)
                }
            }
        })
    }
    private func open(_ mode: ChatExpressionTab) { open(.expressions(mode)) }
    private func open(_ panel: ChatComposerDrawer) {
        focus.wrappedValue = false; pendingPhotos = []
        drawerDetent = dynamicType.isAccessibilitySize ? .large : compactDrawerDetent
        drawer = panel
    }
    private func insertEmoji(_ item: NotoEmoji) -> Bool {
        guard !stickerSender.busy else { return false }
        let result = ChatEmojiInsertion.insert(item.emoji, into: store.draft, selection: caret)
        store.draft = result.text
        let next = ComposerReferenceInsertion.safeSelection(NSRange(location: result.caretUTF16, length: 0), in: result.text)
        caret = next
        if let range = Range(next, in: result.text) { selection = TextSelection(insertionPoint: range.lowerBound) }
        return true
    }
    private func cancelSticker() { sendTask?.cancel(); stickerSender.cancel(); stagedSticker = nil }
    private func send() {
        guard !stickerSender.busy, sendTask == nil else { return }
        let text = store.draft, quoteID = quote?.id
        guard let staged = stagedSticker else {
            if store.enqueue(content: text, quoteID: quoteID) { finishSend(text: text, quoteID: quoteID) }
            return
        }
        sendTask = Task {
            defer { sendTask = nil }
            let accepted = await stickerSender.send(staged, caption: text, quoteID: quoteID,
                isValid: { session.api.generation == accountEpoch && session.api.token != nil },
                upload: { data in
                    try await session.api.upload(data, filename: "noto-sticker-\(UUID()).png", mime: "image/png", type: "chat")
                }, enqueue: { sticker, caption, quoteID in store.enqueueSticker(sticker, caption: caption, quoteID: quoteID) })
            if accepted {
                if stagedSticker?.id == staged.id { stagedSticker = nil }
                finishSend(text: text, quoteID: quoteID)
            }
        }
    }
    private func finishSend(text: String, quoteID: Int?) {
        if store.draft == text { store.draft = ""; selection = nil; caret = nil; store.saveDraft() }
        if quote?.id == quoteID { quote = nil }
    }
}
