import SwiftUI
import PhotosUI

struct ChatExpressionDrawer: View {
    @Environment(\.appAccent) private var accent
    let accountID: Int
    let api: APIClient
    let selection: StagedChatSticker?
    let disabled: Bool
    let onInsertEmoji: (NotoEmoji) -> Bool
    let onStageSticker: (StagedChatSticker) -> Void
    let onClose: () -> Void
    @Binding var expanded: Bool
    @State private var tab: ChatExpressionTab
    @State private var stickers: ChatStickerBrowser
    @State private var emoji: NotoEmojiBrowser
    @State private var noto: NotoEmojiBrowser
    @State private var history: [NotoStickerHistory.Use] = []
    @State private var recentQuery = ""
    @State private var searchOpen = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?
    @State private var creation: StickerCreationSession?
    @State private var showingCredits = false
    @State private var position = ScrollPosition(edge: .top)
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var sourceIconSize: CGFloat = 20
    private let epoch: UUID
    private let defaults: UserDefaults

    // The drawer owns one account's browsers for this presentation only.
    init(accountID: Int, api: APIClient, initialTab: ChatExpressionTab, selection: StagedChatSticker?,
         expanded: Binding<Bool>, disabled: Bool = false, defaults: UserDefaults = .standard, stickers: ChatStickerBrowser? = nil,
         emoji: NotoEmojiBrowser? = nil, noto: NotoEmojiBrowser? = nil,
         onInsertEmoji: @escaping (NotoEmoji) -> Bool, onStageSticker: @escaping (StagedChatSticker) -> Void,
         onClose: @escaping () -> Void) {
        self.accountID = accountID; self.api = api; self.selection = selection; self.disabled = disabled
        self.onInsertEmoji = onInsertEmoji; self.onStageSticker = onStageSticker; self.onClose = onClose
        _expanded = expanded; _tab = State(initialValue: initialTab); epoch = api.generation
        self.defaults = defaults
        _stickers = State(initialValue: stickers ?? ChatStickerBrowser(accountID: accountID, defaults: defaults))
        let emojiBrowser = emoji ?? NotoEmojiBrowser(accountID: accountID, defaults: defaults)
        if emojiBrowser.scope == .favorites { emojiBrowser.show(.all) }
        _emoji = State(initialValue: emojiBrowser)
        let notoBrowser = noto ?? NotoEmojiBrowser(accountID: accountID, defaults: defaults)
        notoBrowser.show(.all); _noto = State(initialValue: notoBrowser)
    }
    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                Capsule().fill(.secondary.opacity(0.55)).frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 20)
            }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起选择器" : "展开选择器")
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.height < -30 { expanded = true }
                    else if value.translation.height > 30 { expanded = false }
                })
            sourceBar
            if searchOpen {
                NotoEmojiSearchField(text: query, focus: $searchFocused, prompt: tab == .emoji ? "搜索表情名称或 emoji" : "搜索贴纸名称")
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            HStack {
                Text(sectionTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let resultCount { Text("\(resultCount)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
                Spacer()
                if importing { ProgressView().controlSize(.mini); Text("正在制作贴纸…").font(.caption2) }
            }.padding(.horizontal, 16).padding(.vertical, 5).accessibilityAddTraits(.isHeader)
            ScrollView {
                switch tab {
                case .stickers: personalStickers
                case .recent: recentStickers
                case .emoji:
                    if emoji.items.isEmpty { emptySearch }
                    else { NotoEmojiGrid(items: emoji.items, selectedID: nil, favorites: [], canFavorite: false,
                                  onSelect: { item in if onInsertEmoji(item) { emoji.recordInsertion(item) } }, onFavorite: { _ in },
                                  systemGlyphs: true, onUseAsSticker: stageNoto) }
                case .noto:
                    if noto.items.isEmpty { emptySearch }
                    else { NotoEmojiGrid(items: noto.items, selectedID: selection?.notoEmoji?.id,
                                  favorites: noto.favoriteIDs, canFavorite: noto.canFavorite,
                                  onSelect: stageNoto, onFavorite: noto.toggleFavorite) }
                }
            }.contentMargins(.horizontal, 12, for: .scrollContent).scrollDismissesKeyboard(.interactively)
                .scrollPosition($position)
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("chat.expressions.grid")
            if let importError { Text(importError).font(.caption).foregroundStyle(.red).padding(8) }
            if tab == .emoji || tab == .noto {
                HStack(spacing: 0) {
                    let browser = tab == .emoji ? emoji : noto
                    NotoEmojiScopeStrip(scopes: browser.scopes.filter { tab == .emoji ? $0 != .favorites : $0 != .recent },
                                        active: browser.isSearching ? nil : browser.scope,
                                        onSelect: { scope in searchFocused = false; browser.show(scope) })
                    if tab == .noto {
                        Button { searchFocused = false; showingCredits = true } label: {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("动态贴纸设置与许可")
                    }
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 26))
        .clipShape(.rect(cornerRadius: 26))
        .disabled(disabled)
        .onAppear(perform: reload)
        .onChange(of: selection?.id) { _, _ in reload() }
        .onChange(of: tab) { _, _ in position.scrollTo(edge: .top) }
        .onChange(of: query.wrappedValue) { _, _ in position.scrollTo(edge: .top) }
        .onChange(of: emoji.scope) { _, _ in if tab == .emoji { position.scrollTo(edge: .top) } }
        .onChange(of: noto.scope) { _, _ in if tab == .noto { position.scrollTo(edge: .top) } }
        .sheet(item: $creation, onDismiss: { stickers.reload() }) { session in
            ChatStickerCreationView(browser: session.browser, api: api, epoch: epoch) { stickers.reload() }
        }
        .sheet(isPresented: $showingCredits) { NavigationStack { NotoEmojiCreditsView() } }
        .task(id: photo) {
            guard let photo else { return }
            importing = true; importError = nil
            defer { importing = false; self.photo = nil }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw ChatStickerError.invalidImage }
                try Task.checkCancellation()
                let model = ChatStickerBrowser(accountID: accountID, defaults: defaults)
                await model.prepare(data, liftSubject: true)
                try Task.checkCancellation()
                guard epoch == api.generation, model.prepared != nil else {
                    importError = model.error; return
                }
                creation = StickerCreationSession(browser: model)
            } catch { if !Task.isCancelled { importError = error.localizedDescription } }
        }
        .accessibilityIdentifier("chat.expressions.drawer")
    }
    private var sourceBar: some View {
        HStack(spacing: 2) {
            ForEach(ChatExpressionTab.allCases) { source in
                Button { choose(source) } label: {
                    Image(systemName: source.symbol).font(.system(size: min(sourceIconSize, 24)))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(tab == source ? Color.primary : .secondary)
                        .background(tab == source ? Color(uiColor: .tertiarySystemFill) : .clear,
                                    in: .rect(cornerRadius: 12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(importing).accessibilityLabel(source.title).accessibilityAddTraits(tab == source ? .isSelected : [])
                    .accessibilityIdentifier("chat.expressions.tab.\(source.id)")
            }
            Spacer(minLength: 0)
            Button { searchOpen.toggle(); searchFocused = searchOpen; if searchOpen { expanded = true } } label: {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                    .foregroundStyle(searchOpen ? Color.primary : .secondary)
                    .background(searchOpen ? Color(uiColor: .tertiarySystemFill) : .clear,
                                in: .rect(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(importing).accessibilityLabel("搜索\(tab == .emoji ? "表情" : "贴纸")")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
                .buttonStyle(.plain).accessibilityLabel("关闭选择器")
        }.padding(.horizontal, 10).padding(.bottom, 6)
    }
    private var sectionTitle: String {
        switch tab { case .recent: return "最近使用的贴纸"; case .stickers: return "我的贴纸"; case .emoji: return "表情符号 · 轻点插入文字"; case .noto: return "Noto 动态贴纸" }
    }
    private var resultCount: Int? {
        switch tab { case .recent: return nil; case .stickers: return stickers.results.count; case .emoji: return emoji.items.count; case .noto: return noto.items.count }
    }
    private var emptySearch: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary)
            Text(query.wrappedValue.isEmpty ? "这里还没有内容" : "没有找到相关内容").font(.subheadline).foregroundStyle(.secondary)
            if !query.wrappedValue.isEmpty {
                Button("清除搜索") { query.wrappedValue = ""; searchFocused = false }
                    .font(.subheadline).foregroundStyle(accent.textColor).frame(minHeight: 44)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
    private var query: Binding<String> {
        Binding(get: {
            switch tab { case .recent: return recentQuery; case .stickers: return stickers.query; case .emoji: return emoji.query; case .noto: return noto.query }
        }, set: { value in
            switch tab { case .recent: recentQuery = value; case .stickers: stickers.query = value; case .emoji: emoji.query = value; case .noto: noto.query = value }
        })
    }
    private var personalStickers: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                        .frame(width: 60, height: 60)
                        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 16))
                        .frame(maxWidth: .infinity, minHeight: 84)
                }.buttonStyle(.plain).disabled(importing || stickers.items.count >= ChatStickerLibrary.limit)
                    .accessibilityLabel("从照片添加新贴纸").accessibilityIdentifier("chat.stickers.add")
                ForEach(stickers.results) { sticker in
                    stickerTile(.saved(sticker)).contextMenu {
                        Button("删除贴纸", systemImage: "trash", role: .destructive) { stickers.remove(sticker) }
                    }
                }
            }
            if stickers.items.isEmpty {
                Text("轻点 ＋ 从照片制作贴纸，也可以长按聊天图片添加。")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            } else if stickers.results.isEmpty {
                emptySearch
            }
            Text("贴纸收藏按账号保存在本机 · 长按可删除").font(.caption2).foregroundStyle(.secondary).padding(.vertical, 8)
        }.padding(.bottom, 8)
    }
    private var recentStickers: some View {
        let saved = stickers.items.compactMap { item in item.lastUsed.map { RecentSticker(source: .saved(item), date: $0) } }
        let animated = history.compactMap { use in NotoEmojiCatalog.item(id: use.id).map { RecentSticker(source: .noto($0), date: use.date) } }
        let items = (saved + animated).sorted { $0.date > $1.date }.prefix(24)
            .filter { recentQuery.isEmpty || $0.name.localizedStandardContains(recentQuery) }
        return Group {
            if items.isEmpty {
                if !recentQuery.isEmpty { emptySearch }
                else { Text("发送过的贴纸会出现在这里。").font(.subheadline).foregroundStyle(.secondary).padding(24) }
            }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in stickerTile(item.source) }
                }
            }
        }
    }
    private func stickerTile(_ source: StagedChatSticker.Source) -> some View {
        let item = StagedChatSticker(source: source)
        return Button { searchFocused = false; onStageSticker(item) } label: {
            ChatStagedStickerImage(sticker: item, animated: false).frame(height: 80).padding(4).frame(maxWidth: .infinity)
                .modifier(ExpressionPickerSelection(selected: selection?.sourceID == item.sourceID))
        }.buttonStyle(.plain).accessibilityLabel(item.name).accessibilityHint("添加到待发送贴纸")
            .accessibilityAddTraits(selection?.sourceID == item.sourceID ? .isSelected : [])
    }
    private func stageNoto(_ item: NotoEmoji) { searchFocused = false; onStageSticker(.init(source: .noto(item))) }
    private func choose(_ source: ChatExpressionTab) { searchFocused = false; searchOpen = false; tab = source }
    private func reload() { stickers.reload(); history = NotoStickerHistory(accountID: accountID, defaults: defaults).items }
}

private struct StickerCreationSession: Identifiable { let id = UUID(); let browser: ChatStickerBrowser }
private struct RecentSticker: Identifiable {
    let source: StagedChatSticker.Source
    let date: Date
    var id: String { StagedChatSticker(source: source).sourceID }
    var name: String { StagedChatSticker(source: source).name }
}

struct ChatStagedStickerImage: View {
    let sticker: StagedChatSticker
    var animated = true
    var body: some View {
        Group {
            if let item = sticker.notoEmoji {
                if animated { NotoEmojiAnimation(item: item) } else { NotoEmojiPoster(item: item) }
            } else if let url = sticker.imageURL { ChatStickerImage(url: url) }
        }
    }
}
