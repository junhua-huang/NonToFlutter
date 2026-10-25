import Foundation

/// A picker visit adds to the current composition; validation never discards it.
struct ComposerAttachments {
    private(set) var items: [SelectedMedia] = []
    private var assets: [UUID: String] = [:]
    var canAddPhotos: Bool { !items.contains(where: \.isVideo) && items.count < 9 }
    var remainingCount: Int { max(0, 9 - items.count) }

    mutating func append(_ incoming: [SelectedMedia], assetIDs: [String?] = []) throws {
        var known = Set(assets.values)
        var additions: [(SelectedMedia, String?)] = []
        for (index, item) in incoming.enumerated() {
            let asset = assetIDs.indices.contains(index) ? assetIDs[index] : nil
            if let asset, !known.insert(asset).inserted { continue }
            additions.append((item, asset))
        }
        let combined = items + additions.map(\.0)
        guard combined.count <= 9 else { throw APIError(status: 0, message: "每条动态最多添加 9 张照片") }
        guard !combined.contains(where: \.isVideo) || combined.count == 1 else {
            throw APIError(status: 0, message: "视频需要单独发布，请先移除照片或视频")
        }
        items = combined
        for (item, asset) in additions { if let asset { assets[item.id] = asset } }
    }
    mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }; assets.removeValue(forKey: id)
    }
    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        let item = items.remove(at: index); items.insert(item, at: index + offset)
    }
    /// Resolve a native drag by identity; stale drops leave the composition intact.
    mutating func reorder(_ sources: [UUID], before target: UUID? = nil) {
        let ids = Set(sources)
        guard !ids.isEmpty, ids.count == sources.count,
              ids.isSubset(of: Set(items.map(\.id))) else { return }
        if let target {
            guard !ids.contains(target), items.contains(where: { $0.id == target }) else { return }
        }
        let moved = items.filter { ids.contains($0.id) }
        var remaining = items.filter { !ids.contains($0.id) }
        let destination = target.flatMap { id in remaining.firstIndex(where: { $0.id == id }) } ?? remaining.endIndex
        remaining.insert(contentsOf: moved, at: destination)
        items = remaining
    }
}
