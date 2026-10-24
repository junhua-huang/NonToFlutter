import XCTest
import SwiftUI
import Lottie
@testable import Nonto

@MainActor final class NotoEmojiTests: XCTestCase {
    func testAllAnimationsAndPreviewsLoadOffline() throws {
        XCTAssertEqual(NotoEmojiCatalog.all.count, 881)
        XCTAssertEqual(Set(NotoEmojiCatalog.all.map(\.id)).count, 881)
        for item in NotoEmojiCatalog.all {
            try autoreleasepool {
                let animation = try LottieAnimation.from(data: Data(contentsOf: XCTUnwrap(item.animationURL)))
                XCTAssertGreaterThan(animation.endFrame, animation.startFrame, item.id)
                XCTAssertGreaterThan(animation.framerate, 0, item.id)
                XCTAssertNotNil(UIImage(contentsOfFile: try XCTUnwrap(item.previewURL).path), item.id)
            }
        }
    }
    func testOnlySupportedEmojiOnlyTextMessagesAnimate() throws {
        XCTAssertEqual(NotoEmojiCatalog.standalone(in: "😀")?.first?.id, "1f600")
        XCTAssertEqual(NotoEmojiCatalog.standalone(in: "😀 😀😀")?.count, 3)
        XCTAssertEqual(NotoEmojiCatalog.standalone(in: "❤")?.first?.id, NotoEmojiCatalog.standalone(in: "❤️")?.first?.id)
        XCTAssertNotNil(NotoEmojiCatalog.standalone(in: "❤️‍🔥"))
        XCTAssertNotNil(NotoEmojiCatalog.standalone(in: "👍🏽"))
        for text in ["", "你好😀", "😀😀😀😀", "abc", "❤\u{FE0E}", String(repeating: "😀", count: 100)] {
            XCTAssertNil(NotoEmojiCatalog.standalone(in: text), text)
        }
        let text = ChatMessage(.object(["message_type": .text("text"), "content": .text("😀")]))
        XCTAssertNotNil(text.notoEmoji)
        XCTAssertNil(ChatMessage(text.raw.merging(.object(["is_recalled": .bool(true)]))).notoEmoji)
        XCTAssertNil(ChatMessage(text.raw.merging(.object(["message_type": .text("image")]))).notoEmoji)
    }
    func testSearchAndAccountIsolatedRecents() throws {
        let smile = try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600"))
        XCTAssertTrue(smile.matches("笑")); XCTAssertTrue(smile.matches("SMILE"))
        XCTAssertTrue(smile.matches("😀")); XCTAssertFalse(smile.matches("猫"))
        let name = "noto-recents-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = NotoEmojiRecents(accountID: 1, defaults: defaults)
        for item in NotoEmojiCatalog.all.prefix(30) { first.record(item) }
        first.record(smile); first.record(smile)
        XCTAssertEqual(first.items.count, 24)
        XCTAssertEqual(first.items.first, smile)
        XCTAssertEqual(first.items.filter { $0 == smile }.count, 1)
        XCTAssertTrue(NotoEmojiRecents(accountID: 2, defaults: defaults).items.isEmpty)
        NotoEmojiRecents(accountID: 0, defaults: defaults).record(smile)
        XCTAssertTrue(NotoEmojiRecents(accountID: 0, defaults: defaults).items.isEmpty)
    }
    func testPickerReviewScreenshot() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: NotoEmojiPicker(accountID: 0) { _ in false }.preferredColorScheme(.light))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        controller.loadViewIfNeeded(); controller.view.frame = window.bounds; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Noto-emoji-picker-iOS27"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertFalse(NotoEmojiCatalog.all.isEmpty)
    }
}
