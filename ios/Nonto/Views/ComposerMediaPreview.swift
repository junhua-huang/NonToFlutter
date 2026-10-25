import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposerAttachmentTile: View {
    let item: SelectedMedia
    let index: Int
    let count: Int
    let open: () -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                GeometryReader { geometry in
                    ComposerMediaThumbnail(item: item, side: geometry.size.width)
                        .overlay(alignment: .bottomLeading) {
                            Label(item.isVideo ? "预览视频" : "\(index + 1)", systemImage: item.isVideo ? "play.fill" : "photo")
                                .font(.caption.bold()).padding(8).foregroundStyle(.white)
                                .background(.black.opacity(0.55), in: Capsule()).padding(8)
                        }
                }.aspectRatio(1, contentMode: .fit)
            }.buttonStyle(.plain)
                .accessibilityLabel(item.isVideo ? "预览视频" : "预览第 \(index + 1) 张照片")
                .contextMenu {
                    if index > 0 { Button("向前移动", systemImage: "arrow.left") { move(-1) } }
                    if index < count - 1 { Button("向后移动", systemImage: "arrow.right") { move(1) } }
                    Button("移除", systemImage: "trash", role: .destructive, action: remove)
                }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.isVideo ? "移除视频" : "移除第 \(index + 1) 张照片")
        }
    }
}

/// Local previews never upload the selection; the video file lives only for this sheet.
struct ComposerMediaPreview: View {
    let item: SelectedMedia
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let videoURL { NativeVideo(url: videoURL) }
                else if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .containerRelativeFrame(.horizontal)
                    }.defaultScrollAnchor(.center)
                } else if let error {
                    ContentUnavailableView("无法预览", systemImage: "exclamationmark.triangle", description: Text(error))
                } else { ProgressView("正在准备预览…") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(item.isVideo ? "视频预览" : "照片预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task(id: item.id) { await preparePreview() }
                .onDisappear { if let videoURL { try? FileManager.default.removeItem(at: videoURL) } }
        }
    }
    private func preparePreview() async {
        do {
            if item.isVideo {
                let data = item.data
                let ext = UTType(mimeType: item.mime)?.preferredFilenameExtension ?? "mov"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonto-preview-\(UUID().uuidString).\(ext)")
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try data.write(to: url, options: [.atomic, .completeFileProtection])
                    }.value
                    try Task.checkCancellation(); videoURL = url
                } catch { try? FileManager.default.removeItem(at: url); throw error }
            } else {
                let data = item.data
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try ImageRepository.decode(data, maxPixelSize: 2560)
                }.value
                try Task.checkCancellation(); image = decoded
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
