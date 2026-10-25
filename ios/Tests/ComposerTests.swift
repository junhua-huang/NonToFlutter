import XCTest
import UIKit
@testable import Nonto

@MainActor final class ComposerTests: XCTestCase {
    private func photo() -> SelectedMedia { SelectedMedia(data: Data([1]), name: "photo.jpg", mime: "image/jpeg") }
    private func video() -> SelectedMedia { SelectedMedia(data: Data([2]), name: "movie.mp4", mime: "video/mp4") }

    func testPickingMorePhotosPreservesOrderAndDeduplicatesAssets() throws {
        var selection = ComposerAttachments()
        let first = photo(), second = photo(), third = photo()
        try selection.append([first, second], assetIDs: ["first", "second"])
        try selection.append([photo(), third], assetIDs: ["first", "third"])
        XCTAssertEqual(selection.items.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(selection.remainingCount, 6)
    }
    func testInvalidPickerBatchNeverDropsExistingPhotos() throws {
        var selection = ComposerAttachments()
        let first = photo()
        try selection.append([first])
        XCTAssertThrowsError(try selection.append([video()]))
        XCTAssertThrowsError(try selection.append((0..<9).map { _ in photo() }))
        XCTAssertEqual(selection.items.map(\.id), [first.id])
        XCTAssertTrue(selection.canAddPhotos)
    }
    func testOneVideoExcludesAdditionalPhotosAndVideos() throws {
        var selection = ComposerAttachments()
        let movie = video()
        try selection.append([movie])
        XCTAssertFalse(selection.canAddPhotos)
        XCTAssertThrowsError(try selection.append([video()]))
        XCTAssertThrowsError(try selection.append([photo()]))
        XCTAssertEqual(selection.items.map(\.id), [movie.id])
        selection.remove(movie.id)
        XCTAssertTrue(selection.canAddPhotos)
        try selection.append([photo()])
    }
    func testRemoveThenReselectAndReorderKeepStableAttachmentIdentity() throws {
        var selection = ComposerAttachments()
        let first = photo(), second = photo(), replacement = photo()
        try selection.append([first, second], assetIDs: ["a", "b"])
        selection.remove(first.id)
        try selection.append([replacement], assetIDs: ["a"])
        selection.move(replacement.id, by: -1)
        XCTAssertEqual(selection.items.map(\.id), [replacement.id, second.id])
        selection.move(replacement.id, by: -1)
        selection.move(second.id, by: 1)
        XCTAssertEqual(selection.items.map(\.id), [replacement.id, second.id])
    }
    func testFullPickerBatchAndMissingAssetIdentifiers() throws {
        var selection = ComposerAttachments()
        let photos = (0..<9).map { _ in photo() }
        try selection.append(photos)
        XCTAssertEqual(selection.items.map(\.id), photos.map(\.id))
        XCTAssertFalse(selection.canAddPhotos)
        XCTAssertEqual(selection.remainingCount, 0)
        selection.remove(photos[4].id)
        XCTAssertTrue(selection.canAddPhotos)
    }
    func testLeavingEditorCommitsItsCurrentTextBeforePublishOrClose() {
        let editor = ComposerEditor(), view = UITextView()
        editor.attach(view)
        view.text = "🌅 输入中的内容"
        editor.endEditing()
        XCTAssertEqual(editor.text, view.text)
        XCTAssertFalse(editor.isEditing)
    }
    func testDragReorderingKeepsSourceOrderAndAssetDeduplication() throws {
        var selection = ComposerAttachments()
        let photos = (0..<5).map { _ in photo() }
        try selection.append(photos, assetIDs: ["a", "b", "c", "d", "e"])
        selection.reorder([photos[3].id, photos[1].id], before: photos[0].id)
        XCTAssertEqual(selection.items.map(\.id), [photos[1], photos[3], photos[0], photos[2], photos[4]].map(\.id))
        selection.reorder([photos[1].id])
        XCTAssertEqual(selection.items.map(\.id), [photos[3], photos[0], photos[2], photos[4], photos[1]].map(\.id))
        try selection.append([photo()], assetIDs: ["b"])
        XCTAssertEqual(selection.items.count, 5, "Reordering must preserve picker asset identities")
    }
    func testStaleAndSelfTargetedDropsNeverRemoveAttachments() throws {
        var selection = ComposerAttachments()
        let photos = (0..<3).map { _ in photo() }
        try selection.append(photos)
        for sources in [[], [UUID()], [photos[0].id, UUID()], [photos[0].id, photos[0].id]] {
            selection.reorder(sources)
            XCTAssertEqual(selection.items.map(\.id), photos.map(\.id))
        }
        selection.reorder([photos[0].id], before: photos[0].id)
        selection.reorder([photos[0].id], before: UUID())
        XCTAssertEqual(selection.items.map(\.id), photos.map(\.id))
    }
}
