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
    @State private var recentEmoji: [NotoEmoji] = []
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
        emojiBrowser.show(.all)
        _emoji = State(initialValue: emojiBrowser)
        let notoBrowser = noto ?? NotoEmojiBrowser(accountID: accountID, defaults: defaults)
        notoBrowser.show(.all); _noto = State(initialValue: notoBrowser)
    }
    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            if searchOpen {
                NotoEmojiSearchField(text: query, focus: $searchFocused, prompt: searchPrompt)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            if importing {
                ProgressView("正在制作贴纸…").font(.caption).padding(.vertical, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .stickers: personalStickers
                    case .recent: recentExpressions
                    case .emoji: emojiSections(emoji, systemGlyphs: true)
                    case .noto: emojiSections(noto, systemGlyphs: false)
                    }
                }.padding(.vertical, 8)
            }.contentMargins(.horizontal, 16, for: .scrollContent).scrollDismissesKeyboard(.interactively)
                .scrollPosition($position)
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("chat.expressions.grid")
            if let importError { Text(importError).font(.caption).foregroundStyle(.red).padding(8) }
        }
        .padding(.top, 8)
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
        ViewThatFits(in: .horizontal) {
            sourceControls
            ScrollView(.horizontal) { sourceControls }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }.padding(.horizontal, 12).padding(.bottom, 4)
    }
    private var sourceControls: some View {
        HStack(spacing: 2) {
            ForEach(ChatExpressionTab.allCases) { source in
                Button { choose(source) } label: {
                    Image(systemName: source.symbol).font(.system(size: min(sourceIconSize, 24)))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(tab == source ? Color.primary : .secondary)
                        .background(tab == source ? Color.primary.opacity(0.06) : .clear,
                                    in: .rect(cornerRadius: 12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(importing).accessibilityLabel(source.title).accessibilityAddTraits(tab == source ? .isSelected : [])
                    .accessibilityIdentifier("chat.expressions.tab.\(source.id)")
            }
            Spacer(minLength: 0)
            Button(action: toggleSearch) {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                    .foregroundStyle(searchOpen ? Color.primary : .secondary)
                    .background(searchOpen ? Color.primary.opacity(0.06) : .clear,
                                in: .rect(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(importing).accessibilityLabel(searchPrompt)
            if tab == .noto {
                Button { searchFocused = false; showingCredits = true } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("动态贴纸设置与许可")
            }
            Button(action: onClose) {
                Image(systemName: "xmark").foregroundStyle(.secondary).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("关闭选择器")
        }
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
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "plus").font(.system(size: 36, weight: .medium)).foregroundStyle(.primary)
                        .frame(width: 60, height: 60)
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
        }.padding(.bottom, 8)
    }
    private var recentExpressions: some View {
        let saved = stickers.items.compactMap { item in item.lastUsed.map { RecentSticker(source: .saved(item), date: $0) } }
        let animated = history.compactMap { use in NotoEmojiCatalog.item(id: use.id).map { RecentSticker(source: .noto($0), date: use.date) } }
        let items = (saved + animated).sorted { $0.date > $1.date }.prefix(24)
            .filter { recentQuery.isEmpty || $0.name.localizedStandardContains(recentQuery) }
        let textEmoji = recentEmoji.filter { recentQuery.isEmpty || $0.matches(recentQuery) }
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty && textEmoji.isEmpty {
                if !recentQuery.isEmpty { emptySearch }
                else { Text("最近使用的表情和贴纸会出现在这里。").font(.subheadline).foregroundStyle(.secondary).padding(24) }
            }
            if !textEmoji.isEmpty {
                sectionHeading("表情符号")
                expressionGrid(textEmoji, systemGlyphs: true)
            }
            if !items.isEmpty {
                sectionHeading("贴纸")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in stickerTile(item.source) }
                }
            }
        }
    }
    @ViewBuilder private func emojiSections(_ browser: NotoEmojiBrowser, systemGlyphs: Bool) -> some View {
        if browser.items.isEmpty { emptySearch }
        else if browser.isSearching {
            expressionGrid(browser.items, systemGlyphs: systemGlyphs)
        } else {
            let groups = Dictionary(grouping: browser.items, by: \.category)
            LazyVStack(alignment: .leading, spacing: 16) {
                if !systemGlyphs && !browser.favoriteIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeading("收藏")
                        expressionGrid(browser.items.filter { browser.favoriteIDs.contains($0.id) }, systemGlyphs: false)
                    }
                }
                ForEach(NotoEmojiCatalog.categories.filter { groups[$0]?.isEmpty == false }, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeading(category)
                        expressionGrid(groups[category] ?? [], systemGlyphs: systemGlyphs)
                    }
                }
            }
        }
    }
    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).accessibilityAddTraits(.isHeader)
    }
    private func expressionGrid(_ items: [NotoEmoji], systemGlyphs: Bool) -> some View {
        NotoEmojiGrid(items: items, selectedID: systemGlyphs ? nil : selection?.notoEmoji?.id,
                      favorites: systemGlyphs ? [] : noto.favoriteIDs, canFavorite: !systemGlyphs && noto.canFavorite,
                      onSelect: { item in if systemGlyphs { insertEmoji(item) } else { stageNoto(item) } },
                      onFavorite: noto.toggleFavorite, systemGlyphs: systemGlyphs,
                      onUseAsSticker: systemGlyphs ? stageNoto : nil)
    }
    private func insertEmoji(_ item: NotoEmoji) {
        searchFocused = false
        if onInsertEmoji(item) {
            emoji.recordInsertion(item)
            recentEmoji = NotoEmojiRecents(accountID: accountID, defaults: defaults).items
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
    private var searchPrompt: String {
        switch tab {
        case .recent: return "搜索表情或贴纸"
        case .emoji: return "搜索表情名称或 emoji"
        case .stickers, .noto: return "搜索贴纸名称"
        }
    }
    private func toggleSearch() {
        if searchOpen { query.wrappedValue = "" }
        searchOpen.toggle(); searchFocused = searchOpen
        if searchOpen { expanded = true }
    }
    private func choose(_ source: ChatExpressionTab) {
        searchFocused = false; searchOpen = false; tab = source; query.wrappedValue = ""
    }
    private func reload() {
        stickers.reload()
        history = NotoStickerHistory(accountID: accountID, defaults: defaults).items
        recentEmoji = NotoEmojiRecents(accountID: accountID, defaults: defaults).items
    }
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
