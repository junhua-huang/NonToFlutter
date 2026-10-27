import SwiftUI
import PhotosUI

struct PostComposer: View {
    @Environment(\.appAccent) private var accent
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
    @State private var showPhotoPicker = false
    @State private var attachments: ComposerAttachments
    @State private var preview: SelectedMedia?
    @State private var uploaded: [UUID: String] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var reading = false
    @State private var status = ""
    @State private var completedUploads = 0
    @State private var published = false
    @State private var draftLoaded = false
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
                VStack(alignment: .leading, spacing: 16) {
                    authorAndAudience
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
                }.padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .top)
            }.disabled(busy).scrollDismissesKeyboard(.interactively)
                .background(Color.timelineBackground)
                .safeAreaInset(edge: .bottom, spacing: 0) { composerFooter }
                .navigationTitle(editing == nil ? "" : "编辑动态").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: close) { Image(systemName: "xmark") }
                            .foregroundStyle(.primary).disabled(busy || reading).accessibilityLabel("关闭发布页")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await publish() } } label: {
                            if busy { ProgressView().accessibilityLabel("正在提交") }
                            else {
                                Text(editing == nil ? "发布" : "保存").fontWeight(.semibold)
                            }
                        }.disabled(busy || reading || !canPublish)
                            .buttonStyle(.glassProminent).tint(accent.color)
                            .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("post.composer.publish")
                    }
                }
                .interactiveDismissDisabled(busy || reading || !media.isEmpty || (editing != nil && hasChanges))
                .confirmationDialog(editing == nil ? "关闭发布？" : "放弃尚未保存的修改？", isPresented: $confirmClose, titleVisibility: .visible) {
                    if editing == nil { Button("保留草稿并关闭") {
                        draftSaveTask?.cancel()
                        Task { busy = true; defer { busy = false }; if await saveDraft() { dismiss() } }
                    } }
                    Button(editing == nil ? "放弃本次内容" : "放弃修改", role: .destructive) {
                        draftSaveTask?.cancel()
                        Task {
                            busy = true; defer { busy = false }
                            if editing == nil { published = true; await clearDraft() }
                            dismiss()
                        }
                    }
                    Button("继续编辑", role: .cancel) {}
                } message: {
                    if editing == nil && (!media.isEmpty || reading) {
                        Text("文字、可见范围和所选照片或视频会保存在本机，下次打开时恢复。")
                    }
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $picks,
                              maxSelectionCount: max(1, attachments.remainingCount), selectionBehavior: .ordered,
                              matching: media.isEmpty ? .any(of: [.images, .videos]) : .images)
                .sheet(item: $preview) { item in ComposerMediaPreview(item: item) }
                .sheet(item: $editor.referenceKind, onDismiss: {
                    editor.finishReference(allowed: accountEpoch == session.api.generation && accountID == session.user?.id)
                }) { kind in
                    ComposerReferencePicker(api: session.api, kind: kind) { value in
                        guard accountEpoch == session.api.generation, accountID == session.user?.id else { error = APIError.sessionChanged.localizedDescription; return }
                        editor.stageReference(value, kind: kind)
                    }
                }
                .task { await restoreDraft() }
                .onDisappear { draftSaveTask?.cancel(); Task { _ = await saveDraft() } }
                .onChange(of: [text, visibility, role]) { _, _ in scheduleDraftSave() }
                .onChange(of: media.map(\.id)) { _, _ in scheduleDraftSave() }
                .onChange(of: phase) { _, value in
                    if value != .active { draftSaveTask?.cancel(); Task { _ = await saveDraft() } }
                }
                .onChange(of: session.user?.id) { _, value in
                    if draftLoaded && value != accountID { showPhotoPicker = false; preview = nil; editor.endEditing(); dismiss() }
                }
                .task(id: picks) { await readSelection() }
        }.tint(accent.color)
    }
    private var authorAndAudience: some View {
        HStack(spacing: 10) {
            AvatarView(url: session.user?.avatar ?? "", name: session.user?.name ?? "", size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.user?.name ?? "我的动态").font(.subheadline.bold()).lineLimit(1)
                if editing == nil { rolePicker }
            }
            Spacer(minLength: 8)
            visibilityPicker
        }
    }
    private var attachmentGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.count == 1, let item = media.first {
                attachmentTile(item, large: true).frame(maxWidth: 420)
            } else {
                photoGrid
            }
        }.accessibilityIdentifier("post.composer.attachments")
    }
    @ViewBuilder private var photoGrid: some View {
        if #available(iOS 27, *) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(media) { item in
                    attachmentTile(item)
                }.reorderable()
            }.reorderContainer(for: SelectedMedia.self, isEnabled: !busy && !reading) { difference in
                guard !busy && !reading else { return }
                switch difference.destination.position {
                case .before(let target): attachments.reorder(difference.sources, before: target)
                case .end: attachments.reorder(difference.sources)
                @unknown default: break
                }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(media) { item in attachmentTile(item) }
            }
        }
    }
    private func attachmentTile(_ item: SelectedMedia, large: Bool = false) -> some View {
        ComposerAttachmentTile(item: item, index: media.firstIndex(where: { $0.id == item.id }) ?? 0,
            count: media.count, large: large, open: { editor.endEditing(); preview = item },
            remove: {
                guard !busy && !reading else { return }
                attachments.remove(item.id); uploaded.removeValue(forKey: item.id)
            }, move: { offset in
                guard !busy && !reading else { return }
                attachments.move(item.id, by: offset)
            }).disabled(reading)
    }
    @ViewBuilder private var rolePicker: some View {
        if let user = session.user, !user.raw["verified_roles"].array.isEmpty {
            Picker("展示身份", selection: $role) {
                Text("不展示").tag("")
                ForEach(user.raw["verified_roles"].array.map(\.string), id: \.self) { value in
                    let index = user.raw["verified_roles"].array.map(\.string).firstIndex(of: value) ?? 0
                    Text(user.verifiedLabels.indices.contains(index) ? user.verifiedLabels[index] : value).tag(value)
                }
            }.pickerStyle(.menu).font(.caption)
        }
    }
    private var composerFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reading || busy {
                VStack(alignment: .leading, spacing: 6) {
                    if busy && !media.isEmpty {
                        ProgressView(value: Double(completedUploads), total: Double(media.count))
                    } else { ProgressView().controlSize(.small) }
                    Text(status.isEmpty ? "正在准备媒体…" : status).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }
            if let error {
                ErrorBanner(text: error).padding(.horizontal, 16)
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        if editing == nil {
                            Button(action: openPhotos) { toolSymbol("photo") }
                                .disabled(!attachments.canAddPhotos)
                                .accessibilityLabel(media.isEmpty ? "添加照片或视频" : "继续添加照片")
                                .accessibilityHint(media.first?.isVideo == true ? "视频需单独发布" : "最多 9 张照片或一段视频")
                                .accessibilityIdentifier("post.composer.add-media")
                        }
                        Button { editor.beginReference(.mention) } label: { toolSymbol("at") }
                            .accessibilityLabel("艾特好友")
                        Button { editor.beginReference(.topic) } label: { toolSymbol("number") }
                            .accessibilityLabel("引用话题")
                    }.padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                    Spacer(minLength: 0)
                    if editor.isEditing {
                        Button { editor.endEditing() } label: { toolSymbol("keyboard.chevron.compact.down") }
                            .glassEffect(.regular.interactive(), in: Circle())
                            .accessibilityLabel("收起键盘")
                    }
                }.font(.title3).buttonStyle(.plain).foregroundStyle(accent.symbolColor).disabled(busy || reading)
                    .padding(.horizontal, 16)
            }
        }.padding(.top, 6).padding(.bottom, 6)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    private func toolSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol).frame(width: 44, height: 44)
    }
    private var visibilityPicker: some View {
        Menu {
            Picker("谁可以看", selection: $visibility) {
                Label("公开 · 所有人可见", systemImage: "globe.asia.australia").tag("public")
                Label("仅好友 · 好友可见", systemImage: "person.2").tag("friends")
            }
        } label: {
            HStack(spacing: 5) {
                Text(visibility == "public" ? "公开" : "仅好友")
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
        }.foregroundStyle(accent.color).accessibilityLabel("谁可以看")
            .accessibilityValue(visibility == "public" ? "公开" : "仅好友")
            .accessibilityIdentifier("post.composer.audience")
    }
    private func openPhotos() {
        guard editing == nil, attachments.canAddPhotos, !busy, !reading else { return }
        editor.endEditing(); showPhotoPicker = true
    }
    private func close() {
        editor.endEditing()
        if hasChanges { confirmClose = true } else { dismiss() }
    }
    private func restoreDraft() async {
        guard !draftLoaded else { return }
        accountID = session.user?.id ?? 0; accountEpoch = session.api.generation
        reading = true
        defer { reading = false; draftLoaded = true }
        let store = PostDraftStore(), community = communityID ?? 0, quote = quoted?.id ?? 0
        var saved = store.read(userID: accountID, communityID: community, quoteID: quote, defaultVisibility: session.defaultVisibility)
        if editing == nil && !store.isDiscarded(userID: accountID, communityID: community, quoteID: quote) {
            do {
                if let restored = try await PostDraftFiles.shared.read(userID: accountID, communityID: community, quoteID: quote) {
                    try checkAccount()
                    saved = restored.draft
                    if media.isEmpty { try attachments.append(restored.media, assetIDs: restored.assetIDs) }
                }
            } catch {
                if accountEpoch == session.api.generation, !(error is CancellationError) {
                    self.error = "部分草稿无法恢复，已保留可读取的文字。请检查附件后再发布。"
                }
            }
        }
        guard accountEpoch == session.api.generation, accountID == session.user?.id else { return }
        text = editing?.content ?? saved.text
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
        catch { self.error = error.localizedDescription }
        picks = []
    }
    private func scheduleDraftSave() {
        guard draftLoaded, editing == nil, !published else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            _ = await saveDraft()
        }
    }
    private func saveDraft() async -> Bool {
        guard editing == nil, !published else { return true }
        guard draftLoaded, accountID > 0, accountEpoch == session.api.generation, accountID == session.user?.id else { return false }
        let draft = PostDraft(text: text, visibility: visibility, role: role)
        let revision = DispatchTime.now().uptimeNanoseconds
        do {
            try await PostDraftFiles.shared.save(draft, media: media, assetIDs: attachments.assetIDs,
                userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0, revision: revision)
            try checkAccount()
            guard !published else { return true }
            PostDraftStore().save(draft, userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0)
            return true
        } catch {
            if !Task.isCancelled, accountEpoch == session.api.generation {
                self.error = "草稿未能保存，请检查本机存储空间后重试。"
            }
            return false
        }
    }
    private func clearDraft() async {
        draftSaveTask?.cancel(); draftSaveTask = nil
        PostDraftStore().remove(userID: accountID, communityID: communityID ?? 0, quoteID: quoted?.id ?? 0)
        try? await PostDraftFiles.shared.remove(userID: accountID, communityID: communityID ?? 0,
            quoteID: quoted?.id ?? 0, revision: DispatchTime.now().uptimeNanoseconds)
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
        busy = true; error = nil; completedUploads = 0; status = editing == nil ? "正在发布…" : "正在保存…"
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
                    completedUploads = index + 1
                }
                if !images.isEmpty { fields["image_urls"] = String(decoding: try JSON.array(images.map(JSON.text)).encoded(), as: UTF8.self) }
                if !identity.isEmpty { fields["display_role_type"] = identity }
                if let communityID { fields["community_id"] = String(communityID) }
                if let quoted { fields["quoted_post_id"] = String(quoted.id) }
                try checkAccount(); status = "正在发布…"
                _ = try await session.api.request("/posts", method: "POST", form: fields)
                try checkAccount(); published = true; await clearDraft()
            }
            published = true
            if editing == nil { session.postRevision += 1 }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
