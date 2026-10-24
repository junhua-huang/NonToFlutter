import SwiftUI

struct NotoEmojiPicker: View {
    // A picker owns one account's browser for the lifetime of its presentation.
    @State private var browser: NotoEmojiBrowser
    private let onSend: (NotoEmoji) -> Bool
    init(accountID: Int, onSend: @escaping (NotoEmoji) -> Bool) {
        _browser = State(initialValue: NotoEmojiBrowser(accountID: accountID))
        self.onSend = onSend
    }
    var body: some View { NotoEmojiPickerContent(browser: browser, onSend: onSend) }
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
