import SwiftUI
import Photos
import ImageIO

@MainActor final class ImageRepository {
    static let shared = ImageRepository()
    private let cache = NSCache<NSString, UIImage>()
    private var requests: [String: Task<UIImage, Error>] = [:]
    private var generation = UUID()
    private let session: URLSession
    init(session: URLSession = .shared) {
        self.session = session; cache.totalCostLimit = 48 * 1024 * 1024; cache.countLimit = 40
    }
    func clear() {
        generation = UUID(); cache.removeAllObjects()
        for request in requests.values { request.cancel() }; requests.removeAll()
    }
    /// The uploaded bytes are already available locally; do not download them again for the sent thumbnail.
    func rememberUploadedPreview(_ image: UIImage, at text: String) {
        guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: (url.absoluteString + "#uploaded-preview") as NSString, cost: cost)
    }
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) throws -> UIImage {
        guard data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(4096, max(64, maxPixelSize))
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return UIImage(cgImage: cg)
    }
    func image(at text: String, maxPixelSize: Int = 3072, reload: Bool = false) async throws -> UIImage {
        guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        let pixels = min(4096, max(64, maxPixelSize)), epoch = generation
        let key = url.absoluteString + "#nonto-decode-" + String(pixels)
        let previewKey = (url.absoluteString + "#uploaded-preview") as NSString
        if reload {
            cache.removeObject(forKey: key as NSString); cache.removeObject(forKey: previewKey)
            session.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))
        }
        let uploadedPreview = cache.object(forKey: previewKey)
        // A local chat thumbnail is immediate, but must not cap full-screen zoom quality.
        if let image = uploadedPreview, pixels <= 960 { return image }
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = requests[key] { return try await resolve(task, epoch: epoch, preview: uploadedPreview) }
        let task = Task { () throws -> UIImage in
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            try Task.checkCancellation()
            let decoded = try await Task.detached(priority: .userInitiated) { try Self.decode(data, maxPixelSize: pixels) }.value
            try Task.checkCancellation()
            return decoded
        }
        requests[key] = task
        defer { if epoch == generation { requests[key] = nil } }
        let image = try await resolve(task, epoch: epoch, preview: uploadedPreview)
        guard epoch == generation else { throw CancellationError() }
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    private func resolve(_ task: Task<UIImage, Error>, epoch: UUID, preview: UIImage?) async throws -> UIImage {
        do {
            let image = try await task.value
            guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
            return image
        } catch {
            guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
            // All coalesced viewers share the same offline fallback and account boundary.
            if let preview { return preview }
            throw error
        }
    }
}

enum GalleryPosition {
    static func clamped(_ index: Int, count: Int) -> Int { count > 0 ? min(max(0, index), count - 1) : 0 }
}
struct ImageGallery: View {
    let images: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var controls = true
    @State private var zoomed = false
    @State private var sharing: SharedImage?
    @State private var saving = false
    @State private var feedback: String?
    @State private var displayImage: UIImage?
    init(images: [String], initial: Int) {
        self.images = images
        _index = State(initialValue: GalleryPosition.clamped(initial, count: images.count))
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if images.isEmpty { ContentUnavailableView("图片不可用", systemImage: "photo").foregroundStyle(.white) }
            else {
                TabView(selection: $index) {
                    ForEach(images.indices, id: \.self) { i in
                        Group {
                            if abs(i - index) <= 1 {
                                ZoomImage(url: images[i], onTap: { controls.toggle() }, onZoom: { value in if index == i { zoomed = value } }, onLoaded: { image in if index == i { displayImage = image } })
                            } else { Color.black }
                        }.tag(i).accessibilityLabel("第 \(i + 1) 张图片，共 \(images.count) 张")
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if !zoomed, value.translation.height > 130, value.translation.height > abs(value.translation.width) * 1.5 { dismiss() }
                    })
            }
            if controls {
                VStack {
                    HStack(spacing: 16) {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("关闭图片")
                        Spacer()
                        Text("\(images.isEmpty ? 0 : index + 1) / \(images.count)").monospacedDigit()
                        Spacer()
                        Button { if let displayImage { sharing = SharedImage(image: displayImage) } } label: {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }.disabled(displayImage == nil).accessibilityLabel("分享图片")
                    }.padding(.horizontal, 10).background(.black.opacity(0.55))
                    Spacer()
                    if let feedback { Text(feedback).font(.subheadline).padding(10).background(.black.opacity(0.7), in: Capsule()) }
                    HStack(spacing: 16) {
                        Button { index = max(0, index - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .disabled(index == 0).accessibilityLabel("上一张图片")
                        Spacer()
                        Button { Task { await saveImage() } } label: {
                            if saving { ProgressView().tint(.white) } else { Label("保存图片", systemImage: "square.and.arrow.down") }
                        }.disabled(displayImage == nil || saving).frame(minHeight: 44)
                        Spacer()
                        Button { index = min(images.count - 1, index + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(images.isEmpty || index == images.count - 1).accessibilityLabel("下一张图片")
                    }.padding(.horizontal).background(.black.opacity(0.55))
                }.foregroundStyle(.white).buttonStyle(.plain)
            }
        }.accessibilityAction(.escape) { dismiss() }
            .statusBarHidden(!controls).persistentSystemOverlays(.hidden)
            .sheet(item: $sharing) { ImageShareSheet(image: $0.image) }
            .task(id: index) {
                displayImage = nil; feedback = nil; zoomed = false
                guard images.indices.contains(index) else { return }
                let selected = index
                if let image = try? await ImageRepository.shared.image(at: images[selected]), !Task.isCancelled, selected == index { displayImage = image }
            }
    }
    private func saveImage() async {
        guard let image = displayImage, !saving else { return }
        saving = true; defer { saving = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else { feedback = "请在系统设置中允许南图添加照片"; return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            feedback = "已保存到相册"
        } catch { feedback = "保存失败，请稍后重试" }
    }
}
private struct SharedImage: Identifiable { let id = UUID(); let image: UIImage }
private struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct ZoomImage: View {
    let url: String
    var onTap: () -> Void = {}
    var onZoom: (Bool) -> Void = { _ in }
    var onLoaded: (UIImage) -> Void = { _ in }
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        Group {
            if let image { ZoomImageSurface(image: image, onTap: onTap, onZoom: onZoom) }
            else if failed {
                VStack(spacing: 16) {
                    Label("图片加载失败", systemImage: "photo.badge.exclamationmark").foregroundStyle(.white)
                    Button("重新加载") { attempt += 1 }.buttonStyle(.glass)
                }
            } else { ProgressView().tint(.white) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: "\(url)#\(attempt)") {
                failed = false
                do {
                    let result = try await ImageRepository.shared.image(at: url, reload: attempt > 0)
                    try Task.checkCancellation(); image = result; onLoaded(result)
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}
struct ZoomImageSurface: UIViewRepresentable {
    let image: UIImage
    var onTap: () -> Void = {}
    var onZoom: (Bool) -> Void = { _ in }
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView() }
    func updateUIView(_ view: ImageScrollView, context: Context) {
        view.onTap = onTap; view.onZoom = onZoom; view.display(image)
    }
}
final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let picture = UIImageView()
    private var fittedSize = CGSize.zero
    private var reportedZoom = false
    var onTap: () -> Void = {}
    var onZoom: (Bool) -> Void = { _ in }
    init() {
        super.init(frame: .zero)
        delegate = self; backgroundColor = .clear; bouncesZoom = true
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        picture.isAccessibilityElement = true; picture.accessibilityLabel = "图片，可双指缩放或双击放大"
        addSubview(picture)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        singleTap.require(toFail: doubleTap); addGestureRecognizer(singleTap)
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
            minimumZoomScale = fit; maximumZoomScale = max(fit * 5, 1); zoomScale = fit
        }
        centerImage()
    }
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2), y = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
        // At fitted size, horizontal swipes belong to the gallery, not this page.
        let expanded = zoomScale > minimumZoomScale * 1.02
        panGestureRecognizer.isEnabled = expanded
        if expanded != reportedZoom {
            reportedZoom = expanded
            DispatchQueue.main.async { [weak self] in self?.onZoom(expanded) }
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    @objc private func tapped() { onTap() }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true); return }
        let point = gesture.location(in: picture), scale = min(maximumZoomScale, minimumZoomScale * 2.5)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
