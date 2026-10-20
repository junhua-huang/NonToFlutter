import SwiftUI
import PhotosUI

struct FeedView: View {
    @ObservedObject var session: AppSession
    @Environment(\.openComposer) private var compose
    @State private var filter = 0
    private var path: String { filter == 0 ? "/recommendations/feed" : (filter == 1 ? "/posts/" : "/posts/related-to-me") }
    var body: some View {
        PostList(session: session, path: path).id(filter)
        .safeAreaInset(edge: .top, spacing: 0) {
            TimelineTabs(title: "动态范围", tabs: [(0, "推荐"), (1, "最新"), (2, "与你相关")], selection: $filter)
        }
        .navigationTitle("南图").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                RouteButton(.profile(session.user?.id ?? 0)) {
                    AvatarView(url: session.user?.avatar ?? "", name: session.user?.name ?? "", size: 30)
                }.buttonStyle(.plain).accessibilityLabel("我的主页")
            }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) { Text("南图").font(.headline.weight(.heavy)).foregroundStyle(Color.brand) }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: compose) {
                    Image(systemName: "square.and.pencil").font(.system(size: 18, weight: .medium))
                        .frame(width: 28, height: 28)
                }.controlSize(.small)
                    .accessibilityLabel("发布动态")
            }
        }
    }
}

struct PostList: View {
    @StateObject private var resource: PagedResource<Post>
    @EnvironmentObject private var session: AppSession
    private let header: AnyView?
    init(session: AppSession, path: String, query: [String: String] = [:], header: AnyView? = nil) {
        self.header = header
        _resource = StateObject(wrappedValue: PagedResource(api: session.api, path: path, keys: ["posts", "items"], query: query, userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            if let header { header.listRowInsets(EdgeInsets()).listRowSeparator(.hidden) }
            ForEach(resource.items) { post in PostCard(post: post).timelinePostRow() }
            ResourceFooter(resource: resource, emptyTitle: "还没有动态", emptyDescription: "分享此刻的想法，或下拉刷新看看。", emptyIcon: "text.bubble")
        }.timelineList().scrollDismissesKeyboard(.interactively)
            .refreshable { await resource.load(reset: true) }
            .task { await resource.loadIfNeeded() }
            .onReceive(session.$postRevision.dropFirst()) { _ in Task { await resource.load(reset: true) } }
            .onReceive(session.$postChange.dropFirst().compactMap { $0 }) { change in
                let removeUnliked = resource.path == "/posts/user/\(session.user?.id ?? 0)/liked" && change.patch?["is_liked"] == .bool(false)
                resource.apply(id: change.postID, patch: removeUnliked ? nil : change.patch)
            }
    }
}

struct PostCard: View {
    let post: Post
    var detailed = false
    var onComment: (() -> Void)? = nil
    @EnvironmentObject private var session: AppSession
    @State private var current: Post
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var quoting = false
    @State private var sharing = false
    @State private var reporting = false
    @State private var deleting = false
    init(post: Post, detailed: Bool = false, onComment: (() -> Void)? = nil) {
        self.post = post; self.detailed = detailed; self.onComment = onComment; _current = State(initialValue: post)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                let thread = PostThread.items(from: current)
                if detailed && thread.count == 1 { detailContent }
                else {
                    ForEach(thread) { item in
                        threadRow(item.post, isRoot: item.id == current.id, continues: item.id != thread.last?.id)
                    }
                }
                let inset: CGFloat = detailed && thread.count == 1 ? 0 : 52
                postActions.padding(.leading, inset)
                if error != nil { ErrorBanner(text: error).padding(.leading, inset) }
            }.frame(maxWidth: 720).padding(.horizontal, 16).padding(.top, 12).frame(maxWidth: .infinity)
            Color.timelineSeparator.frame(height: 0.5)
        }.background(Color.timelineBackground).navigationLinkIndicatorVisibility(.hidden)
            .onChange(of: post.raw) { _, raw in current = Post(raw) }
            .onReceive(session.$postChange.dropFirst().compactMap { $0 }) { change in
                if change.postID == current.id, let patch = change.patch { current = Post(current.raw.merging(patch)) }
            }
            .sheet(isPresented: $editing) { PostComposer(editing: current) }
            .sheet(isPresented: $quoting) { PostComposer(quoted: current) }
            .sheet(isPresented: $sharing) { SharePostView(session: session, post: current) }
            .sheet(isPresented: $reporting) { ReportView(kind: "post", targetID: current.id) }
            .confirmationDialog("删除这条动态？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除动态", role: .destructive) {
                    Task {
                        do { _ = try await session.api.request("/posts/\(current.id)", method: "DELETE"); session.postChange = PostChange(postID: current.id, patch: nil) }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
    }
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RouteButton(.profile(current.userID)) {
                    AvatarView(url: current.author.avatar, name: current.author.name, size: 42)
                }.frame(width: 42, height: 42).accessibilityLabel("查看\(current.author.name)的主页")
                authorHeader(current, showsMenu: true)
            }
            PostBodyText(content: current.content, detailed: true)
            if !current.images.isEmpty || !current.video.isEmpty {
                MediaView(images: current.images, video: current.video, postLayout: true)
            }
            if let date = current.date {
                Text(date, format: .dateTime.hour().minute().day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            if current.raw["quoted_post_unavailable"].bool || current.raw["quoted_post"]["unavailable"].bool {
                Label("原动态已不可见", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.bottom, 4)
    }
    private func threadRow(_ item: Post, isRoot: Bool, continues: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                RouteButton(.profile(item.userID)) {
                    AvatarView(url: item.author.avatar, name: item.author.name, size: 42)
                }.frame(width: 42, height: 42).accessibilityLabel("查看\(item.author.name)的主页")
                if continues {
                    Rectangle().fill(Color.timelineSeparator).frame(width: 2)
                        .frame(maxHeight: .infinity).padding(.top, 4).accessibilityHidden(true)
                }
            }.frame(width: 42)
            VStack(alignment: .leading, spacing: 4) {
                authorHeader(item, showsMenu: isRoot)
                PostBodyText(content: item.content, detailed: detailed && isRoot,
                             route: detailed && isRoot ? nil : .post(item.id, initial: item))
                if !item.images.isEmpty || !item.video.isEmpty {
                    MediaView(images: item.images, video: item.video, postLayout: true).padding(.top, 4)
                }
                if detailed && isRoot, let date = item.date {
                    Text(date, format: .dateTime.hour().minute().day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                if item.raw["quoted_post_unavailable"].bool || item.raw["quoted_post"]["unavailable"].bool {
                    Label("原动态已不可见", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, continues ? 12 : 0)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func authorHeader(_ item: Post, showsMenu: Bool) -> some View {
        HStack(spacing: 4) {
            RouteButton(.profile(item.userID)) {
                HStack(spacing: 4) {
                    Text(item.author.name).font(.subheadline.bold()).foregroundStyle(.primary)
                        .lineLimit(1).layoutPriority(1)
                    if !item.raw["display_role_label"].string.isEmpty {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.brand).font(.caption)
                            .accessibilityLabel(item.raw["display_role_label"].string)
                    }
                    Text("@\(item.author.username)").font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.visibilityForEdit == "friends" {
                Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("仅好友可见")
            }
            if !detailed, let date = item.date {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            if showsMenu { postMenu }
        }.frame(minHeight: 24).lineLimit(1)
    }
    private var postMenu: some View {
        Menu {
            Button("引用动态", systemImage: "quote.bubble") { quoting = true }
            Button("分享给好友", systemImage: "paperplane") { sharing = true }
            if let url = URL(string: "https://www.nonto.online/posts/\(current.id)") {
                ShareLink(item: url) { Label("系统分享", systemImage: "square.and.arrow.up") }
            }
            if current.userID == session.user?.id {
                Button("编辑", systemImage: "pencil") { editing = true }
                Button("删除", systemImage: "trash", role: .destructive) { deleting = true }
            } else { Button("举报", systemImage: "flag") { reporting = true } }
        } label: {
            Image(systemName: "ellipsis").font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("动态操作")
    }
    private var postActions: some View {
        HStack(spacing: 0) {
            Group {
                if let onComment { Button(action: onComment) { TimelineActionSymbol(symbol: "bubble", count: current.comments) } }
                else { RouteButton(.post(current.id, initial: current)) { TimelineActionSymbol(symbol: "bubble", count: current.comments) } }
            }.accessibilityLabel("评论，\(current.comments) 条")
            Button { quoting = true } label: { TimelineActionSymbol(symbol: "arrow.2.squarepath") }
                .accessibilityLabel("引用动态")
            Button { Task { await toggleLike() } } label: {
                TimelineActionSymbol(symbol: current.liked ? "heart.fill" : "heart", count: current.likes)
                    .foregroundStyle(current.liked ? Color.brandLike : Color.secondary)
            }.disabled(busy).accessibilityLabel("\(current.liked ? "取消点赞" : "点赞")，\(current.likes) 个赞")
            Button { sharing = true } label: { TimelineActionSymbol(symbol: "square.and.arrow.up") }
                .accessibilityLabel("分享动态")
        }.foregroundStyle(.secondary).buttonStyle(.plain)
    }
    private func toggleLike() async {
        guard !busy else { return }
        let liked = !current.liked
        let fallbackCount = max(0, current.likes + (liked ? 1 : -1))
        busy = true; error = nil; defer { busy = false }
        do {
            let result = try await session.api.request("/posts/\(current.id)/like", method: liked ? "POST" : "DELETE")
            let fallback: JSON = .object(["is_liked": .bool(liked), "like_count": .id(fallbackCount)])
            let patch = fallback.merging(result["post"].or(result))
            current = Post(current.raw.merging(patch))
            session.postChange = PostChange(postID: current.id, patch: patch)
        } catch { self.error = error.localizedDescription }
    }
}

struct PostDetailView: View {
    let postID: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @StateObject private var comments: PagedResource<Comment>
    @State private var post: Post?
    @State private var error: String?
    @State private var text = ""
    @State private var reply: Comment?
    @State private var sending = false
    @FocusState private var commentFocused: Bool
    init(session: AppSession, postID: Int, initial: Post? = nil) {
        self.postID = postID; _post = State(initialValue: initial)
        _comments = StateObject(wrappedValue: PagedResource(api: session.api, path: "/posts/\(postID)/comments", keys: ["comments", "items"], userID: session.user?.id ?? 0))
    }
    var body: some View {
        List {
            if let post { PostCard(post: post, detailed: true, onComment: { commentFocused = true }).timelinePostRow() }
            if error != nil { ErrorBanner(text: error) }
            Section("回复") {
                ForEach(comments.items) { comment in CommentRow(comment: comment, postID: postID, onReply: { reply = $0; commentFocused = true }, onChange: { Task { await comments.load(reset: true) } }) }
                ResourceFooter(resource: comments, emptyTitle: "还没有回复", emptyDescription: "说说你的想法，成为第一个回复的人。", emptyIcon: "bubble.left", compactEmpty: true)
            }
        }.timelineList().navigationTitle("动态").navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let reply { HStack { Text("回复 @\(reply.author.username)").font(.caption); Spacer(); Button("取消") { self.reply = nil } }.padding(.horizontal) }
                    HStack {
                        TextField("说点什么…", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.plain).padding(.vertical, 10).padding(.leading, 8).focused($commentFocused).accessibilityLabel("评论内容")
                        Button { Task { await send() } } label: { if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) } }.frame(width: 44, height: 44).disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送评论")
                    }.floatingGlass()
                }.padding(.top, 8).background(Color.timelineBackground)
            }
            .task { await load(); _ = try? await session.api.request("/posts/\(postID)/view", method: "POST") }
            .refreshable { await load() }
            .onReceive(session.$postRevision.dropFirst()) { _ in Task { await load() } }
            .onReceive(session.$postChange.dropFirst().compactMap { $0 }) { change in
                guard change.postID == postID else { return }
                if let patch = change.patch { post = Post((post?.raw ?? .object([:])).merging(patch)) }
                else { dismiss() }
            }
            .scrollDismissesKeyboard(.interactively)
    }
    private func load() async {
        do { let j = try await session.api.request("/posts/\(postID)"); post = Post(j["post"].or(j)); error = nil }
        catch { self.error = error.localizedDescription }
        await comments.load(reset: true)
    }
    private func send() async {
        guard !sending else { return }
        let submittedText = text, submittedReplyID = reply?.id
        sending = true; error = nil; defer { sending = false }
        do {
            var body: [String: JSON] = ["content": .text(text.trimmingCharacters(in: .whitespacesAndNewlines))]
            if let reply { body["parent_id"] = reply.raw["parent_id"].isNull ? .id(reply.id) : reply.raw["parent_id"]; body["reply_to_user_id"] = .id(reply.author.id) }
            _ = try await session.api.request("/posts/\(postID)/comments", method: "POST", body: .object(body))
            if text == submittedText {
                text = ""
                if reply?.id == submittedReplyID { reply = nil }
            }
            if let post { session.postChange = PostChange(postID: postID, patch: .object(["comment_count": .id(post.comments + 1)])) }
            await comments.load(reset: true)
        } catch { self.error = error.localizedDescription }
    }
}

struct CommentRow: View {
    let comment: Comment
    let postID: Int
    var onReply: (Comment) -> Void
    var onChange: () -> Void
    @EnvironmentObject private var session: AppSession
    @State private var extraReplies: [Comment] = []
    @State private var repliesPage = 1
    @State private var repliesMore = true
    @State private var error: String?
    @State private var busy = false
    @State private var report = false
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(comment)
            ForEach(Records.unique(comment.replies + extraReplies)) { reply in row(reply).padding(.leading, 28) }
            if repliesMore && (comment.raw["replies_has_more"].bool || comment.raw["reply_count"].int > comment.replies.count + extraReplies.count) {
                Button("查看更多回复") { Task { await moreReplies() } }.font(.caption).disabled(busy)
            }
            ErrorBanner(text: error)
        }.padding(.vertical, 8)
            .sheet(isPresented: $report) { ReportView(kind: "comment", targetID: comment.id) }
            .confirmationDialog("删除评论？", isPresented: $deleting) {
                Button("删除", role: .destructive) { Task { await mutate(comment, method: "DELETE") } }
            }
    }
    private func row(_ item: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RouteButton(.profile(item.author.id)) {
                AvatarView(url: item.author.avatar, name: item.author.name, size: 34)
            }.buttonStyle(.plain).frame(width: 34, height: 34).accessibilityLabel("查看\(item.author.name)的主页")
            VStack(alignment: .leading, spacing: 6) {
                RouteButton(.profile(item.author.id)) {
                    Text(item.author.name).font(.subheadline.bold()).foregroundStyle(.primary)
                }.buttonStyle(.plain)
                Text(item.content).font(.body).lineSpacing(3).textSelection(.enabled)
                HStack(spacing: 20) {
                    Button("回复") { onReply(item) }.frame(minHeight: 44)
                    Button { Task { await mutate(item, method: item.raw["is_liked"].bool ? "DELETE" : "POST", suffix: "/like") } } label: {
                        Label("\(item.raw["like_count"].int)", systemImage: item.raw["is_liked"].bool ? "heart.fill" : "heart")
                            .frame(minHeight: 44).foregroundStyle(item.raw["is_liked"].bool ? Color.brandLike : Color.secondary)
                    }.disabled(busy)
                    Spacer(minLength: 0)
                    if item.id == comment.id {
                        Menu {
                            if item.raw["user_id"].int == session.user?.id { Button("删除", role: .destructive) { deleting = true } }
                            else { Button("举报") { report = true } }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("评论操作")
                    }
                }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func mutate(_ item: Comment, method: String, suffix: String = "") async {
        busy = true; defer { busy = false }
        do { _ = try await session.api.request("/comments/\(item.id)\(suffix)", method: method); onChange() }
        catch { self.error = error.localizedDescription }
    }
    private func moreReplies() async {
        busy = true; defer { busy = false }
        do {
            let next = extraReplies.isEmpty ? max(2, comment.raw["replies_page"].int + 1) : repliesPage + 1
            let j = try await session.api.request("/posts/\(postID)/comments", query: ["parent_id": String(comment.id), "page": String(next), "per_page": "10"])
            let rows = j.list("comments", "items").map(Comment.init)
            extraReplies = Records.unique(extraReplies + rows); repliesPage = next
            repliesMore = j["has_more"].isNull ? rows.count >= 10 : j["has_more"].bool
        } catch { self.error = error.localizedDescription }
    }
}

struct PostComposer: View {
    var editing: Post? = nil
    var quoted: Post? = nil
    var communityID: Int? = nil
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var visibility = "public"
    @State private var role = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var media: [SelectedMedia] = []
    @State private var uploaded: [UUID: String] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var reading = false
    @State private var status = ""
    @State private var published = false
    @State private var draftLoaded = false
    @State private var accountID = 0
    @State private var accountEpoch: UUID?
    @State private var confirmClose = false
    @State private var draftSaveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    private var hasChanges: Bool {
        if let editing { return text != editing.content || visibility != editing.visibilityForEdit }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.isEmpty || quoted != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(url: session.user?.avatar ?? "", name: session.user?.name ?? "", size: 42)
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("有什么新鲜事？", text: $text, axis: .vertical)
                                .font(.title3).lineSpacing(4).lineLimit(6...20)
                                .textFieldStyle(.plain).accessibilityLabel("动态内容")
                            if let quoted {
                                Label("引用 @\(quoted.author.username)：\(quoted.content)", systemImage: "quote.bubble")
                                    .font(.subheadline).lineLimit(4).padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.timelineSeparator, lineWidth: 1))
                            }
                        }
                    }
                    if editing == nil {
                        ForEach(media) { item in
                            HStack(spacing: 12) {
                                if !item.isVideo, let image = UIImage(data: item.data) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72)
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                } else { Image(systemName: "video").font(.title).frame(width: 72, height: 72) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.isVideo ? "视频" : "照片").font(.subheadline.bold())
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) { media.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }.accessibilityLabel(item.isVideo ? "移除视频" : "移除照片").disabled(busy)
                            }
                        }
                        if reading { ProgressView("正在准备媒体…") }
                    }
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            mediaPicker
                            Spacer()
                            visibilityPicker
                        }
                        VStack(alignment: .leading, spacing: 12) { mediaPicker; visibilityPicker }
                    }
                    if editing == nil, let user = session.user, !user.raw["verified_roles"].array.isEmpty {
                        Picker("展示身份", selection: $role) {
                            Text("不展示").tag("")
                            ForEach(Array(user.raw["verified_roles"].array.enumerated()), id: \.offset) { i, value in
                                Text(user.verifiedLabels.indices.contains(i) ? user.verifiedLabels[i] : value.string).tag(value.string)
                            }
                        }.pickerStyle(.menu)
                    }
                    if !status.isEmpty { ProgressView(status) }
                    if error != nil { ErrorBanner(text: error) }
                    if editing == nil { Text("文字自动保存为草稿").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .top)
            }.disabled(busy).scrollDismissesKeyboard(.interactively)
                .navigationTitle(editing == nil ? "发布动态" : "编辑动态").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if hasChanges { confirmClose = true } else { dismiss() } }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button(editing == nil ? "发布" : "保存") { Task { await publish() } }.disabled(busy || reading || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && media.isEmpty && quoted == nil && editing?.images.isEmpty != false && editing?.video.isEmpty != false)) }
                }.interactiveDismissDisabled(busy || !media.isEmpty || (editing != nil && hasChanges))
                .confirmationDialog(editing == nil ? "关闭发布？" : "放弃尚未保存的修改？", isPresented: $confirmClose, titleVisibility: .visible) {
                    if editing == nil {
                        Button("保存文字草稿并关闭") { saveDraft(); dismiss() }
                    }
                    Button(editing == nil ? "放弃本次内容" : "放弃修改", role: .destructive) {
                        draftSaveTask?.cancel()
                        if editing == nil { published = true; clearDraft() }
                        dismiss()
                    }
                    Button("继续编辑", role: .cancel) {}
                } message: {
                    if editing == nil && !media.isEmpty { Text("照片和视频不会保存在文字草稿中。") }
                }
                .onAppear {
                    guard !draftLoaded else { return }; draftLoaded = true
                    accountID = session.user?.id ?? 0; accountEpoch = session.api.generation
                    let saved = PostDraftStore().read(userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0, defaultVisibility: session.defaultVisibility)
                    text = editing?.content ?? saved.text
                    visibility = editing?.visibilityForEdit ?? saved.visibility
                    let roles = session.user?.raw["verified_roles"].array.map(\.string) ?? []
                    role = roles.contains(saved.role) ? saved.role : ""
                }
                .onDisappear { saveDraft() }
                .onChange(of: [text, visibility, role]) { _, _ in
                    draftSaveTask?.cancel()
                    draftSaveTask = Task {
                        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                        saveDraft()
                    }
                }
                .onChange(of: phase) { _, value in if value != .active { saveDraft() } }
                .task(id: picks) {
                    guard !picks.isEmpty else { return }; reading = true; defer { reading = false }
                    do {
                        var result: [SelectedMedia] = []
                        for pick in picks { try Task.checkCancellation(); result.append(try await MediaLoader.load(pick)) }
                        guard result.filter(\.isVideo).count <= 1, !result.contains(where: \.isVideo) || result.count == 1 else { throw APIError(status: 0, message: "视频请单独发布，每次一段") }
                        media = result
                    } catch is CancellationError {} catch { self.error = error.localizedDescription }
                }
        }
    }
    @ViewBuilder private var mediaPicker: some View {
        if editing == nil {
            PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                Label("照片 / 视频", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline).frame(minHeight: 44)
            }.disabled(busy || reading)
        }
    }
    private var visibilityPicker: some View {
        Picker("谁可以看", selection: $visibility) {
            Label("公开", systemImage: "globe.asia.australia").tag("public")
            Label("仅好友", systemImage: "person.2").tag("friends")
        }.pickerStyle(.menu).font(.subheadline)
    }
    private func saveDraft() {
        draftSaveTask?.cancel(); draftSaveTask = nil
        if accountID > 0 && accountEpoch == session.api.generation && editing == nil && !published {
            PostDraftStore().save(PostDraft(text: text, visibility: visibility, role: role), userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0)
        }
    }
    private func clearDraft() {
        draftSaveTask?.cancel(); draftSaveTask = nil
        PostDraftStore().remove(userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0)
    }
    private func checkAccount() throws {
        try Task.checkCancellation()
        guard accountEpoch == session.api.generation, accountID == session.user?.id else { throw APIError.sessionChanged }
    }
    private func publish() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false; status = "" }
        do {
            try checkAccount()
            if let editing {
                let patch: JSON = .object(["content": .text(text), "visibility": .text(visibility)])
                let result = try await session.api.request("/posts/\(editing.id)", method: "PUT", body: patch)
                session.postChange = PostChange(postID: editing.id, patch: patch.merging(result["post"].or(result)))
            } else {
                var fields: [String: String] = ["content": text, "visibility": visibility]
                var images: [String] = []
                for (i, item) in media.enumerated() {
                    try checkAccount()
                    status = "上传媒体 \(i + 1)/\(media.count)…"
                    let url: String
                    if let existing = uploaded[item.id] { url = existing }
                    else { url = try await session.api.upload(item.data, filename: item.name, mime: item.mime); uploaded[item.id] = url }
                    if item.isVideo { fields["video_url"] = url } else { images.append(url) }
                }
                if !images.isEmpty { fields["image_urls"] = String(decoding: try JSON.array(images.map(JSON.text)).encoded(), as: UTF8.self) }
                if !role.isEmpty { fields["display_role_type"] = role }
                if let communityID { fields["community_id"] = String(communityID) }
                if let quoted { fields["quoted_post_id"] = String(quoted.id) }
                try checkAccount()
                status = "正在发布…"
                _ = try await session.api.request("/posts", method: "POST", form: fields)
                clearDraft()
            }
            published = true
            if editing == nil { session.postRevision += 1 }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
