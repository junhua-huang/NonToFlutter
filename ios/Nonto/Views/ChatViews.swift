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
                        if conversation.unread > 0 { Text("\(conversation.unread)").font(.caption.bold()).padding(6).background(.brand, in: Capsule()).foregroundStyle(.white) }
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

struct PendingMessage: Codable, Identifiable {
    var id: String = UUID().uuidString
    var content: String
    var kind = "text"
    var media: String? = nil
    var quoteID: Int? = nil
    var failure: String? = nil
}

struct ChatRoomView: View {
    let conversation: Conversation
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    @State private var messages: [ChatMessage] = []
    @State private var pending: [PendingMessage] = []
    @State private var text = ""
    @State private var error: String?
    @State private var loading = false
    @State private var sending = false
    @State private var page = 1
    @State private var more = true
    @State private var roomID = 0
    @State private var quote: ChatMessage?
    @State private var pick: PhotosPickerItem?
    @State private var scrollTarget: Int?
    @State private var recall: ChatMessage?
    @State private var confirmRecall = false
    private var communityID: Int? { conversation.isCommunity ? conversation.communityID : nil }
    private var cacheKey: String { "chat.\(communityID == nil ? "single" : "community").\(communityID ?? conversation.id)" }
    private var outboxKey: String { "nonto.native.outbox.\(session.user?.id ?? 0).\(cacheKey)" }
    private var path: String { if let communityID { return "/communities/\(communityID)/chat" }; return "/chat/conversations/\(conversation.id)/messages" }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if more { Button("加载更早的消息") { Task { await load(older: true) } }.disabled(loading).padding(.top) }
                    if loading { ProgressView() }
                    ErrorBanner(text: error) { Task { await load() } }.padding(.horizontal)
                    ForEach(messages) { message in
                        messageRow(message).id(message.id)
                    }
                    ForEach(pending) { item in
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(item.content.isEmpty ? "[媒体消息]" : item.content).padding(12).background(.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                            if let failure = item.failure {
                                Text(failure).font(.caption).foregroundStyle(.red)
                                HStack { Button("重试") { Task { await deliver(item) } }.disabled(sending); Button("移除", role: .destructive) { pending.removeAll { $0.id == item.id }; savePending() } }.font(.caption)
                            } else { ProgressView("待发送").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.bottom)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: scrollTarget) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: pending.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .navigationTitle(conversation.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let quote { HStack { Text("引用：\(quote.content)").lineLimit(1).font(.caption); Spacer(); Button("取消") { self.quote = nil } }.padding(.horizontal) }
                HStack(alignment: .bottom) {
                    PhotosPicker(selection: $pick, matching: .any(of: [.images, .videos])) { Image(systemName: "plus.circle").font(.title2) }.disabled(sending)
                    TextField("发送消息…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                    Button { enqueue() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送消息")
                }.floatingGlass()
                if sending { ProgressView("正在发送…").font(.caption).padding(.horizontal) }
            }.padding(.top, 8)
        }
        .task {
            roomID = conversation.id
            NativeNotifications.shared.activeConversation = roomID
            if let cached = LocalCache.read(userID: session.user?.id ?? 0, key: cacheKey) { messages = Records.messages([], cached.array.map(ChatMessage.init)) }
            if let data = UserDefaults.standard.data(forKey: outboxKey), let saved = try? JSONDecoder().decode([PendingMessage].self, from: data) { pending = saved }
            await load(); await flushPending()
            // Refresh while visible to recover even if a socket reconnect loses an event.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if phase == .active { await load() }
            }
        }
        .onDisappear { session.socket.room(roomID, joined: false); NativeNotifications.shared.activeConversation = nil; savePending(); Task { await session.refreshCounts() } }
        .onChange(of: phase) { _, value in if value == .active { Task { await load(); await flushPending() } } }
        .task(id: pick) {
            guard let pick else { return }; sending = true
            do {
                let media = try await MediaLoader.load(pick)
                let url = try await session.api.upload(media.data, filename: media.name, mime: media.mime)
                let item = PendingMessage(content: "", kind: media.isVideo ? "video" : "image", media: url)
                pending.append(item); savePending(); sending = false; await deliver(item)
            } catch { self.error = error.localizedDescription; sending = false }
            self.pick = nil
        }
        .confirmationDialog("撤回这条消息？", isPresented: $confirmRecall) {
            Button("撤回", role: .destructive) { if let recall { Task { await recallMessage(recall) } } }
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
    private func load(older: Bool = false) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        let epoch = session.api.generation
        do {
            var query = ["per_page": "50", "page": String(older ? page + 1 : 1)]
            if communityID != nil {
                query = ["limit": "50"]
                if older, let first = messages.map(\.id).filter({ $0 > 0 }).min() { query["before_id"] = String(first) }
            }
            let j = try await session.api.request(path, query: query)
            guard session.api.generation == epoch else { return }
            let rows = j.list("messages", "items").map(ChatMessage.init)
            let last = messages.last?.id
            messages = Records.messages(messages, rows)
            if older { page += 1; more = rows.count >= 50 }
            else if page == 1 { more = rows.count >= 50 }
            if communityID != nil, j["conversation"]["id"].int > 0 { roomID = j["conversation"]["id"].int }
            if roomID > 0 { session.socket.room(roomID, joined: true); NativeNotifications.shared.activeConversation = roomID }
            // Reconcile a response lost after server acceptance using the idempotency key.
            let confirmed = Set(rows.flatMap { [$0.raw["request_id"].string, $0.raw["client_msg_id"].string] }.filter { !$0.isEmpty })
            pending.removeAll { confirmed.contains($0.id) }; savePending()
            LocalCache.write(.array(Array(messages.suffix(500)).map(\.raw)), userID: session.user?.id ?? 0, key: cacheKey)
            if !older && messages.last?.id != last { scrollTarget = messages.last?.id }
            if roomID > 0 { _ = try? await session.api.request("/chat/conversations/\(roomID)/mark-read", method: "POST") }
            error = nil
        } catch { if (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription } }
    }
    private func enqueue() {
        let item = PendingMessage(content: text.trimmingCharacters(in: .whitespacesAndNewlines), quoteID: quote?.id)
        pending.append(item); text = ""; quote = nil; savePending()
        Task { await deliver(item) }
    }
    private func savePending() { if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: outboxKey) } }
    private func flushPending() async { for item in pending where item.failure == nil { await deliver(item) } }
    private func deliver(_ item: PendingMessage) async {
        guard !sending else { return }; sending = true; defer { sending = false }
        do {
            var body: [String: JSON] = ["content": .text(item.content), "message_type": .text(item.kind)]
            body[communityID == nil ? "request_id" : "client_msg_id"] = .text(item.id)
            if let media = item.media { body["media_url"] = .text(media) }
            if let quoteID = item.quoteID { body["quote_message_id"] = .id(quoteID) }
            let endpoint = communityID == nil ? path : path + "/messages"
            let j = try await session.api.request(endpoint, method: "POST", body: .object(body))
            let message = ChatMessage(j["message"].or(j))
            if message.id > 0 { messages = Records.messages(messages, [message]); scrollTarget = message.id }
            pending.removeAll { $0.id == item.id }; savePending(); await load()
        } catch {
            if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].failure = error.localizedDescription; savePending() }
        }
    }
    private func recallMessage(_ message: ChatMessage) async {
        guard let communityID else { return }
        do { _ = try await session.api.request("/communities/\(communityID)/chat/messages/\(message.id)", method: "DELETE"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct SharePostView: View {
    let post: Post
    @StateObject private var resource: PagedResource<Conversation>
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var error: String?
    @State private var requestID = UUID().uuidString
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
        do {
            let path = conv.isCommunity ? "/communities/\(conv.communityID ?? 0)/chat/messages" : "/chat/conversations/\(conv.id)/messages"
            _ = try await session.api.request(path, method: "POST", body: .object([
                "content": .text(post.content), "message_type": .text("post"), "related_id": .id(post.id),
                conv.isCommunity ? "client_msg_id" : "request_id": .text(requestID)]))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
