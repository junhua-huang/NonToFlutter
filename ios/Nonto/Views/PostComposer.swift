import SwiftUI
import PhotosUI

struct PostComposer: View {
    var editing: Post? = nil
    var quoted: Post? = nil
    var communityID: Int? = nil
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var editor: ComposerEditor
    private var text: String {
        get { editor.text }
        nonmutating set { editor.replaceText(newValue) }
    }
    @State private var visibility = "public"
    @State private var role = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var attachments: ComposerAttachments
    @State private var preview: SelectedMedia?
    @State private var uploaded: [UUID: String] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var reading = false
    @State private var status = ""
    @State private var published = false
    @State private var draftLoaded = false
    @State private var restoredDraft = false
    @State private var accountID = 0
    @State private var accountEpoch: UUID?
    @State private var confirmClose = false
    @State private var draftSaveTask: Task<Void, Never>?
    private var media: [SelectedMedia] { attachments.items }
    private var hasChanges: Bool {
        if let editing { return text != editing.content || visibility != editing.visibilityForEdit }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.isEmpty || quoted != nil || reading
    }
    private var canPublish: Bool {
        if let editing {
            return hasChanges && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !editing.images.isEmpty || !editing.video.isEmpty || editing.quoted != nil)
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.isEmpty || quoted != nil
    }
    init(editing: Post? = nil, quoted: Post? = nil, communityID: Int? = nil,
         editor: ComposerEditor? = nil, initialMedia: [SelectedMedia] = []) {
        self.editing = editing; self.quoted = quoted; self.communityID = communityID
        _editor = State(initialValue: editor ?? ComposerEditor())
        var attachments = ComposerAttachments(); try? attachments.append(initialMedia)
        _attachments = State(initialValue: attachments)
    }
    var body: some View {
        @Bindable var editor = editor
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    authorAndAudience
                    if restoredDraft {
                        Label("已恢复上次文字草稿", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    }
                    ComposerTextEditor(editor: editor)
                    if let quoted {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("引用 @\(quoted.author.username)", systemImage: "quote.bubble").font(.caption.bold())
                            Text(quoted.content).font(.subheadline).lineLimit(4)
                        }.foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let editing {
                        if !editing.images.isEmpty || !editing.video.isEmpty {
                            MediaView(images: editing.images, video: editing.video, postLayout: true)
                            Text("原有照片和视频将保留").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !media.isEmpty { attachmentGrid }
                    if editing == nil { rolePicker }
                    if editing == nil && media.isEmpty && !reading {
                        Text("分享照片、作品，或记录此刻的想法。").font(.subheadline).foregroundStyle(.tertiary)
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .top)
            }.disabled(busy).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { composerFooter }
                .navigationTitle(editing == nil ? "发布动态" : "编辑动态").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editor.endEditing(); if hasChanges { confirmClose = true } else { dismiss() } }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await publish() } } label: {
                            if busy { ProgressView().accessibilityLabel("正在提交") }
                            else { Text(editing == nil ? "发布" : "保存").fontWeight(.semibold) }
                        }.disabled(busy || reading || !canPublish)
                            .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("post.composer.publish")
                    }
                }
                .interactiveDismissDisabled(busy || reading || !media.isEmpty || (editing != nil && hasChanges))
                .confirmationDialog(editing == nil ? "关闭发布？" : "放弃尚未保存的修改？", isPresented: $confirmClose, titleVisibility: .visible) {
                    if editing == nil { Button("保留文字草稿并关闭") { saveDraft(); dismiss() } }
                    Button(editing == nil ? "放弃本次内容" : "放弃修改", role: .destructive) {
                        draftSaveTask?.cancel()
                        if editing == nil { published = true; clearDraft() }
                        dismiss()
                    }
                    Button("继续编辑", role: .cancel) {}
                } message: {
                    if editing == nil && (!media.isEmpty || reading) {
                        Text("文字和可见范围可保留为草稿，照片和视频关闭后需要重新选择。")
                    }
                }
                .sheet(item: $preview) { item in ComposerMediaPreview(item: item) }
                .sheet(item: $editor.referenceKind, onDismiss: {
                    editor.finishReference(allowed: accountEpoch == session.api.generation && accountID == session.user?.id)
                }) { kind in
                    ComposerReferencePicker(api: session.api, kind: kind) { value in
                        guard accountEpoch == session.api.generation, accountID == session.user?.id else { error = APIError.sessionChanged.localizedDescription; return }
                        editor.stageReference(value, kind: kind)
                    }
                }
                .onAppear { restoreDraft() }
                .onDisappear { saveDraft() }
                .onChange(of: [text, visibility, role]) { _, _ in
                    draftSaveTask?.cancel()
                    draftSaveTask = Task {
                        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                        saveDraft()
                    }
                }
                .onChange(of: phase) { _, value in if value != .active { saveDraft() } }
                .onChange(of: session.user?.id) { _, value in
                    if draftLoaded && value != accountID { preview = nil; editor.endEditing(); dismiss() }
                }
                .task(id: picks) { await readSelection() }
        }
    }
    private var authorAndAudience: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: session.user?.avatar ?? "", name: session.user?.name ?? "", size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.user?.name ?? "我的动态").font(.subheadline.bold())
                visibilityPicker
            }
            Spacer(minLength: 0)
        }
    }
    private var attachmentGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(media.first?.isVideo == true ? "视频预览" : "已选照片 \(media.count)/9").font(.subheadline.bold())
                Spacer()
                if media.count > 1 { Text("长按调整顺序").font(.caption).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 220), spacing: 12)], spacing: 12) {
                ForEach(media) { item in
                    ComposerAttachmentTile(item: item, index: media.firstIndex(where: { $0.id == item.id }) ?? 0,
                        count: media.count, open: { editor.endEditing(); preview = item },
                        remove: { attachments.remove(item.id); uploaded.removeValue(forKey: item.id) },
                        move: { attachments.move(item.id, by: $0) })
                }
            }
        }
    }
    @ViewBuilder private var rolePicker: some View {
        if let user = session.user, !user.raw["verified_roles"].array.isEmpty {
            Picker("展示身份", selection: $role) {
                Text("不展示").tag("")
                ForEach(user.raw["verified_roles"].array.map(\.string), id: \.self) { value in
                    let index = user.raw["verified_roles"].array.map(\.string).firstIndex(of: value) ?? 0
                    Text(user.verifiedLabels.indices.contains(index) ? user.verifiedLabels[index] : value).tag(value)
                }
            }.pickerStyle(.menu).font(.subheadline)
        }
    }
    private var composerFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reading || busy {
                ProgressView(status.isEmpty ? "正在准备媒体…" : status).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityLiveRegion(.polite)
            }
            if let error {
                ErrorBanner(text: error)
                Text("内容仍保留在此页，可调整后重新操作。").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if editing == nil { mediaPicker }
                Button { editor.beginReference(.mention) } label: {
                    Image(systemName: "at").frame(width: 44, height: 44)
                }.accessibilityLabel("艾特好友")
                Button { editor.beginReference(.topic) } label: {
                    Image(systemName: "number").frame(width: 44, height: 44)
                }.accessibilityLabel("引用话题")
                Spacer(minLength: 0)
                if editor.isEditing {
                    Button { editor.endEditing() } label: {
                        Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
                    }.accessibilityLabel("收起键盘")
                } else if editing == nil {
                    Text("文字草稿自动保留").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }.font(.title3).buttonStyle(.plain).foregroundStyle(Color.brand).disabled(busy || reading)
        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
            .frame(maxWidth: 720).frame(maxWidth: .infinity).background(.bar)
    }
    private var mediaPicker: some View {
        PhotosPicker(selection: $picks, maxSelectionCount: max(1, attachments.remainingCount),
                     selectionBehavior: .ordered, matching: media.isEmpty ? .any(of: [.images, .videos]) : .images) {
            Image(systemName: "photo.on.rectangle.angled").frame(width: 44, height: 44)
        }.disabled(!attachments.canAddPhotos || busy || reading)
            .accessibilityLabel(media.isEmpty ? "添加照片或视频" : "继续添加照片")
            .accessibilityHint(media.first?.isVideo == true ? "视频需单独发布" : "最多 9 张照片或一段视频")
    }
    private var visibilityPicker: some View {
        Picker("谁可以看", selection: $visibility) {
            Label("公开", systemImage: "globe.asia.australia").tag("public")
            Label("仅好友", systemImage: "person.2").tag("friends")
        }.pickerStyle(.menu).font(.caption).fixedSize(horizontal: false, vertical: true)
    }
    private func restoreDraft() {
        guard !draftLoaded else { return }; draftLoaded = true
        accountID = session.user?.id ?? 0; accountEpoch = session.api.generation
        let saved = PostDraftStore().read(userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0, defaultVisibility: session.defaultVisibility)
        text = editing?.content ?? saved.text; restoredDraft = editing == nil && !saved.text.isEmpty
        visibility = editing?.visibilityForEdit ?? saved.visibility
        let roles = session.user?.raw["verified_roles"].array.map(\.string) ?? []
        role = roles.contains(saved.role) ? saved.role : ""
    }
    private func readSelection() async {
        let selection = picks
        guard !selection.isEmpty else { return }
        reading = true; error = nil; status = "正在准备媒体…"
        defer { reading = false; if !busy { status = "" } }
        do {
            var result: [SelectedMedia] = []
            for (index, pick) in selection.enumerated() {
                try checkAccount(); status = "正在准备媒体 \(index + 1)/\(selection.count)…"
                result.append(try await MediaLoader.load(pick))
            }
            try checkAccount()
            try attachments.append(result, assetIDs: selection.map(\.itemIdentifier))
        } catch is CancellationError { return }
        catch { error = error.localizedDescription }
        picks = []
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
        guard !busy && !reading else { return }
        editor.endEditing()
        guard canPublish else { return }
        let content = text, audience = visibility, selected = media, identity = role
        busy = true; error = nil; status = editing == nil ? "正在发布…" : "正在保存…"
        defer { busy = false; status = "" }
        do {
            try checkAccount()
            if let editing {
                let patch: JSON = .object(["content": .text(content), "visibility": .text(audience)])
                let result = try await session.api.request("/posts/\(editing.id)", method: "PUT", body: patch)
                try checkAccount()
                session.postChange = PostChange(postID: editing.id, patch: patch.merging(result["post"].or(result)))
            } else {
                var fields: [String: String] = ["content": content, "visibility": audience]
                var images: [String] = []
                for (index, item) in selected.enumerated() {
                    try checkAccount()
                    status = "正在上传\(item.isVideo ? "视频" : "照片") \(index + 1)/\(selected.count)…"
                    let url: String
                    if let existing = uploaded[item.id] { url = existing }
                    else {
                        url = try await session.api.upload(item.data, filename: item.name, mime: item.mime)
                        try checkAccount(); uploaded[item.id] = url
                    }
                    if item.isVideo { fields["video_url"] = url } else { images.append(url) }
                }
                if !images.isEmpty { fields["image_urls"] = String(decoding: try JSON.array(images.map(JSON.text)).encoded(), as: UTF8.self) }
                if !identity.isEmpty { fields["display_role_type"] = identity }
                if let communityID { fields["community_id"] = String(communityID) }
                if let quoted { fields["quoted_post_id"] = String(quoted.id) }
                try checkAccount(); status = "正在发布…"
                _ = try await session.api.request("/posts", method: "POST", form: fields)
                try checkAccount(); clearDraft()
            }
            published = true
            if editing == nil { session.postRevision += 1 }
            dismiss()
        } catch { error = error.localizedDescription }
    }
}
