import SwiftUI

struct NotoEmojiPicker: View {
    let accountID: Int
    let onSend: (NotoEmoji) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category = "全部"
    @State private var selection: NotoEmoji?
    @State private var recents: [NotoEmoji] = []
    @State private var error: String?
    @State private var showingCredits = false
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
    private var filtered: [NotoEmoji] {
        let source = category == "最近" ? recents : NotoEmojiCatalog.all
        return source.filter { (category == "全部" || category == "最近" || $0.category == category) && $0.matches(query) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(["全部", "最近"] + NotoEmojiCatalog.categories, id: \.self) { value in
                            Button(value) { category = value }
                                .buttonStyle(.bordered).tint(category == value ? Color.brand : .secondary)
                                .accessibilityAddTraits(category == value ? .isSelected : [])
                        }
                    }.padding(.horizontal).padding(.vertical, 8)
                }.scrollIndicators(.hidden)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(filtered) { item in
                            Button { selection = item; error = nil } label: {
                                NotoEmojiPoster(item: item).frame(width: 52, height: 52)
                                    .frame(maxWidth: .infinity, minHeight: 68)
                                    .background(selection?.id == item.id ? Color.brand.opacity(0.14) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityLabel(item.name)
                                .accessibilityHint("预览动画并选择发送")
                                .accessibilityIdentifier("noto.emoji.\(item.id)")
                                .accessibilityAddTraits(selection?.id == item.id ? .isSelected : [])
                        }
                    }.padding(.horizontal).padding(.bottom)
                }.overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView(category == "最近" && query.isEmpty ? "还没有最近使用的表情" : "没有找到表情",
                            systemImage: "face.smiling", description: Text("试试其他分类、中文名称或 emoji"))
                    }
                }
                preview
            }
            .navigationTitle("动态表情").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索表情，如开心、爱心或 cat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCredits = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("表情资源与许可")
                }
            }
            .onAppear { recents = NotoEmojiRecents(accountID: accountID).items }
            .sheet(isPresented: $showingCredits) { NavigationStack { NotoEmojiCreditsView() } }
        }.presentationDetents([.large])
    }
    private var preview: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Group {
                    if let selection { NotoEmojiAnimation(item: selection).id(selection.id) }
                    else { Image(systemName: "face.smiling").font(.largeTitle).foregroundStyle(.secondary) }
                }.frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection?.name ?? "选择一个表情").font(.headline).lineLimit(2)
                    Text("Noto Emoji · Google").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("发送") {
                    guard let selection else { return }
                    if onSend(selection) {
                        NotoEmojiRecents(accountID: accountID).record(selection); dismiss()
                    } else { error = "暂时无法发送，请返回聊天检查登录状态" }
                }.buttonStyle(.glassProminent).disabled(selection == nil)
                    .accessibilityLabel("发送选中的动态表情").accessibilityIdentifier("chat.emoji.send")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding().background(.bar)
    }
}

struct NotoEmojiCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nonto.native.animated-emoji") private var animations = true
    var body: some View {
        Form {
            Section { Toggle("播放动态表情", isOn: $animations) }
            footer: { Text("开启“减弱动态效果”时，表情会显示为静态图片。") }
            Section("Animated Noto Emoji") {
                Text("创作者：Google")
                Text("许可：Creative Commons Attribution 4.0 International（CC BY 4.0）")
                Link("官方表情库", destination: URL(string: "https://googlefonts.github.io/noto-emoji-animation/")!)
                Link("许可说明", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                Text("原始 Lottie 动画保持不变；南图生成了缩放后的静态预览。动画资源随 App 提供。")
                NavigationLink("完整许可文本") { license("CC-BY-4.0") }
            }
            Section("中文名称与搜索词") {
                Text("来自 Unicode CLDR。")
                NavigationLink("Unicode 许可") { license("UNICODE-LICENSE") }
            }
            Section("动画播放器") {
                Text("Lottie iOS · Airbnb · Apache License 2.0")
                NavigationLink("Lottie 许可") { license("Lottie-LICENSE") }
            }
        }.navigationTitle("表情资源与许可").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
    private func license(_ name: String) -> some View {
        ScrollView {
            Text(NotoEmojiCatalog.asset(name, extension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "许可文本暂不可用")
                .font(.caption).textSelection(.enabled).padding()
        }.navigationTitle(name)
    }
}
