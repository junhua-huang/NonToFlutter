import SwiftUI
import PhotosUI

struct FeedView: View {
    @ObservedObject var session: AppSession
    @Environment(\.openComposer) private var compose
    @State private var filter = 1
    private var path: String { filter == 1 ? "/posts/" : "/posts/related-to-me" }
    var body: some View {
        PostList(session: session, path: path).id(filter)
        .safeAreaInset(edge: .top, spacing: 0) {
            TimelineTabs(title: "动态范围", tabs: [(1, "最新"), (2, "与你相关")], selection: $filter)
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
    init(session: AppSession, path: String, query: [String: String] = [:], header: AnyView? = nil, cacheEnabled: Bool = true) {
        self.header = header
        _resource = StateObject(wrappedValue: Self.resource(session: session, path: path, query: query, cacheEnabled: cacheEnabled))
    }
    private static func resource(session: AppSession, path: String, query: [String: String], cacheEnabled: Bool) -> PagedResource<Post> {
        let resource = PagedResource<Post>(api: session.api, path: path, keys: ["posts", "items"], query: query, userID: session.user?.id ?? 0, cacheEnabled: cacheEnabled)
        resource.observePostChanges(in: session)
        return resource
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
    }
}

struct PostCard: View {
    let post: Post
    var detailed = false
    var onComment: (() -> Void)? = nil
    @EnvironmentObject private var session: AppSession
    @Environment(\.postComposer) private var composer
    @State private var current: Post
    @State private var busy = false
    @State private var error: String?
    @State private var localComposer: PostComposerDestination?
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
            .onAppear {
                let updated = Post(post.raw.merging(session.pendingLikePatch(for: post.id)))
                if current != updated { current = updated }
            }
            .onChange(of: post.raw) { _, raw in
                let updated = Post(raw.merging(session.pendingLikePatch(for: post.id)))
                if current != updated { current = updated }
            }
            .onReceive(session.$postChange.dropFirst().compactMap { $0 }) { change in
                if change.postID == current.id, let patch = change.patch {
                    let updated = Post(current.raw.merging(patch))
                    if current != updated { current = updated }
                }
            }
            .sheet(item: $localComposer) { destination in destination.content }
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
            Button("引用动态", systemImage: "quote.bubble") { presentComposer(.quote(current)) }
            Button("分享给好友", systemImage: "paperplane") { sharing = true }
            if let url = URL(string: "https://www.nonto.online/posts/\(current.id)") {
                ShareLink(item: url) { Label("系统分享", systemImage: "square.and.arrow.up") }
            }
            if current.userID == session.user?.id {
                Button("编辑", systemImage: "pencil") { presentComposer(.edit(current)) }
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
            Button { presentComposer(.quote(current)) } label: { TimelineActionSymbol(symbol: "arrow.2.squarepath") }
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
        busy = true; error = nil; defer { busy = false }
        do { try await session.togglePostLike(current) }
        catch { self.error = error.localizedDescription }
    }
    private func presentComposer(_ destination: PostComposerDestination) {
        if let composer { composer.destination = destination }
        else { localComposer = destination }
    }
}

