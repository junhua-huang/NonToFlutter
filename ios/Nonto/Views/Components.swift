import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct AvatarView: View {
    var url: String
    var name: String
    var size: CGFloat = 44
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.brand.opacity(0.12)
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped() }
            else { Text(String(name.prefix(1))).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Color.brand) }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
            .task(id: url) {
                image = nil
                if let result = try? await ImageRepository.shared.image(at: url, maxPixelSize: 256), !Task.isCancelled { image = result }
            }
    }
}

struct ProfileCover: View {
    let url: String
    var height: CGFloat? = 144
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { LinearGradient(colors: [Color.brand.opacity(0.28), Color.brand.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.frame(height: height).accessibilityHidden(true)
            .task(id: url) {
                image = nil
                if let result = try? await ImageRepository.shared.image(at: url, maxPixelSize: 1200), !Task.isCancelled { image = result }
            }
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
    var compactEmpty = false
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
                if compactEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(emptyTitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(emptyDescription).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDescription))
                }
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
        }.padding(.vertical, 8)
    }
}
struct MediaView: View {
    let images: [String]
    let video: String
    var thumbnailHeight: CGFloat? = nil
    var galleryImages: [String]? = nil
    var galleryIndex: Int? = nil
    var postLayout = false
    var fitImage = false
    var onPresentationChange: (Bool) -> Void = { _ in }
    @State private var selected: MediaSelection?
    var body: some View {
        VStack(spacing: 8) {
            if !images.isEmpty {
                if postLayout && images.count > 1 {
                    PostImageGrid(images: images, open: open)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: images.count == 1 ? 1 : (images.count <= 4 ? 2 : 3)), spacing: 3) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, link in
                        MediaThumbnail(url: link, height: thumbnailHeight ?? (images.count == 1 ? 280 : (images.count <= 4 ? 150 : 110)), label: "查看图片 \(index + 1)", fitImage: fitImage) {
                            open(galleryIndex ?? index)
                        }
                    }
                    }.clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            if let url = URL(string: video), !video.isEmpty {
                if fitImage { ChatVideoPreview(url: url, height: thumbnailHeight ?? 190, onPresentationChange: onPresentationChange) }
                else { NativeVideo(url: url).frame(height: thumbnailHeight ?? 260).clipShape(RoundedRectangle(cornerRadius: 14)) }
            }
        }.fullScreenCover(item: $selected, onDismiss: { onPresentationChange(false) }) { selection in
            ImageGallery(images: galleryImages ?? images, initial: selection.index)
        }
    }
    private func open(_ index: Int) {
        onPresentationChange(true)
        selected = MediaSelection(index: index)
    }
}
private struct PostImageGrid: View {
    let images: [String]
    let open: (Int) -> Void
    private let spacing: CGFloat = 3
    var body: some View {
        GeometryReader { geometry in
            let items = PostMediaLayout.items(images)
            let rows = PostMediaLayout.rows(images)
            if items.count == 3 {
                HStack(spacing: spacing) {
                    tile(items[0], height: geometry.size.height)
                    VStack(spacing: spacing) {
                        tile(items[1], height: (geometry.size.height - spacing) / 2)
                        tile(items[2], height: (geometry.size.height - spacing) / 2)
                    }
                }
            } else {
                VStack(spacing: spacing) {
                    ForEach(rows) { row in
                        HStack(spacing: spacing) {
                            ForEach(row.items) { item in
                                tile(item, height: (geometry.size.height - CGFloat(rows.count - 1) * spacing) / CGFloat(rows.count))
                            }
                        }
                    }
                }
            }
        }.aspectRatio(PostMediaLayout.aspectRatio(count: images.count), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func tile(_ item: PostMediaLayout.Item, height: CGFloat) -> some View {
        MediaThumbnail(url: item.url, height: max(1, height), label: "查看图片 \(item.index + 1)，共 \(images.count) 张") {
            open(item.index)
        }
    }
}
private struct MediaThumbnail: View {
    let url: String
    let height: CGFloat
    let label: String
    var fitImage = false
    let open: () -> Void
    @State private var attempt = 0
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Button {
            if failed { attempt += 1 } else { open() }
        } label: {
            if fitImage, let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
            } else {
            GeometryReader { geometry in
                ZStack {
                    Color.secondary.opacity(0.08)
                    if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: height).clipped() }
                    else if failed {
                        VStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text("点按重试").font(.caption) }.foregroundStyle(.secondary)
                    } else { ProgressView() }
                }.frame(width: geometry.size.width, height: height).contentShape(Rectangle()).clipped()
            }.frame(height: height).frame(maxWidth: .infinity).contentShape(Rectangle()).clipped()
            }
        }.buttonStyle(.plain).contentShape(Rectangle()).accessibilityLabel(failed ? "图片加载失败，点按重试" : label)
            .task(id: "\(url)#\(attempt)") {
                image = nil; failed = false
                do {
                    let result = try await ImageRepository.shared.image(at: url, maxPixelSize: 960, reload: attempt > 0)
                    try Task.checkCancellation(); image = result
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}
private struct MediaSelection: Identifiable { let id = UUID(); var index: Int }
struct NativeVideo: View {
    let url: URL
    var autoplay = false
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url); if autoplay { player?.play() } }
            .onChange(of: url) { _, value in player?.pause(); player = AVPlayer(url: value); if autoplay { player?.play() } }
            .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
            .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
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
