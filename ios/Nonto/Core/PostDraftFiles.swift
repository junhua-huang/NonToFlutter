import Foundation

struct RestoredPostDraft: Sendable {
    let draft: PostDraft
    let media: [SelectedMedia]
    let assetIDs: [String?]
}

/// Immutable media files plus one atomic manifest, isolated by account and context.
/// The serial actor keeps disk work off the UI thread and rejects stale saves.
actor PostDraftFiles {
    static let shared = PostDraftFiles()
    private struct Item: Codable {
        let id: UUID
        let name: String
        let mime: String
        let assetID: String?
    }
    private struct Manifest: Codable { let draft: PostDraft; let items: [Item] }
    private var revisions: [String: UInt64] = [:]
    private var removedAccounts: [Int: UInt64] = [:]
    private let manager = FileManager.default
    private func folder(_ userID: Int, _ communityID: Int, _ quoteID: Int) throws -> URL {
        guard userID > 0, communityID >= 0, quoteID >= 0 else { throw APIError.sessionChanged }
        let root = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("NontoDrafts/\(userID)/\(communityID)-\(quoteID)", isDirectory: true)
    }
    private func protect(_ url: URL) throws {
        var url = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
    func read(userID: Int, communityID: Int, quoteID: Int) throws -> RestoredPostDraft? {
        let folder = try folder(userID, communityID, quoteID)
        let index = folder.appendingPathComponent("draft.json")
        guard manager.fileExists(atPath: index.path) else { return nil }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: index))
        guard manifest.items.count <= 9, Set(manifest.items.map(\.id)).count == manifest.items.count else { throw CocoaError(.fileReadCorruptFile) }
        let media = try manifest.items.map { item in
            guard ["image/jpeg", "video/mp4", "video/quicktime"].contains(item.mime) else { throw CocoaError(.fileReadCorruptFile) }
            let file = folder.appendingPathComponent(item.id.uuidString + ".media")
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 50 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            return SelectedMedia(id: item.id, data: try Data(contentsOf: file), name: item.name, mime: item.mime)
        }
        guard !media.contains(where: \.isVideo) || media.count == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return RestoredPostDraft(draft: manifest.draft, media: media, assetIDs: manifest.items.map(\.assetID))
    }
    func save(_ draft: PostDraft, media: [SelectedMedia], assetIDs: [String?], userID: Int,
              communityID: Int, quoteID: Int, revision: UInt64) throws {
        let folder = try folder(userID, communityID, quoteID)
        guard revision >= (revisions[folder.path] ?? 0), revision > (removedAccounts[userID] ?? 0) else { return }
        try Task.checkCancellation()
        guard media.count <= 9, !media.contains(where: \.isVideo) || media.count == 1 else { throw CocoaError(.fileWriteUnknown) }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try protect(folder)
        var items: [Item] = []
        for (index, item) in media.enumerated() {
            try Task.checkCancellation()
            let file = folder.appendingPathComponent(item.id.uuidString + ".media")
            if !manager.fileExists(atPath: file.path) {
                try item.data.write(to: file, options: [.atomic, .completeFileProtection])
                try protect(file)
            }
            items.append(Item(id: item.id, name: item.name, mime: item.mime, assetID: assetIDs.indices.contains(index) ? assetIDs[index] : nil))
        }
        try Task.checkCancellation()
        let file = folder.appendingPathComponent("draft.json")
        try JSONEncoder().encode(Manifest(draft: draft, items: items)).write(to: file, options: [.atomic, .completeFileProtection])
        try protect(file)
        revisions[folder.path] = revision
        // Remove unreferenced bytes only after the new manifest is durable.
        let retained = Set(items.map { $0.id.uuidString + ".media" }).union(["draft.json"])
        for file in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where !retained.contains(file.lastPathComponent) {
            try? manager.removeItem(at: file)
        }
    }
    func remove(userID: Int, communityID: Int, quoteID: Int, revision: UInt64) throws {
        let folder = try folder(userID, communityID, quoteID)
        guard revision >= (revisions[folder.path] ?? 0) else { return }
        revisions[folder.path] = revision
        if manager.fileExists(atPath: folder.path) { try manager.removeItem(at: folder) }
    }
    func removeAccount(_ userID: Int) throws {
        guard userID > 0 else { return }
        removedAccounts[userID] = DispatchTime.now().uptimeNanoseconds
        let folder = try folder(userID, 0, 0).deletingLastPathComponent()
        if manager.fileExists(atPath: folder.path) { try manager.removeItem(at: folder) }
    }
}
