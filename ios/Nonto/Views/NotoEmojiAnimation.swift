import SwiftUI
import UIKit
import Lottie

@MainActor private final class NotoEmojiPosterCache {
    static let shared = NotoEmojiPosterCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.totalCostLimit = 8 * 1024 * 1024; cache.countLimit = 160 }
    func image(for item: NotoEmoji) -> UIImage? {
        if let image = cache.object(forKey: item.id as NSString) { return image }
        guard let url = item.previewURL, let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: item.id as NSString, cost: 96 * 96 * 4)
        return image
    }
}

struct NotoEmojiPoster: View {
    let item: NotoEmoji
    var body: some View {
        Group {
            if let image = NotoEmojiPosterCache.shared.image(for: item) {
                Image(uiImage: image).resizable().scaledToFit()
            } else { Text(item.emoji).font(.largeTitle) }
        }.accessibilityHidden(true)
    }
}

struct NotoEmojiAnimation: View {
    let item: NotoEmoji
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("nonto.native.animated-emoji") private var enabled = true
    @State private var visible = false
    var body: some View {
        Group {
            if enabled && !reduceMotion && phase == .active && visible, let url = item.animationURL {
                LottieView { () async throws -> LottieAnimation? in
                    try await Task.detached(priority: .userInitiated) {
                        try LottieAnimation.from(data: Data(contentsOf: url))
                    }.value
                } placeholder: { NotoEmojiPoster(item: item) }
                    .looping().resizable().backgroundBehavior(.pauseAndRestore)
            } else { NotoEmojiPoster(item: item) }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .accessibilityElement(children: .ignore).accessibilityLabel(item.name)
    }
}
