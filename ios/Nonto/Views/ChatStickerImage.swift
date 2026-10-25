import SwiftUI

/// Button tint and selection colors never replace a sticker's original pixels.
struct StickerArtwork: View {
    let image: UIImage
    var body: some View { Image(uiImage: image).renderingMode(.original).resizable().scaledToFit() }
}

/// Preserve alpha and the entire image; stickers have no photo crop or bubble fill.
struct ChatStickerImage: View {
    let url: String
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: String, image: UIImage)?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if let loaded, loaded.url == url { StickerArtwork(image: loaded.image).accessibilityLabel("贴纸") }
            else if failed {
                Button { retry += 1 } label: {
                    Label("重新加载", systemImage: "arrow.clockwise").font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("贴纸加载失败，重新加载")
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel("正在加载贴纸") }
        }
            .task(id: "\(url)#\(retry)") {
                loaded = nil; failed = false
                do {
                    let image = try await ImageRepository.shared.image(at: url, maxPixelSize: Int(192 * displayScale), reload: retry > 0)
                    try Task.checkCancellation(); loaded = (url, image)
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}
