import SwiftUI

struct NotoEmojiPickerContent: View {
    @Bindable var browser: NotoEmojiBrowser
    let onSend: (NotoEmoji) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var detent: PresentationDetent = .medium
    @State private var showingCredits = false
    @State private var position = ScrollPosition(edge: .top)
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NotoEmojiSearchField(text: $browser.query, focus: $searchFocused)
                    .padding(.horizontal, 16).padding(.top, 8)
                NotoEmojiScopeStrip(scopes: browser.scopes, active: browser.isSearching ? nil : browser.scope,
                                    onSelect: showScope)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(browser.title).font(.subheadline.weight(.semibold))
                    Text("\(browser.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if !dynamicType.isAccessibilitySize {
                        Text("轻点预览，长按收藏").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8)
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                ScrollView {
                    if browser.items.isEmpty { emptyState.padding(.vertical, 24) }
                    else {
                        NotoEmojiGrid(items: browser.items, selectedID: browser.selection?.id,
                                      favorites: browser.favoriteIDs, canFavorite: browser.canFavorite,
                                      onSelect: select, onFavorite: browser.toggleFavorite)
                            .padding(.bottom, 16)
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollPosition($position).scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("noto.results")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if let selection = browser.selection {
                    NotoEmojiSelectionBar(item: selection, favorite: browser.favoriteIDs.contains(selection.id),
                                          canFavorite: browser.canFavorite, isActive: !showingCredits,
                                          hasSent: browser.hasSent, error: browser.error,
                                          onFavorite: { browser.toggleFavorite(selection) }, onSend: send)
                }
            }
            .navigationTitle("动态表情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { searchFocused = false; showingCredits = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("表情设置与许可")
                }
            }
            .onChange(of: browser.filter) { _, _ in position.scrollTo(edge: .top) }
            .onChange(of: searchFocused) { _, focused in if focused { detent = .large } }
            .onChange(of: dynamicType, initial: true) { _, size in if size.isAccessibilitySize { detent = .large } }
            .sensoryFeedback(.selection, trigger: browser.selection?.id) { old, new in new != nil && old != new }
            .sheet(isPresented: $showingCredits) { NavigationStack { NotoEmojiCreditsView() } }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
    }
    @ViewBuilder private var emptyState: some View {
        if browser.isSearching {
            ContentUnavailableView {
                Label("没有找到相关表情", systemImage: "magnifyingglass")
            } description: {
                Text("试试「开心」「爱心」、英文名称或 emoji。")
            } actions: {
                Button("清除搜索") { browser.query = ""; searchFocused = false }
            }
        } else if browser.scope == .favorites {
            ContentUnavailableView {
                Label("还没有收藏的表情", systemImage: "star")
            } description: {
                Text("长按表情，或在预览中轻点星标，就能在这里快速找到它。")
            } actions: {
                Button("浏览全部表情") { showScope(.all) }
            }
        } else {
            ContentUnavailableView {
                Label("还没有最近使用的表情", systemImage: "clock")
            } description: {
                Text("发送过的表情会出现在这里。")
            } actions: {
                Button("浏览全部表情") { showScope(.all) }
            }
        }
    }
    private func showScope(_ scope: NotoEmojiScope) { searchFocused = false; browser.show(scope) }
    private func select(_ item: NotoEmoji) { searchFocused = false; browser.select(item) }
    private func send() { searchFocused = false; if browser.send(using: onSend) { dismiss() } }
}

struct NotoEmojiSearchField: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    var prompt = "搜索名称、关键词或 emoji"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused(focus).onSubmit { focus.wrappedValue = false }
                .accessibilityLabel(prompt).accessibilityIdentifier("noto.search")
                .frame(minHeight: 44)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("清除搜索").accessibilityIdentifier("noto.search.clear")
            }
        }.padding(.leading, 12).padding(.trailing, text.isEmpty ? 12 : 0)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 14))
    }
}

struct NotoEmojiScopeStrip: View {
    @Environment(\.appAccent) private var accent
    let scopes: [NotoEmojiScope]
    let active: NotoEmojiScope?
    let onSelect: (NotoEmojiScope) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(scopes) { scope in
                        Button { onSelect(scope) } label: {
                            Image(systemName: scope.symbol).font(.system(size: min(iconSize, 28)))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(active == scope ? accent.symbolColor : .secondary)
                                .background(active == scope ? accent.color.opacity(0.12) : .clear, in: Circle())
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(scope.id)
                            .accessibilityLabel(scope.title).accessibilityAddTraits(active == scope ? .isSelected : [])
                            .accessibilityIdentifier("noto.scope.\(scope.id)")
                    }
                }.padding(.horizontal, 8).padding(.vertical, 4)
            }.scrollIndicators(.hidden)
                .onChange(of: active, initial: true) { _, value in
                    guard let value else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { proxy.scrollTo(value.id, anchor: .center) }
                }
        }
    }
}

/// Artwork stays transparent; a border and check distinguish selection.
struct ExpressionPickerSelection: ViewModifier {
    let selected: Bool
    var cornerRadius: CGFloat = 16
    @Environment(\.appAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(selected ? accent.symbolColor : .clear, lineWidth: contrast == .increased ? 2.5 : 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent.foregroundColor).frame(width: 16, height: 16)
                        .background(accent.color, in: Circle()).padding(4).accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
    }
}

struct NotoEmojiGrid: View {
    let items: [NotoEmoji]
    let selectedID: String?
    let favorites: Set<String>
    let canFavorite: Bool
    let onSelect: (NotoEmoji) -> Void
    let onFavorite: (NotoEmoji) -> Void
    var systemGlyphs = false
    var onUseAsSticker: ((NotoEmoji) -> Void)? = nil
    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 56
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 6)], spacing: 6) {
            ForEach(items) { item in
                NotoEmojiTile(item: item, selected: selectedID == item.id, favorite: favorites.contains(item.id),
                              canFavorite: canFavorite, cellSize: cellSize,
                              onSelect: { onSelect(item) }, onFavorite: { onFavorite(item) },
                              systemGlyphs: systemGlyphs, onUseAsSticker: onUseAsSticker.map { action in { action(item) } })
            }
        }.scrollTargetLayout()
    }
}

private struct NotoEmojiTile: View {
    let item: NotoEmoji
    let selected: Bool
    let favorite: Bool
    let canFavorite: Bool
    let cellSize: CGFloat
    let onSelect: () -> Void
    let onFavorite: () -> Void
    var systemGlyphs = false
    var onUseAsSticker: (() -> Void)? = nil
    var body: some View {
        Button(action: onSelect) {
            Group {
                if systemGlyphs { Text(item.emoji).font(.system(size: min(cellSize * 0.72, 60))) }
                else { NotoEmojiPoster(item: item) }
            }.frame(width: min(cellSize * 0.78, 64), height: min(cellSize * 0.78, 64))
                .frame(maxWidth: .infinity, minHeight: cellSize)
                .modifier(ExpressionPickerSelection(selected: selected, cornerRadius: 14))
                .overlay(alignment: .bottomTrailing) {
                    if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange).padding(5) }
                }
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityLabel(item.name).accessibilityValue(favorite ? "已收藏" : "")
        .accessibilityHint(systemGlyphs ? "插入文字，长按可用作贴纸" : "添加为待发送的贴纸")
        .accessibilityIdentifier("noto.emoji.\(item.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions {
            if canFavorite { Button(favorite ? "取消收藏" : "收藏", action: onFavorite) }
            if let onUseAsSticker { Button("用作贴纸", action: onUseAsSticker) }
        }
        .contextMenu {
            if let onUseAsSticker {
                Button("用作贴纸", systemImage: "square.on.circle", action: onUseAsSticker)
            }
            if canFavorite {
                Button(action: onFavorite) { Label(favorite ? "取消收藏" : "收藏", systemImage: favorite ? "star.slash" : "star") }
            }
        }
    }
}

private struct NotoEmojiSelectionBar: View {
    let item: NotoEmoji
    let favorite: Bool
    let canFavorite: Bool
    let isActive: Bool
    let hasSent: Bool
    let error: String?
    let onFavorite: () -> Void
    let onSend: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack(spacing: 8) {
            if dynamicType.isAccessibilitySize {
                HStack(spacing: 12) { image; name; favoriteButton }
                sendButton
            } else {
                HStack(spacing: 8) { image; name; favoriteButton; sendButton }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(12).background(.bar).accessibilityIdentifier("noto.selection")
    }
    private var image: some View { NotoEmojiAnimation(item: item, isActive: isActive).id(item.id).frame(width: 56, height: 56) }
    private var name: some View {
        Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(dynamicType.isAccessibilitySize ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var favoriteButton: some View {
        Button(action: onFavorite) {
            Image(systemName: favorite ? "star.fill" : "star").foregroundStyle(favorite ? Color.orange : .secondary)
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).disabled(!canFavorite)
            .accessibilityLabel(favorite ? "取消收藏此表情" : "收藏此表情").accessibilityIdentifier("noto.favorite.toggle")
    }
    private var sendButton: some View {
        Button(action: onSend) {
            Text("发送").font(.headline)
                .frame(minWidth: 36, maxWidth: dynamicType.isAccessibilitySize ? .infinity : nil, minHeight: 32)
        }.buttonStyle(.glassProminent).disabled(hasSent)
            .accessibilityLabel("发送选中的动态表情").accessibilityIdentifier("chat.emoji.send")
    }
}
