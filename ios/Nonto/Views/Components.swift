import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers

struct AvatarView: View {
    var url: String
    var name: String
    var size: CGFloat = 44
    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { ZStack { Color.brand.opacity(0.12); Text(String(name.prefix(1))).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.brand) } }
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
    var body: some View {
        Group {
            if resource.loading { ProgressView().frame(maxWidth: .infinity).padding() }
            else if let error = resource.error { ErrorBanner(text: error) { Task { await resource.load(reset: resource.items.isEmpty) } } }
            else if resource.hasMore { Button("加载更多") { Task { await resource.load() } }.frame(maxWidth: .infinity).padding() }
            else if resource.items.isEmpty { ContentUnavailableView("这里还没有内容", systemImage: "tray", description: Text("稍后再来看看，或下拉刷新。")) }
        }.listRowSeparator(.hidden)
    }
}
struct PersonRow: View {
    var person: Person
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: person.avatar, name: person.name)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(person.name).font(.headline); if !person.verifiedLabels.isEmpty { Image(systemName: "checkmark.seal.fill").foregroundStyle(.brand) } }
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
                        Button { selected = MediaSelection(index: index) } label: {
                            AsyncImage(url: URL(string: link)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { ZStack { Color.secondary.opacity(0.08); Image(systemName: "photo").foregroundStyle(.secondary) } }
                            }
                            .frame(height: images.count == 1 ? 300 : 120).frame(maxWidth: .infinity).clipped()
                        }.buttonStyle(.plain).accessibilityLabel("查看图片 \(index + 1)")
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let url = URL(string: video), !video.isEmpty { NativeVideo(url: url).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 14)) }
        }.fullScreenCover(item: $selected) { selection in ImageGallery(images: images, initial: selection.index) }
    }
}
private struct MediaSelection: Identifiable { let id = UUID(); var index: Int }
struct NativeVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
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
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            AsyncImage(url: URL(string: url)) { phase in
                if let image = phase.image { image.resizable().scaledToFit().containerRelativeFrame(.horizontal) }
                else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.white).padding(100) }
                else { ProgressView().tint(.white).padding(100) }
            }.scaleEffect(scale * magnification)
                .gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { scale = min(5, max(1, scale * $0)) })
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2 } }
        }.defaultScrollAnchor(.center)
    }
}

struct SelectedMedia: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
    let mime: String
    var isVideo: Bool { mime.hasPrefix("video/") }
    static func image(_ data: Data) throws -> SelectedMedia {
        guard let image = UIImage(data: data) else { throw APIError(status: 0, message: "无法读取这张照片") }
        let ratio = min(1, 1920 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { throw APIError(status: 0, message: "图片转换失败") }
        return SelectedMedia(data: jpeg, name: "photo-\(UUID().uuidString).jpg", mime: "image/jpeg")
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
        return try await MainActor.run { try SelectedMedia.image(data) }
    }
}
