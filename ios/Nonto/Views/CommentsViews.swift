import SwiftUI

struct PostDetailView: View {
    @Environment(\.appAccent) private var accent
    let postID: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var comments: CommentsStore
    @State private var post: Post?
    @State private var error: String?
    @State private var reportTarget: Comment?
    @State private var deleteTarget: Comment?
    @FocusState private var commentFocused: Bool

    init(session: AppSession, postID: Int, initial: Post? = nil) {
        self.postID = postID; _post = State(initialValue: initial)
        _comments = State(initialValue: CommentsStore(api: session.api, postID: postID, userID: session.user?.id ?? 0))
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let post {
                    PostCard(post: post, detailed: true, onComment: {
                        commentFocused = true
                        withAnimation { proxy.scrollTo("comments-header", anchor: .top) }
                    }).timelinePostRow()
                }
                if error != nil { ErrorBanner(text: error) { Task { await loadPost() } } }
                HStack {
                    Text("评论").font(.headline)
                    if let post { Text("\(post.comments)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
                    Spacer()
                    Text("最新").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8).id("comments-header").listRowSeparator(.hidden)
                ForEach(comments.threads) { thread in
                    commentRow(thread.root, nested: false).id("comment/\(thread.id)")
                    ForEach(thread.visibleReplies) { reply in
                        commentRow(reply, nested: true).id("comment/\(reply.id)")
                    }
                    threadFooter(thread).listRowSeparator(.hidden)
                }
                commentsFooter.listRowSeparator(.hidden)
            }
            .timelineList().navigationTitle("动态").navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommentComposer(store: comments, focused: $commentFocused)
            }
            .task {
                async let postLoad: Void = loadPost()
                async let commentLoad: Void = comments.load(reset: true)
                _ = await (postLoad, commentLoad)
                _ = try? await session.api.request("/posts/\(postID)/view", method: "POST")
            }
            .refreshable {
                async let postLoad: Void = loadPost()
                async let commentLoad: Void = comments.load(reset: true)
                _ = await (postLoad, commentLoad)
            }
            .onDisappear { comments.flushDraft() }
            .onChange(of: comments.scrollTarget) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo("comment/\(id)", anchor: .center) }
            }
            .onChange(of: comments.commentCount) { _, count in
                guard let count else { return }
                session.postChange = PostChange(postID: postID, patch: .object(["comment_count": .id(count)]))
            }
            .onReceive(session.$postRevision.dropFirst()) { _ in Task { await loadPost() } }
            .onReceive(session.$postChange.dropFirst().compactMap { $0 }) { change in
                guard change.postID == postID else { return }
                if let patch = change.patch { post = Post((post?.raw ?? .object([:])).merging(patch)) }
                else { dismiss() }
            }
            .scrollDismissesKeyboard(.interactively)
            .sheet(item: $reportTarget) { ReportView(kind: "comment", targetID: $0.id) }
            .confirmationDialog("删除这条评论？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { target in
                Button("删除", role: .destructive) { Task { await comments.delete(target) } }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("删除后无法恢复。")
            }
        }
    }
    private func commentRow(_ item: Comment, nested: Bool) -> some View {
        CommentItemRow(comment: item, nested: nested, busy: comments.busyIDs.contains(item.id),
            isPostAuthor: item.userID == post?.userID,
            canDelete: item.userID == session.user?.id || post?.userID == session.user?.id,
            canReport: item.userID != session.user?.id, error: comments.actionErrors[item.id],
            onReply: { comments.reply = item; comments.notice = nil; commentFocused = true },
            onLike: { Task { await comments.toggleLike(item) } },
            onDelete: { deleteTarget = item }, onReport: { reportTarget = item })
            .listRowSeparator(.hidden)
    }
    @ViewBuilder private func threadFooter(_ thread: CommentThread) -> some View {
        if thread.replies.count > 2 || thread.hasMore || comments.replyErrors[thread.id] != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    if !thread.expanded || thread.hasMore {
                        Button {
                            Task { await comments.expandReplies(thread.id) }
                        } label: {
                            HStack(spacing: 6) {
                                if comments.loadingReplies.contains(thread.id) { ProgressView().controlSize(.small) }
                                Text(!thread.expanded && thread.replies.count > 2 ? "展开回复（\(max(thread.root.raw["reply_count"].int, thread.replies.count) - 2)）" : "查看更多回复")
                            }.frame(minHeight: 44)
                        }.disabled(comments.loadingReplies.contains(thread.id))
                            .accessibilityIdentifier("comment-replies-\(thread.id)")
                    }
                    if thread.expanded && thread.replies.count > 2 {
                        Button("收起") { comments.collapseReplies(thread.id) }.frame(minHeight: 44)
                    }
                }.font(.caption).buttonStyle(.plain).foregroundStyle(accent.textColor)
                if let error = comments.replyErrors[thread.id] { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.leading, 52)
        }
    }
    @ViewBuilder private var commentsFooter: some View {
        if let error = comments.loadError {
            ErrorBanner(text: error) { Task { await comments.load(reset: !comments.loaded) } }
        } else if comments.loading || !comments.loaded {
            ProgressView("正在加载评论…").frame(maxWidth: .infinity).padding()
        } else if comments.threads.isEmpty {
            ContentUnavailableView("还没有评论", systemImage: "bubble.left.and.bubble.right", description: Text("分享你的想法，成为第一个评论的人。"))
        } else if comments.hasMore {
            Button("加载更多评论") { Task { await comments.load() } }
                .frame(maxWidth: .infinity, minHeight: 44)
                .task(id: comments.page) { if comments.page > 0 { await comments.load() } }
        } else {
            Text("已显示全部评论").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
    private func loadPost() async {
        let previousCount = comments.commentCount
        do {
            let result = try await session.api.request("/posts/\(postID)")
            var value = result["post"].or(result)
            if comments.commentCount != previousCount, let count = comments.commentCount { value["comment_count"] = .id(count) }
            post = Post(value); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommentComposer: View {
    @Environment(\.appAccent) private var accent
    @Bindable var store: CommentsStore
    var focused: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reply = store.reply {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("回复 \(reply.author.name)").font(.caption.bold())
                        Text(reply.content).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("取消回复", systemImage: "xmark.circle.fill") { store.reply = nil }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.padding(.horizontal, 8).accessibilityIdentifier("comment-reply-context")
            }
            if let error = store.sendError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer(minLength: 8)
                    Button("重试") { Task { await store.send() } }.disabled(!store.canSend)
                }.padding(.horizontal, 8)
            } else if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(store.reply == nil ? "说说你的想法…" : "写下你的回复…", text: $store.text, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.plain).padding(.vertical, 12).padding(.leading, 12)
                    .focused(focused).accessibilityLabel("评论内容").accessibilityIdentifier("comment-input")
                Button { Task { await store.send() } } label: {
                    Group {
                        if store.sending { ProgressView() }
                        else { Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(store.canSend ? accent.textColor : Color.secondary) }
                    }.frame(width: 44, height: 44)
                }.disabled(!store.canSend).accessibilityLabel(store.sending ? "正在发送评论" : "发送评论")
                    .accessibilityIdentifier("comment-send")
            }.floatingGlass()
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 820).frame(maxWidth: .infinity).background(Color.timelineBackground)
            .onChange(of: store.text) { _, text in if !text.isEmpty { store.notice = nil }; store.sendError = nil }
    }
}

private struct CommentItemRow: View {
    @Environment(\.appAccent) private var accent
    let comment: Comment
    let nested: Bool
    let busy: Bool
    let isPostAuthor: Bool
    let canDelete: Bool
    let canReport: Bool
    let error: String?
    let onReply: () -> Void
    let onLike: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RouteButton(.profile(comment.author.id)) {
                AvatarView(url: comment.author.avatar, name: comment.author.name, size: nested ? 28 : 36)
            }.frame(width: nested ? 28 : 36).accessibilityLabel("查看\(comment.author.name)的主页")
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RouteButton(.profile(comment.author.id)) { Text(comment.author.name).font(.subheadline.bold()).foregroundStyle(.primary) }
                    if isPostAuthor { Text("作者").font(.caption2).foregroundStyle(accent.textColor) }
                    Spacer(minLength: 2)
                    if let date = comment.date { Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                }
                if let target = comment.replyTo {
                    RouteButton(.profile(target.id)) { Text("回复 @\(target.username)").font(.caption).foregroundStyle(accent.textColor) }
                }
                Text(comment.content).font(.body).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button("回复", action: onReply).frame(minHeight: 44).accessibilityIdentifier("comment-reply-\(comment.id)")
                    Button(action: onLike) {
                        Label("\(comment.likes)", systemImage: comment.liked ? "heart.fill" : "heart")
                            .foregroundStyle(comment.liked ? Color.brandLike : Color.secondary).monospacedDigit().frame(minHeight: 44)
                    }.disabled(busy).accessibilityLabel(comment.liked ? "取消赞，\(comment.likes) 个赞" : "赞，\(comment.likes) 个赞")
                        .accessibilityIdentifier("comment-like-\(comment.id)")
                    Spacer(minLength: 0)
                    Menu {
                        Button("回复", systemImage: "arrowshape.turn.up.left", action: onReply)
                        if canDelete { Button("删除", systemImage: "trash", role: .destructive, action: onDelete) }
                        if canReport { Button("举报", systemImage: "flag", action: onReport) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .disabled(busy).accessibilityLabel("评论操作").accessibilityIdentifier("comment-menu-\(comment.id)")
                }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.leading, nested ? 36 : 0).padding(.vertical, nested ? 3 : 8)
            .buttonStyle(.plain).accessibilityIdentifier("comment-row-\(comment.id)")
    }
}
