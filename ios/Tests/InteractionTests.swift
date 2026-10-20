import XCTest
import UIKit
import SwiftUI
@testable import Nonto

@MainActor final class InteractionTests: XCTestCase {
    func testPostDisplayTrimsOnlyOuterWhitespaceWithoutChangingWireContent() {
        let original = " \n\t第一段\n\n第二段  内容\r\n "
        let post = Post(.object(["id": .id(1), "content": .text(original)]))
        XCTAssertEqual(PostText.trimmed(post.content), "第一段\n\n第二段  内容")
        XCTAssertEqual(post.content, original)
    }
    func testPostHighlightsUnicodeTopicsAndMentionsWithoutColoringEmailOrURLFragments() {
        let text = PostText.styled("🌅聊聊#生活，欢迎@小明 和 @user_name #旅行# #生活 mail@example.com https://example.test/#fragment")
        let highlighted = text.runs.filter { $0.foregroundColor == Color.brand }
            .map { String(text[$0.range].characters) }
        XCTAssertEqual(highlighted, ["#生活", "@小明", "@user_name", "#旅行#", "#生活"])
    }
    func testQuotedPostsBecomeAnOrderedThreadWithNoRepeatedWireIDs() {
        let first: JSON = .object(["id": .id(1), "content": .text("原帖")])
        let second: JSON = .object(["id": .id(2), "quoted_post": first])
        let third = Post(.object(["id": .id(3), "quoted_post": second]))
        XCTAssertEqual(PostThread.items(from: third).map(\.id), [3, 2, 1])
        let repeated = Post(.object(["id": .id(1), "quoted_post": second]))
        XCTAssertEqual(PostThread.items(from: repeated).map(\.id), [1, 2])
        let unavailable = Post(.object(["id": .id(4), "quoted_post": .object(["id": .id(1), "unavailable": .bool(true)])]))
        XCTAssertEqual(PostThread.items(from: unavailable).map(\.id), [4])
    }
    func testPostPhotoRowsKeepGalleryOrderAndStableIdentityForRepeatedURLs() {
        for count in 1...12 {
            let urls = (0..<count).map { "https://example.test/\($0).jpg" }
            let ordered = PostMediaLayout.rows(urls).flatMap(\.items)
            XCTAssertEqual(ordered.map(\.url), urls)
            XCTAssertEqual(ordered.map(\.index), Array(0..<count))
        }
        XCTAssertEqual(PostMediaLayout.rows(Array(repeating: "photo", count: 5)).map { $0.items.count }, [3, 2])
        XCTAssertEqual(PostMediaLayout.rows(Array(repeating: "photo", count: 7)).map { $0.items.count }, [3, 2, 2])
        let original = PostMediaLayout.items(["a", "b", "a"]).filter { $0.url == "a" }.map(\.id)
        let inserted = PostMediaLayout.items(["new", "a", "b", "a"]).filter { $0.url == "a" }.map(\.id)
        XCTAssertEqual(original, inserted)
        XCTAssertEqual(Set(original).count, 2)
    }
    func testImageCaptionsHideSourceURLsWhileKeepingWrittenDescriptions() {
        let media = "https://example.test/photo.jpg"
        XCTAssertEqual(ImageMessageCaption.text(" \n" + media + "\n", media: media), "")
        XCTAssertEqual(ImageMessageCaption.text("这张很好看\n" + media, media: media), "这张很好看")
        XCTAssertEqual(ImageMessageCaption.text("保留图片说明", media: media), "保留图片说明")
        XCTAssertEqual(ImageMessageCaption.text("https://example.test/photo.jpg?size=large", media: media), "")
        XCTAssertEqual(ImageMessageCaption.text("请看 https://example.test/article", media: media), "请看 https://example.test/article")
    }
    func testLeavingTimelineRestoresVisibleNavigationBarAndPreviousSwipePolicy() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let chrome = ScrollChrome()
        chrome.enableSwipe(in: navigation)
        XCTAssertTrue(navigation.hidesBarsOnSwipe)
        navigation.setNavigationBarHidden(true, animated: false)
        chrome.restoreNavigationBar()
        XCTAssertFalse(navigation.hidesBarsOnSwipe)
        XCTAssertFalse(navigation.isNavigationBarHidden)

        navigation.hidesBarsOnSwipe = true
        chrome.enableSwipe(in: navigation)
        chrome.restoreNavigationBar()
        XCTAssertTrue(navigation.hidesBarsOnSwipe)
    }
    func testReplacingTimelineCannotLetOldCleanupDisableTheVisibleTimeline() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let oldList = ScrollChrome(), newList = ScrollChrome()
        oldList.enableSwipe(in: navigation)
        newList.enableSwipe(in: navigation)
        oldList.restoreNavigationBar()
        XCTAssertTrue(navigation.hidesBarsOnSwipe)
        newList.restoreNavigationBar()
        XCTAssertFalse(navigation.hidesBarsOnSwipe)
    }
    func testTimelineSwipePolicyStaysIndependentAcrossTabs() {
        let feed = UINavigationController(rootViewController: UIViewController())
        let profile = UINavigationController(rootViewController: UIViewController())
        let feedChrome = ScrollChrome(), profileChrome = ScrollChrome()
        feedChrome.enableSwipe(in: feed); profileChrome.enableSwipe(in: profile)
        feedChrome.restoreNavigationBar()
        XCTAssertFalse(feed.hidesBarsOnSwipe)
        XCTAssertTrue(profile.hidesBarsOnSwipe)
        profileChrome.restoreNavigationBar()
    }
    func testNavigationRoutesRemainIndependentAndIgnoreRepeatedOrInvalidTaps() {
        let feed = AppNavigation(), inbox = AppNavigation()
        feed.open(.profile(42)); feed.open(.profile(42))
        feed.open(.post(91)); feed.open(.profile(0)); feed.open(.post(-1))
        XCTAssertEqual(feed.path, [.profile(42), .post(91)])
        inbox.open(.chat(Conversation(.object(["id": .id(8)]))))
        XCTAssertEqual(inbox.path.count, 1)
        feed.path.removeLast(); feed.open(.post(91))
        XCTAssertEqual(feed.path.count, 2)
        XCTAssertEqual(inbox.path.count, 1)
    }
    func testRouteIdentityUsesResourceKindAndServerIDRatherThanMutableSnapshot() {
        let post = Post(.object(["id": .id(9), "content": .text("updated")]))
        XCTAssertEqual(AppRoute.post(9), .post(9, initial: post))
        XCTAssertNotEqual(AppRoute.post(9), .profile(9))
        XCTAssertNotEqual(AppRoute.chat(Conversation(.object(["id": .id(9)]))),
                          .chat(Conversation(.object(["id": .id(9), "type": .text("community"), "community_id": .id(9)]))))
        XCTAssertEqual(Set([AppRoute.post(9), .post(9, initial: post)]).count, 1)
    }
    func testAuthorAndConversationUseCorrectWireIDsAndInvalidQuoteCannotNavigate() {
        let post = Post(.object(["id": .id(4), "author": .object(["id": .id(77)]), "quoted_post": .object(["unavailable": .bool(false)])]))
        XCTAssertEqual(post.userID, 77)
        XCTAssertNil(post.quoted)
        let room = Conversation(.object(["id": .id(7), "conversation_id": .id(63)]))
        XCTAssertEqual(room.id, 63)
    }
    func testGalleryClampsInitialPageAndChatImagesPreserveOrderExcludingRecall() {
        XCTAssertEqual(GalleryPosition.clamped(-2, count: 3), 0)
        XCTAssertEqual(GalleryPosition.clamped(9, count: 3), 2)
        XCTAssertEqual(GalleryPosition.clamped(9, count: 0), 0)
        let messages = [ChatMessage(.object(["id": .id(1), "message_type": .text("image"), "media_url": .text("https://example.test/a.jpg")])),
                        ChatMessage(.object(["id": .id(2), "message_type": .text("image"), "media_url": .text("https://example.test/b.jpg"), "is_recalled": .bool(true)])),
                        ChatMessage(.object(["id": .id(3), "message_type": .text("image"), "media_url": .text("file:///private/a")])),
                        ChatMessage(.object(["id": .id(4), "message_type": .text("image"), "media_url": .text("https://example.test/c.jpg")]))]
        XCTAssertEqual(ChatMediaTimeline.images(messages).map(\.id), [1, 4])
    }
    func testLargePhotoDecodeIsBoundedBeforeItBecomesATimelineThumbnail() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 2000), format: format).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 2000))
        }
        let thumbnail = try ImageRepository.decode(data, maxPixelSize: 128)
        XCTAssertEqual(thumbnail.size.width, 64, accuracy: 1)
        XCTAssertEqual(thumbnail.size.height, 128, accuracy: 1)
        XCTAssertThrowsError(try ImageRepository.decode(Data([0, 1, 2]), maxPixelSize: 128))
    }
    func testPinchSurfaceFitsImageAndKeepsHorizontalSwipesAvailableUntilZoomed() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
        let image = renderer.image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800)) }
        let surface = ImageScrollView(); surface.frame = CGRect(x: 0, y: 0, width: 300, height: 500)
        surface.display(image); surface.layoutIfNeeded()
        XCTAssertEqual(surface.minimumZoomScale, 0.25, accuracy: 0.001)
        XCTAssertFalse(surface.panGestureRecognizer.isEnabled)
        surface.setZoomScale(0.75, animated: false)
        surface.layoutIfNeeded()
        XCTAssertTrue(surface.panGestureRecognizer.isEnabled)
        surface.setZoomScale(surface.minimumZoomScale, animated: false); surface.layoutIfNeeded()
        XCTAssertFalse(surface.panGestureRecognizer.isEnabled)
    }
}
