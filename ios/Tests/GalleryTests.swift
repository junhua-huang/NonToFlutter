import XCTest
import UIKit
@testable import Nonto

@MainActor final class GalleryTests: XCTestCase {
    private func image(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
    }
    func testRepeatedURLsStillHaveDistinctStablePagesAndFiniteEdges() throws {
        let pager = GalleryPagerController(images: ["", "", ""], initial: 0)
        pager.loadViewIfNeeded()
        let first = try XCTUnwrap(pager.viewControllers?.first)
        let second = try XCTUnwrap(pager.pageViewController(pager, viewControllerAfter: first))
        XCTAssertFalse(first === second)
        XCTAssertTrue(second === pager.pageViewController(pager, viewControllerAfter: first))
        XCTAssertTrue(first === pager.pageViewController(pager, viewControllerBefore: second))
        XCTAssertNil(pager.pageViewController(pager, viewControllerBefore: first))
        let third = try XCTUnwrap(pager.pageViewController(pager, viewControllerAfter: second))
        XCTAssertNil(pager.pageViewController(pager, viewControllerAfter: third))
    }
    func testChromeRefreshAndCancelledSwipeKeepTheActualPageController() throws {
        let pager = GalleryPagerController(images: ["", ""], initial: 0)
        pager.loadViewIfNeeded()
        let first = try XCTUnwrap(pager.viewControllers?.first)
        let second = try XCTUnwrap(pager.pageViewController(pager, viewControllerAfter: first))
        pager.pageViewController(pager, willTransitionTo: [second])
        pager.show(images: ["", ""], index: 0, animated: true)
        XCTAssertTrue(first === pager.viewControllers?.first)
        XCTAssertEqual(pager.visibleIndex, 0)
        XCTAssertTrue(pager.transitioning)
        pager.pageViewController(pager, didFinishAnimating: true, previousViewControllers: [first], transitionCompleted: false)
        XCTAssertFalse(pager.transitioning)
        XCTAssertEqual(pager.visibleIndex, 0)
        XCTAssertTrue(first === pager.viewControllers?.first)
    }
    func testArrowNavigationCommitsTheActualFinalPage() async throws {
        let pager = GalleryPagerController(images: ["", "", ""], initial: 0)
        pager.loadViewIfNeeded()
        let completed = expectation(description: "New native page selected")
        pager.onSelect = { index in if index == 2 { completed.fulfill() } }
        pager.show(images: ["", "", ""], index: 2, animated: false)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(pager.visibleIndex, 2)
        XCTAssertFalse(pager.transitioning)
    }
    func testHighResolutionUpgradeKeepsMagnificationAndViewport() async {
        let surface = ImageScrollView()
        surface.frame = CGRect(x: 0, y: 0, width: 300, height: 500)
        surface.display(image(CGSize(width: 300, height: 200))); surface.layoutIfNeeded()
        surface.setZoomScale(surface.minimumZoomScale * 2.5, animated: false)
        surface.layoutIfNeeded(); surface.contentOffset = CGPoint(x: 100, y: 0)
        let offset = surface.contentOffset, factor = surface.zoomScale / surface.minimumZoomScale
        surface.display(image(CGSize(width: 1200, height: 800)), preservingViewport: true)
        surface.layoutIfNeeded()
        XCTAssertEqual(surface.zoomScale / surface.minimumZoomScale, factor, accuracy: 0.01)
        XCTAssertEqual(surface.contentOffset.x, offset.x, accuracy: 1)
        XCTAssertEqual(surface.contentOffset.y, offset.y, accuracy: 1)
        XCTAssertTrue(surface.panGestureRecognizer.isEnabled)
    }
    func testCachedPreviewIsImmediatelyAvailableAndClearedWithAccountCache() {
        let repository = ImageRepository(), photo = image(CGSize(width: 300, height: 200))
        let url = "https://gallery.example.test/photo.jpg"
        repository.rememberUploadedPreview(photo, at: url)
        XCTAssertTrue(repository.cachedImage(at: url) === photo)
        repository.clear()
        XCTAssertNil(repository.cachedImage(at: url))
    }
}
