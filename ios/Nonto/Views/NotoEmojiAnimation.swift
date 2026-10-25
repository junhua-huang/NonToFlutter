import SwiftUI
import UIKit
import Lottie

actor NotoEmojiPosterCache {
    static let shared = NotoEmojiPosterCache()
    private let cache = NSCache<NSString, UIImage>()
    private var unavailable = Set<String>()
    init() { cache.totalCostLimit = 8 * 1024 * 1024; cache.countLimit = 160 }
    func image(for item: NotoEmoji) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: item.id as NSString) { return image }
        guard !unavailable.contains(item.id) else { return nil }
        guard let url = item.previewURL, let data = try? Data(contentsOf: url),
              let image = try? ImageRepository.decode(data, maxPixelSize: 192),
              NotoEmojiPosterQuality.isVisible(image) else { unavailable.insert(item.id); return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 96 * 96 * 4
        cache.setObject(image, forKey: item.id as NSString, cost: cost)
        return image
    }
}

enum NotoEmojiPosterQuality {
    /// Some upstream first frames are transparent, or contain only a tiny entering fragment.
    /// A decoded PNG alone does not mean there is a usable thumbnail.
    nonisolated static func isVisible(_ image: UIImage) -> Bool {
        alphaCoverage(image) >= 20.0 / 1024
    }
    nonisolated static func alphaCoverage(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let count = pixels.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                                          bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 16 ? 1 : 0) }
        }
        return Double(count) / 1024
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
                StickerArtwork(image: poster.image)
            } else {
                GeometryReader { geometry in
                    Text(item.emoji).font(.system(size: max(1, min(geometry.size.width, geometry.size.height) * 0.82)))
                        .lineLimit(1).minimumScaleFactor(0.1).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
