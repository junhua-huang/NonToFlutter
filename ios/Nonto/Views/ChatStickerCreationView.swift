import SwiftUI

struct ChatStickerCreationView: View {
    @Environment(\.appAccent) private var accent
    @Bindable var browser: ChatStickerBrowser
    let api: APIClient
    let epoch: UUID
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var operation: Task<Void, Never>?
    @State private var saved = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let prepared = browser.prepared {
                        StickerArtwork(image: prepared.image).frame(maxWidth: 360, minHeight: 180, maxHeight: 320)
                            .accessibilityLabel("新贴纸预览")
                    }
                    if browser.canToggleBackground {
                        Button(browser.usingCutout ? "保留原图背景" : "提取主体") { browser.toggleBackground() }
                            .buttonStyle(.bordered).disabled(browser.busy)
                    }
                    TextField("贴纸名称（可选）", text: $browser.name).textFieldStyle(.roundedBorder).disabled(browser.busy)
                        .onChange(of: browser.name) { _, value in if value.count > 40 { browser.name = String(value.prefix(40)) } }
                        .accessibilityIdentifier("chat.stickers.name")
                    if let notice = browser.preparationNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if let error = browser.error { ErrorBanner(text: error) }
                    Text("添加后可在贴纸面板中选择，放入聊天输入区发送。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .safeAreaBar(edge: .bottom) {
                Button(action: save) {
                    HStack { if browser.busy { ProgressView() }; Text(browser.busy ? "正在添加…" : "添加贴纸") }
                        .foregroundStyle(browser.canCommit && !saved ? accent.foregroundColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!browser.canCommit || saved).padding(16)
                    .accessibilityIdentifier("chat.stickers.save")
            }
            .navigationTitle("新贴纸").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { operation?.cancel(); browser.cancel(); dismiss() } } }
        }
        .interactiveDismissDisabled(browser.busy)
        .onDisappear { operation?.cancel(); browser.cancel() }
    }
    private func save() {
        guard operation == nil, !saved else { return }
        operation = Task {
            defer { operation = nil }
            let result = await browser.commit(send: false, isValid: { api.generation == epoch && api.token != nil }) { data in
                guard api.generation == epoch else { throw ChatStickerError.signedOut }
                return try await api.upload(data, filename: "sticker-\(UUID()).png", mime: "image/png", type: "chat")
            } enqueue: { _ in false }
            if result { saved = true; onSaved(); dismiss() }
        }
    }
}
