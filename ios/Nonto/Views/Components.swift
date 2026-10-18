import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct AvatarView: View {
    var url: String
    var name: String
    var size: CGFloat = 44
    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { ZStack { Color.brand.opacity(0.12); Text(String(name.prefix(1))).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Color.brand) } }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct ErrorBanner: View {
    var text: String?
    var retry: (() -> Void)? = nil
    var body: some View {
        if let text {
            VStack(alignment: .leading, spacing: 8) {
                Label(text, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red)
                if let retry { Button("重试", action: retry) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct ResourceFooter<T: Record>: View {
    @ObservedObject var resource: PagedResource<T>
    var emptyTitle = "这里还没有内容"
    var emptyDescription = "稍后再来看看，或下拉刷新。"
    var emptyIcon = "tray"
    var body: some View {
        Group {
            if let error = resource.error {
                VStack(spacing: 8) {
                    if resource.showingCache { Label("当前显示本机缓存", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }
                    ErrorBanner(text: error) { Task { await resource.retry() } }
                }
            } else if resource.loading || (resource.page == 0 && resource.items.isEmpty) {
                ProgressView(resource.items.isEmpty ? "正在加载…" : "正在更新…").frame(maxWidth: .infinity).padding()
            } else if resource.hasMore {
                Button("加载更多") { Task { await resource.load() } }.frame(maxWidth: .infinity).padding()
                    .task(id: resource.page) {
                        guard resource.page > 0, !Task.isCancelled else { return }
                        await resource.load()
                    }
            } else if resource.items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDescription))
            } else { Text("已显示全部内容").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
        }.listRowSeparator(.hidden)
    }
}
struct PersonRow: View {
    var person: Person
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: person.avatar, name: person.name)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(person.name).font(.headline); if !person.verifiedLabels.isEmpty { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.brand) } }
                Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                if !person.bio.isEmpty { Text(person.bio).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.padding(.vertical, 4)
    }
}
struct MediaView: View {
    let images: [String]
    let video: String
    @State private var selected: MediaSelection?
    var body: some View {
        VStack(spacing: 8) {
            if !images.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: images.count == 1 ? 1 : min(3, images.count)), spacing: 5) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, link in
                        MediaThumbnail(url: link, height: images.count == 1 ? 300 : 120, label: "查看图片 \(index + 1)") {
                            selected = MediaSelection(index: index)
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let url = URL(string: video), !video.isEmpty { NativeVideo(url: url).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 14)) }
        }.fullScreenCover(item: $selected) { selection in ImageGallery(images: images, initial: selection.index) }
    }
}
private struct MediaThumbnail: View {
    let url: String
    let height: CGFloat
    let label: String
    let open: () -> Void
    @State private var attempt = 0
    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            Button {
                if phase.error != nil {
                    if let url = URL(string: url) { URLCache.shared.removeCachedResponse(for: URLRequest(url: url)) }
                    attempt += 1
                } else { open() }
            } label: {
                ZStack {
                    Color.secondary.opacity(0.08)
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil {
                        VStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text("点按重试").font(.caption) }.foregroundStyle(.secondary)
                    } else { ProgressView() }
                }.frame(height: height).frame(maxWidth: .infinity).clipped()
            }.buttonStyle(.plain).accessibilityLabel(phase.error == nil ? label : "图片加载失败，点按重试")
        }.id("\(url)#\(attempt)")
    }
}
private struct MediaSelection: Identifiable { let id = UUID(); var index: Int }
struct NativeVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
            .onChange(of: url) { _, value in player?.pause(); player = AVPlayer(url: value) }
            .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
            .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}
struct ImageGallery: View {
    let images: [String]
    let initial: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, link in ZoomImage(url: link).tag(i) }
            }.tabViewStyle(.page).onAppear { index = initial }
            HStack {
                Text("\(index + 1) / \(images.count)").foregroundStyle(.white)
                Spacer()
                if images.indices.contains(index), let url = URL(string: images[index]) { ShareLink(item: url).foregroundStyle(.white).padding(.trailing) }
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white) }.accessibilityLabel("关闭图片")
            }.padding()
        }
    }
}
struct ZoomImage: View {
    let url: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        Group {
            if let image { ZoomImageSurface(image: image) }
            else if failed {
                VStack(spacing: 16) {
                    Label("图片加载失败", systemImage: "photo.badge.exclamationmark").foregroundStyle(.white)
                    Button("重新加载") { attempt += 1 }.buttonStyle(.glass)
                }
            } else { ProgressView().tint(.white) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(url)#\(attempt)") {
                image = nil; failed = false
                do {
                    guard let link = URL(string: url), ["https", "http"].contains(link.scheme ?? "") else { throw URLError(.badURL) }
                    let (data, response) = try await URLSession.shared.data(from: link)
                    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                    try Task.checkCancellation(); image = decoded
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}

private struct ZoomImageSurface: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView() }
    func updateUIView(_ view: ImageScrollView, context: Context) { view.display(image) }
}

/// UIScrollView keeps content size, pan bounds and pinch zoom in sync.
private final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let picture = UIImageView()
    private var fittedSize = CGSize.zero
    init() {
        super.init(frame: .zero)
        delegate = self; backgroundColor = .clear
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        picture.isAccessibilityElement = true; picture.accessibilityLabel = "图片，可双指缩放"
        addSubview(picture)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func display(_ image: UIImage) {
        guard picture.image !== image else { return }
        zoomScale = 1; picture.image = image; picture.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size; fittedSize = .zero; setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let image = picture.image, bounds.width > 0, bounds.height > 0, fittedSize != bounds.size {
            fittedSize = bounds.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit; maximumZoomScale = fit * 5; zoomScale = fit
        }
        centerImage()
    }
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2), y = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true); return }
        let point = gesture.location(in: picture), scale = minimumZoomScale * 2.5
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}

struct SelectedMedia: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let name: String
    let mime: String
    var isVideo: Bool { mime.hasPrefix("video/") }
    static func image(_ data: Data) throws -> SelectedMedia {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1920
              ] as CFDictionary) else { throw APIError(status: 0, message: "无法读取这张照片") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { throw APIError(status: 0, message: "图片转换失败") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw APIError(status: 0, message: "图片转换失败") }
        return SelectedMedia(data: output as Data, name: "photo-\(UUID().uuidString).jpg", mime: "image/jpeg")
    }
}

struct MovieTransfer: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { item in SentTransferredFile(item.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("nonto-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return MovieTransfer(url: destination)
        }
    }
}
enum MediaLoader {
    static func load(_ item: PhotosPickerItem) async throws -> SelectedMedia {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try await item.loadTransferable(type: MovieTransfer.self) else { throw APIError(status: 0, message: "无法读取视频") }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let size = (try movie.url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size <= 50 * 1024 * 1024 else { throw APIError(status: 0, message: "视频不能超过 50 MB") }
            let ext = movie.url.pathExtension.lowercased()
            return SelectedMedia(data: try Data(contentsOf: movie.url), name: movie.url.lastPathComponent,
                                 mime: ext == "mp4" ? "video/mp4" : "video/quicktime")
        }
        guard let data = try await item.loadTransferable(type: Data.self) else { throw APIError(status: 0, message: "无法读取照片") }
        let result = try await Task.detached(priority: .userInitiated) { try SelectedMedia.image(data) }.value
        try Task.checkCancellation()
        return result
    }
}
