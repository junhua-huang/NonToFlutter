import SwiftUI
import PhotosUI

struct ChatStickerPicker: View {
    // Account and credentials are one-time seeds for this presentation.
    @State private var browser: ChatStickerBrowser
    private let api: APIClient
    private let epoch: UUID
    private let onSend: (ChatSticker) -> Bool
    init(accountID: Int, api: APIClient, onSend: @escaping (ChatSticker) -> Bool) {
        _browser = State(initialValue: ChatStickerBrowser(accountID: accountID))
        self.api = api; epoch = api.generation; self.onSend = onSend
    }
    var body: some View {
        ChatStickerPickerContent(browser: browser) { data in
            guard api.generation == epoch, api.token != nil else { throw ChatStickerError.signedOut }
            let url = try await api.upload(data, filename: "sticker-\(UUID().uuidString).png", mime: "image/png", type: "chat")
            guard api.generation == epoch, api.token != nil else { throw ChatStickerError.signedOut }
            return url
        } onSend: { sticker in
            guard api.generation == epoch, api.token != nil else { return false }
            return onSend(sticker)
        }
    }
}

struct ChatStickerPickerContent: View {
    @Environment(\.appAccent) private var accent
    @Bindable var browser: ChatStickerBrowser
    let upload: (Data) async throws -> String
    let onSend: (ChatSticker) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var photo: PhotosPickerItem?
    @State private var readingPhoto = false
    @State private var operation: Task<Void, Never>?
    @State private var detent: PresentationDetent = .medium
    @State private var deletion: ChatSticker?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 86
    private var busy: Bool { browser.busy || readingPhoto }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("贴纸范围", selection: $browser.recentOnly) {
                    Text("我的贴纸").tag(false)
                    Text("最近使用").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8).disabled(busy)
                if browser.items.isEmpty {
                    ContentUnavailableView {
                        Label("添加你的第一张贴纸", systemImage: "square.on.circle")
                    } description: {
                        Text("从相册添加图片，或长按聊天中的图片添加到贴纸。支持透明背景图片。")
                    } actions: { addPhoto }
                } else {
                    ScrollView {
                        if browser.results.isEmpty {
                            ContentUnavailableView(browser.query.isEmpty ? "还没有最近使用的贴纸" : "没有找到贴纸",
                                                   systemImage: browser.query.isEmpty ? "clock" : "magnifyingglass")
                                .padding(.vertical, 24)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 12)], spacing: 12) {
                                ForEach(browser.results) { sticker in tile(sticker) }
                            }.padding(.vertical, 8)
                        }
                        Text("已保存 \(browser.items.count)/120 · 长按可删除\n贴纸收藏按账号保存在本机")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical, 12)
                    }.contentMargins(.horizontal, 16, for: .scrollContent).scrollDismissesKeyboard(.interactively)
                }
                if busy { ProgressView(readingPhoto ? "正在读取图片…" : "正在处理贴纸…").font(.caption).padding(8) }
                if let error = browser.error { ErrorBanner(text: error).padding(.horizontal, 16).padding(.bottom, 8) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.timelineBackground)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if browser.prepared != nil || browser.selection != nil { selectionBar }
            }
            .searchable(text: $browser.query, prompt: "搜索贴纸名称")
            .navigationTitle("贴纸").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: close) }
                ToolbarItem(placement: .topBarTrailing) { addPhoto }
            }
            .onChange(of: browser.query) { _, _ in browser.clearSelection(); detent = .large }
            .onChange(of: browser.recentOnly) { _, _ in browser.clearSelection() }
            .onChange(of: dynamicType, initial: true) { _, size in if size.isAccessibilitySize { detent = .large } }
            .task(id: photo) {
                guard let photo else { return }
                readingPhoto = true; detent = .large
                defer { readingPhoto = false; self.photo = nil }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw ChatStickerError.invalidImage }
                    try Task.checkCancellation()
                    await browser.prepare(data)
                } catch {
                    if !Task.isCancelled { browser.error = error.localizedDescription }
                }
            }
            .alert("删除这张贴纸？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) { if let deletion { browser.remove(deletion) }; deletion = nil }
                Button("取消", role: .cancel) { deletion = nil }
            } message: { Text("已发送的消息不受影响。") }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible).presentationContentInteraction(.resizes)
        .interactiveDismissDisabled(busy)
        .onDisappear { operation?.cancel(); browser.cancel() }
    }
    private var addPhoto: some View {
        PhotosPicker(selection: $photo, matching: .images) { Label("添加贴纸", systemImage: "plus") }
            .disabled(busy || browser.items.count >= ChatStickerLibrary.limit)
            .accessibilityIdentifier("chat.stickers.add")
    }
    private func tile(_ sticker: ChatSticker) -> some View {
        Button { nameFocused = false; browser.select(sticker) } label: {
            VStack(spacing: 4) {
                ChatStickerImage(url: sticker.url).frame(height: cellSize - 12)
                Text(sticker.name).font(.caption).foregroundStyle(.primary).lineLimit(1)
            }.padding(6).frame(maxWidth: .infinity)
                .modifier(ExpressionPickerSelection(selected: browser.selection?.id == sticker.id, cornerRadius: 14))
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityLabel(sticker.name).accessibilityHint("轻点预览并发送，长按可删除")
            .accessibilityAddTraits(browser.selection?.id == sticker.id ? .isSelected : [])
            .accessibilityIdentifier("chat.sticker.\(sticker.id)")
            .contextMenu {
                Button("删除贴纸", systemImage: "trash", role: .destructive) { deletion = sticker; confirmDelete = true }
            }
    }
    private var selectionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let prepared = browser.prepared { StickerArtwork(image: prepared.image) }
                    else if let selection = browser.selection { ChatStickerImage(url: selection.url) }
                }.frame(width: 72, height: 72).accessibilityLabel("贴纸预览")
                if browser.prepared != nil {
                    TextField("贴纸名称（可选）", text: $browser.name).focused($nameFocused)
                        .submitLabel(.done).onSubmit { nameFocused = false }
                        .onChange(of: browser.name) { _, value in if value.count > 40 { browser.name = String(value.prefix(40)) } }
                        .disabled(busy).accessibilityIdentifier("chat.stickers.name")
                } else { Text(browser.selection?.name ?? "贴纸").font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
                Button { nameFocused = false; browser.clearSelection() } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(busy).accessibilityLabel("取消选择贴纸")
            }
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(spacing: 8) { saveButton; sendButton }
                } else { HStack(spacing: 12) { saveButton; sendButton } }
            }.controlSize(.large)
        }.padding(16).accessibilityIdentifier("chat.stickers.preview")
    }
    @ViewBuilder private var saveButton: some View {
        if browser.prepared != nil {
            Button { commit(send: false) } label: { Text("仅保存").frame(maxWidth: .infinity) }
                .buttonStyle(.glass).disabled(!browser.canCommit || readingPhoto)
        }
    }
    private var sendButton: some View {
        Button { commit(send: true) } label: {
            Text(browser.prepared == nil ? "发送贴纸" : "添加并发送").frame(maxWidth: .infinity)
                .foregroundStyle(browser.canCommit && !readingPhoto ? accent.foregroundColor : Color.secondary)
        }.buttonStyle(.glassProminent).disabled(!browser.canCommit || readingPhoto)
            .accessibilityIdentifier("chat.stickers.send")
    }
    private func commit(send: Bool) {
        guard !busy, browser.canCommit, operation == nil else { return }
        nameFocused = false
        operation = Task {
            defer { operation = nil }
            if await browser.commit(send: send, upload: upload, enqueue: onSend), send { dismiss() }
        }
    }
    private func close() { operation?.cancel(); browser.cancel(); dismiss() }
}
