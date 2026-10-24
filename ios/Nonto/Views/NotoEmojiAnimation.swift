import SwiftUI
import UIKit
import Lottie

actor NotoEmojiPosterCache {
    static let shared = NotoEmojiPosterCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.totalCostLimit = 8 * 1024 * 1024; cache.countLimit = 160 }
    func image(for item: NotoEmoji) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: item.id as NSString) { return image }
        guard let url = item.previewURL, let data = try? Data(contentsOf: url),
              let image = try? ImageRepository.decode(data, maxPixelSize: 192) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 96 * 96 * 4
        cache.setObject(image, forKey: item.id as NSString, cost: cost)
        return image
    }
}

actor NotoEmojiAnimationCache {
    static let shared = NotoEmojiAnimationCache()
    private let cache = NSCache<NSString, LottieAnimation>()
    init() { cache.countLimit = 12 }
    func animation(for item: NotoEmoji) -> LottieAnimation? {
        guard !Task.isCancelled else { return nil }
        if let animation = cache.object(forKey: item.id as NSString) { return animation }
        guard let url = item.animationURL, let data = try? Data(contentsOf: url),
              let animation = try? LottieAnimation.from(data: data) else { return nil }
        cache.setObject(animation, forKey: item.id as NSString)
        return animation
    }
}

struct NotoEmojiPoster: View {
    let item: NotoEmoji
    @State private var poster: (id: String, image: UIImage)?
    var body: some View {
        Group {
            if let poster, poster.id == item.id {
                Image(uiImage: poster.image).resizable().scaledToFit()
            } else { Text(item.emoji).font(.largeTitle) }
        }
        .task(id: item.id) {
            guard let image = await NotoEmojiPosterCache.shared.image(for: item), !Task.isCancelled else { return }
            poster = (item.id, image)
        }
        .accessibilityHidden(true)
    }
}

struct NotoEmojiAnimation: View {
    let item: NotoEmoji
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("nonto.native.animated-emoji") private var enabled = true
    @State private var visible = false
    var body: some View {
        Group {
            if isActive && enabled && !reduceMotion && phase == .active && visible {
                LottieView { () async throws -> LottieAnimation? in
                    await NotoEmojiAnimationCache.shared.animation(for: item)
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
