import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposerAttachmentTile: View {
    let item: SelectedMedia
    let index: Int
    let count: Int
    var large = false
    let open: () -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewButton
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.isVideo ? "移除视频" : "移除第 \(index + 1) 张照片")
        }
    }
    @ViewBuilder private var previewButton: some View {
        if #available(iOS 27, *) {
            // Native reordering owns the long press. VoiceOver keeps explicit move actions.
            thumbnailButton
        } else {
            thumbnailButton.contextMenu {
                if index > 0 { Button("向前移动", systemImage: "arrow.left") { move(-1) } }
                if index < count - 1 { Button("向后移动", systemImage: "arrow.right") { move(1) } }
                Button("移除", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }
    private var thumbnailButton: some View {
        Button(action: open) {
            GeometryReader { geometry in
                ComposerMediaThumbnail(item: item, side: geometry.size.width, aspect: aspect)
                    .overlay(alignment: .bottomLeading) {
                        Text(item.isVideo ? "▶ 预览视频" : index == 0 && count > 1 ? "1 · 首图" : "\(index + 1)")
                            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 5).foregroundStyle(.white)
                            .background(.black.opacity(0.55), in: Capsule()).padding(8).accessibilityHidden(true)
                    }
            }.aspectRatio(aspect, contentMode: .fit)
        }.buttonStyle(.plain)
            .accessibilityLabel(item.isVideo ? "预览视频" : "预览第 \(index + 1) 张照片")
            .accessibilityActions {
                if index > 0 { Button("向前移动") { move(-1) } }
                if index < count - 1 { Button("向后移动") { move(1) } }
            }
    }
    private var aspect: CGFloat { large ? (item.isVideo ? 16.0 / 9 : 4.0 / 3) : 1 }
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
