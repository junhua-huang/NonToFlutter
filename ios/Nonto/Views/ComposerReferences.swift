import SwiftUI
import Observation
import UIKit

/// UIKit owns the live text selection. Only bounded UTF-16 offsets cross the picker boundary.
@MainActor @Observable
final class ComposerEditor {
    var text = ""
    var referenceKind: ComposerReferenceKind?
    @ObservationIgnored private(set) weak var textView: UITextView?
    @ObservationIgnored private var selection = NSRange(location: 0, length: 0)
    @ObservationIgnored private var snapshot: (text: String, selection: NSRange)?
    @ObservationIgnored private var pending: (value: String, kind: ComposerReferenceKind)?
    @ObservationIgnored private var wasEditing = false
    @ObservationIgnored private var focusTicket = UUID()
    @ObservationIgnored private var updatingNative = false
    var hasReferenceSession: Bool { snapshot != nil }
    func replaceText(_ value: String) {
        text = value; selection = NSRange(location: value.utf16.count, length: 0)
    }

    func attach(_ view: UITextView) { textView = view }
    func detach(_ view: UITextView) { if textView === view { textView = nil; focusTicket = UUID() } }
    func record(_ view: UITextView, changedText: Bool) {
        guard !updatingNative else { return }
        if changedText, text != view.text { text = view.text }
        selection = view.selectedRange
    }
    func beginReference(_ kind: ComposerReferenceKind) {
        guard referenceKind == nil, snapshot == nil else { return }
        focusTicket = UUID(); pending = nil
        wasEditing = textView?.isFirstResponder == true
        // Resigning commits any marked CJK input before the snapshot is captured.
        textView?.resignFirstResponder()
        if let view = textView { record(view, changedText: true) }
        snapshot = (text, ComposerReferenceInsertion.safeSelection(selection, in: text))
        referenceKind = kind
    }
    func stageReference(_ value: String, kind: ComposerReferenceKind) {
        guard referenceKind == kind, snapshot != nil, pending == nil else { return }
        pending = (value, kind)
    }
    func finishReference(allowed: Bool = true) {
        let choice = pending, source = snapshot, shouldFocus = wasEditing || choice != nil
        pending = nil; snapshot = nil; wasEditing = false
        guard allowed, referenceKind == nil else { focusTicket = UUID(); return }
        if let choice, let source, source.text == text {
            let result = ComposerReferenceInsertion.insert(choice.value, kind: choice.kind, into: source.text, selection: source.selection)
            text = result.text
            selection = ComposerReferenceInsertion.safeSelection(NSRange(location: result.caretUTF16, length: 0), in: text)
        }
        synchronize()
        guard shouldFocus else { return }
        let ticket = UUID(); focusTicket = ticket
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusTicket == ticket, self.referenceKind == nil,
                  let view = self.textView, view.window != nil else { return }
            self.synchronize()
            let target = ComposerReferenceInsertion.safeSelection(self.selection, in: self.text)
            self.updatingNative = true
            view.becomeFirstResponder(); view.selectedRange = target
            self.selection = target; self.updatingNative = false
        }
    }
    func synchronize() {
        guard let view = textView, view.markedTextRange == nil else { return }
        if view.text != text {
            let target = ComposerReferenceInsertion.safeSelection(selection, in: text)
            updatingNative = true
            view.text = text; view.selectedRange = target
            selection = target; updatingNative = false
        }
    }
}

struct ComposerTextEditor: View {
    let editor: ComposerEditor
    var body: some View {
        ComposerNativeTextView(editor: editor).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if editor.text.isEmpty {
                    Text("有什么新鲜事？").font(.title3).foregroundStyle(.tertiary)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

private struct ComposerNativeTextView: UIViewRepresentable {
    let editor: ComposerEditor
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear; view.textColor = .label
        let font = UIFont.preferredFont(forTextStyle: .title3); view.font = font
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        view.typingAttributes = [.font: font, .paragraphStyle: paragraph]
        view.accessibilityLabel = "动态内容"; view.accessibilityIdentifier = "post.composer.body"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        editor.attach(view); editor.synchronize()
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { editor.attach(view); editor.synchronize() }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let line = (uiView.font?.lineHeight ?? 24) + 4
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(line * 6, min(fit.height, line * 20)))
    }
    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        view.delegate = nil; coordinator.editor.detach(view)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        let editor: ComposerEditor
        init(editor: ComposerEditor) { self.editor = editor }
        func textViewDidChange(_ textView: UITextView) { editor.record(textView, changedText: true) }
        func textViewDidChangeSelection(_ textView: UITextView) { editor.record(textView, changedText: false) }
    }
}

struct ComposerReference: Identifiable {
    let id: Int
    let value: String
    let title: String
    let avatar: String
}

@MainActor @Observable
final class ComposerReferenceStore {
    private(set) var items: [ComposerReference] = []
    private(set) var loading = false
    private(set) var hasMore = false
    private(set) var error: String?
    private let api: APIClient
    private let kind: ComposerReferenceKind
    private let epoch: UUID
    private var friends: [ComposerReference]?
    private var query = ""
    private var page = 0
    private var requestID = UUID()
    init(api: APIClient, kind: ComposerReferenceKind) {
        self.api = api; self.kind = kind; epoch = api.generation
    }
    func cancel() { requestID = UUID() }
    func load(_ text: String, nextPage: Bool = false) async {
        guard !nextPage || (!loading && hasMore), epoch == api.generation else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticket = UUID(); requestID = ticket
        if query != value { items = []; hasMore = false }
        query = value; loading = true; error = nil
        defer { if requestID == ticket { loading = false } }
        do {
            if kind == .mention {
                let all: [ComposerReference]
                if let friends { all = friends }
                else {
                    let json = try await api.request("/friends/")
                    all = Records.unique(try PagedResource<Person>.rows(json, keys: ["friends", "users", "items"]).map(Person.init))
                        .filter { !$0.username.isEmpty }.map { ComposerReference(id: $0.id, value: $0.username, title: $0.name, avatar: $0.avatar) }
                }
                try Task.checkCancellation()
                guard requestID == ticket, epoch == api.generation else { return }
                friends = all
                items = all.filter { value.isEmpty || $0.value.localizedStandardContains(value) || $0.title.localizedStandardContains(value) }
                hasMore = false
            } else {
                if !value.isEmpty && !nextPage { try await Task.sleep(for: .milliseconds(250)) }
                let requestedPage = nextPage ? page + 1 : 1
                let json = try await api.request(value.isEmpty ? "/topics/trending" : "/topics/",
                    query: value.isEmpty ? ["limit": "30"] : ["q": value, "page": String(requestedPage), "per_page": "30"])
                try Task.checkCancellation()
                guard requestID == ticket, epoch == api.generation else { return }
                let topics = Records.unique(try PagedResource<Topic>.rows(json, keys: ["topics", "items"]).map(Topic.init)).filter { !$0.name.isEmpty }
                let batch = topics.map { ComposerReference(id: $0.id, value: $0.name, title: $0.name, avatar: "") }
                let known = Set(items.map(\.id))
                items = nextPage ? items + batch.filter { !known.contains($0.id) } : batch
                hasMore = !value.isEmpty && batch.count >= 30 && json["has_more"] != .bool(false) && (!nextPage || batch.contains { !known.contains($0.id) })
                page = requestedPage
            }
        } catch {
            if requestID == ticket, epoch == api.generation, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct ComposerReferencePicker: View {
    let kind: ComposerReferenceKind
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var store: ComposerReferenceStore
    init(api: APIClient, kind: ComposerReferenceKind, onSelect: @escaping (String) -> Void) {
        self.kind = kind; self.onSelect = onSelect
        _store = State(initialValue: ComposerReferenceStore(api: api, kind: kind))
    }
    var body: some View {
        NavigationStack {
            List {
                Section(query.isEmpty ? (kind == .mention ? "我的好友" : "热门话题") : "搜索结果") {
                    ForEach(store.items) { item in
                        Button {
                            onSelect(item.value); dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                if kind == .mention { AvatarView(url: item.avatar, name: item.title, size: 38) }
                                else { Image(systemName: "number").font(.title2).foregroundStyle(Color.brand).frame(width: 38) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary)
                                    if kind == .mention { Text("@\(item.value)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("插入到动态正文")
                    }
                }
                if store.loading { ProgressView("正在加载…").frame(maxWidth: .infinity) }
                if let error = store.error {
                    ErrorBanner(text: error) { Task { await store.load(query, nextPage: store.hasMore && !store.items.isEmpty) } }
                } else if !store.loading && store.items.isEmpty {
                    ContentUnavailableView(query.isEmpty ? (kind == .mention ? "还没有好友" : "暂无热门话题") : "没有找到结果",
                        systemImage: kind == .mention ? "person.2" : "number",
                        description: Text(query.isEmpty ? "也可以直接在正文输入\(kind.marker)名称。" : "试试其他关键词。"))
                }
                if store.hasMore && !store.loading {
                    Button("加载更多话题") { Task { await store.load(query, nextPage: true) } }.frame(minHeight: 44)
                }
            }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: kind == .mention ? "搜索好友昵称或用户名" : "搜索话题")
                .scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .task(id: query) { await store.load(query) }
                .onDisappear { store.cancel() }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct ComposerMediaThumbnail: View {
    let item: SelectedMedia
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: item.isVideo ? "video" : "photo").font(.title) }
        }.frame(width: 72, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: item.id) {
                guard !item.isVideo else { return }
                let data = item.data, pixels = Int(72 * displayScale)
                let decoded = try? await Task.detached(priority: .userInitiated) { try ImageRepository.decode(data, maxPixelSize: pixels) }.value
                if !Task.isCancelled { image = decoded }
            }
    }
}
