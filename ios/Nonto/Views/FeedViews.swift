import SwiftUI
import PhotosUI

struct FeedView: View {
    let session: AppSession
    @Environment(\.openComposer) private var compose
    @State private var filter = 0
    private var path: String { filter == 0 ? "/recommendations/feed" : (filter == 1 ? "/posts/" : "/posts/related-to-me") }
    var body: some View {
        VStack(spacing: 0) {
            Picker("动态范围", selection: $filter) { Text("推荐").tag(0); Text("最新").tag(1); Text("与我相关").tag(2) }.pickerStyle(.segmented).padding()
            PostList(session: session, path: path).id(filter)
        }
        .navigationTitle("南图")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { NavigationLink { CommunityListView(session: session) } label: { Image(systemName: "person.3") }.accessibilityLabel("社群") }
            ToolbarItem(placement: .topBarTrailing) { Button(action: compose) { Image(systemName: "square.and.pencil") }.accessibilityLabel("发布动态") }
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
            ForEach(resource.items) { post in PostCard(post: post).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
            ResourceFooter(resource: resource, emptyTitle: "还没有动态", emptyDescription: "分享此刻的想法，或下拉刷新看看。", emptyIcon: "text.bubble")
        }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
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
    @EnvironmentObject private var session: AppSession
    @State private var current: Post
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var quoting = false
    @State private var sharing = false
    @State private var reporting = false
    @State private var deleting = false
    init(post: Post, detailed: Bool = false) {
        self.post = post; self.detailed = detailed; _current = State(initialValue: post)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                NavigationLink { ProfileView(userID: current.userID) } label: {
                    HStack(spacing: 10) {
                        AvatarView(url: current.author.avatar, name: current.author.name)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(current.author.name).font(.headline)
                                if !current.raw["display_role_label"].string.isEmpty { Text(current.raw["display_role_label"].string).font(.caption2).foregroundStyle(Color.brand) }
                            }
                            HStack(spacing: 5) {
                                if let date = current.date { Text(date, style: .relative) }
                                if current.visibilityForEdit == "friends" { Image(systemName: "person.2.fill") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("引用动态", systemImage: "quote.bubble") { quoting = true }
                    Button("分享给好友", systemImage: "paperplane") { sharing = true }
                    if let url = URL(string: "https://www.nonto.online/posts/\(current.id)") { ShareLink(item: url) { Label("系统分享", systemImage: "square.and.arrow.up") } }
                    if current.userID == session.user?.id {
                        Button("编辑", systemImage: "pencil") { editing = true }
                        Button("删除", systemImage: "trash", role: .destructive) { deleting = true }
                    } else { Button("举报", systemImage: "flag") { reporting = true } }
                } label: { Image(systemName: "ellipsis").padding(8).contentShape(Rectangle()) }.accessibilityLabel("动态操作")
            }
            if !current.content.isEmpty {
                if detailed { Text(current.content).textSelection(.enabled) }
                else { NavigationLink { PostDetailView(session: session, postID: current.id, initial: current) } label: { Text(current.content).lineLimit(8).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary) }.buttonStyle(.plain) }
            }
            MediaView(images: current.images, video: current.video)
            if let quote = current.quoted {
                NavigationLink { PostDetailView(session: session, postID: quote.id, initial: quote) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("引用 @\(quote.author.username)").font(.caption).foregroundStyle(.secondary)
                        Text(quote.content).lineLimit(4).foregroundStyle(.primary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            } else if current.raw["quoted_post_unavailable"].bool || current.raw["quoted_post"]["unavailable"].bool {
                Label("原动态已不可见", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                Button { Task { await toggleLike() } } label: { Label("\(current.likes)", systemImage: current.liked ? "heart.fill" : "heart").foregroundStyle(current.liked ? Color.brandLike : Color.secondary) }.disabled(busy)
                NavigationLink { PostDetailView(session: session, postID: current.id, initial: current) } label: { Label("\(current.comments)", systemImage: "bubble.right").foregroundStyle(.secondary) }
                Spacer()
                Button { sharing = true } label: { Image(systemName: "paperplane").foregroundStyle(.secondary) }.accessibilityLabel("分享动态")
            }.font(.subheadline).buttonStyle(.plain)
            ErrorBanner(text: error)
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 0.5))
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
            if let post { PostCard(post: post, detailed: true).listRowSeparator(.hidden) }
            ErrorBanner(text: error)
            Section("评论") {
                ForEach(comments.items) { comment in CommentRow(comment: comment, postID: postID, onReply: { reply = $0; commentFocused = true }, onChange: { Task { await comments.load(reset: true) } }) }
                ResourceFooter(resource: comments)
            }
        }.listStyle(.plain).navigationTitle("动态详情").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if let reply { HStack { Text("回复 @\(reply.author.username)").font(.caption); Spacer(); Button("取消") { self.reply = nil } }.padding(.horizontal) }
                    HStack {
                        TextField("说点什么…", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).focused($commentFocused).accessibilityLabel("评论内容")
                        Button { Task { await send() } } label: { if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) } }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送评论")
                    }.floatingGlass()
                }.padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink { ProfileView(userID: item.author.id) } label: { HStack { AvatarView(url: item.author.avatar, name: item.author.name, size: 28); Text(item.author.name).font(.subheadline.weight(.semibold)) } }.buttonStyle(.plain)
            Text(item.content).textSelection(.enabled)
            HStack(spacing: 22) {
                Button("回复") { onReply(item) }
                Button { Task { await mutate(item, method: item.raw["is_liked"].bool ? "DELETE" : "POST", suffix: "/like") } } label: { Label("\(item.raw["like_count"].int)", systemImage: item.raw["is_liked"].bool ? "heart.fill" : "heart") }.disabled(busy)
                if item.id == comment.id {
                    Menu {
                        if item.raw["user_id"].int == session.user?.id { Button("删除", role: .destructive) { deleting = true } }
                        else { Button("举报") { report = true } }
                    } label: { Image(systemName: "ellipsis") }
                }
            }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
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
            Form {
                Section {
                    TextField("此刻，想分享什么？", text: $text, axis: .vertical).lineLimit(8...20)
                    if let quoted { Label("引用 @\(quoted.author.username)：\(quoted.content)", systemImage: "quote.bubble").font(.caption).lineLimit(3) }
                }
                if editing == nil {
                    Section("照片和视频") {
                        PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) { Label("选择照片或一段视频", systemImage: "photo.on.rectangle.angled") }.disabled(busy || reading)
                        if reading { ProgressView("正在准备媒体…") }
                        ForEach(media) { item in
                            HStack {
                                if !item.isVideo, let image = UIImage(data: item.data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 8)) }
                                else { Image(systemName: "video").font(.title).frame(width: 64) }
                                Text(item.isVideo ? "视频" : "照片"); Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                Button(role: .destructive) { media.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle") }.disabled(busy)
                            }
                        }
                    }
                }
                Section("发布设置") {
                    Picker("谁可以看", selection: $visibility) { Text("公开").tag("public"); Text("仅好友").tag("friends") }
                    if editing == nil, let user = session.user, !user.raw["verified_roles"].array.isEmpty {
                        Picker("展示身份", selection: $role) {
                            Text("不展示").tag("")
                            ForEach(Array(user.raw["verified_roles"].array.enumerated()), id: \.offset) { i, value in Text(user.verifiedLabels.indices.contains(i) ? user.verifiedLabels[i] : value.string).tag(value.string) }
                        }
                    }
                }
                if !status.isEmpty { ProgressView(status) }
                ErrorBanner(text: error)
                if editing == nil { Text("未发布的文字会保存在本机草稿中；照片和视频需重新选择。").font(.caption).foregroundStyle(.secondary) }
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
