import XCTest
import SwiftUI
import Observation
import UIKit
@testable import Nonto

@MainActor final class NotoEmojiPickerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let account = 990150
    override func setUp() async throws {
        try await super.setUp()
        suite = "noto-picker-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }
    private func browser() -> NotoEmojiBrowser { NotoEmojiBrowser(accountID: account, defaults: defaults) }
    private func smile() throws -> NotoEmoji { try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600")) }

    func testGlobalSearchFromCategorySupportsNamesAliasesAndEmoji() throws {
        let model = browser()
        model.show(.category("动物与自然"))
        XCTAssertTrue(model.items.allSatisfy { $0.category == "动物与自然" })
        model.query = "  开心  "
        XCTAssertTrue(model.items.contains(try smile()))
        XCTAssertEqual(model.title, "搜索结果")
        model.query = "SMILE"
        XCTAssertTrue(model.items.contains(try smile()))
        model.query = "❤"
        let heart = try XCTUnwrap(NotoEmojiCatalog.standalone(in: "❤️")?.first)
        XCTAssertTrue(model.items.contains(heart))
        model.query = "cat 动物"
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertTrue(model.items.allSatisfy { $0.category == "动物与自然" })
        model.query = "a-query-that-does-not-exist-990150"
        XCTAssertTrue(model.items.isEmpty)
        model.show(.all)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.items.count, 881)
    }
    func testChangingSearchOrScopeClearsTheOldSendSelection() throws {
        let model = browser(), item = try smile()
        model.select(item); XCTAssertEqual(model.selection, item)
        model.query = "heart"
        XCTAssertNil(model.selection)
        model.select(try XCTUnwrap(model.items.first))
        model.show(.recent)
        XCTAssertNil(model.selection); XCTAssertFalse(model.isSearching); XCTAssertTrue(model.items.isEmpty)
    }
    func testFavoritesPersistInTheirAccountAndDoNotCreateRecents() throws {
        let item = try smile(), model = browser()
        model.toggleFavorite(item)
        XCTAssertTrue(model.favoriteIDs.contains(item.id))
        XCTAssertTrue(NotoEmojiRecents(accountID: account, defaults: defaults).items.isEmpty)
        let reopened = browser()
        XCTAssertEqual(reopened.scope, .favorites); XCTAssertEqual(reopened.items, [item])
        let other = NotoEmojiBrowser(accountID: account + 1, defaults: defaults)
        XCTAssertFalse(other.favoriteIDs.contains(item.id)); XCTAssertEqual(other.scope, .all)
        reopened.toggleFavorite(item)
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertFalse(browser().favoriteIDs.contains(item.id))
        let anonymous = NotoEmojiBrowser(accountID: 0, defaults: defaults)
        anonymous.toggleFavorite(item)
        XCTAssertTrue(anonymous.favoriteIDs.isEmpty)
    }
    func testOnlyAnAcceptedSendRecordsRecentAndCommitsOnce() throws {
        let model = browser(), item = try smile()
        var attempts = 0
        XCTAssertFalse(model.send { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 0)
        model.select(item)
        XCTAssertFalse(model.send { _ in attempts += 1; return false })
        XCTAssertFalse(model.hasSent); XCTAssertNotNil(model.error); XCTAssertEqual(model.selection, item)
        XCTAssertTrue(NotoEmojiRecents(accountID: account, defaults: defaults).items.isEmpty)
        XCTAssertTrue(model.send { sent in attempts += 1; XCTAssertEqual(sent, item); return true })
        XCTAssertFalse(model.send { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 2); XCTAssertNil(model.error)
        XCTAssertEqual(NotoEmojiRecents(accountID: account, defaults: defaults).items, [item])
        XCTAssertEqual(browser().scope, .recent)
    }
    func testOfflinePosterAndAnimationModelsAreReused() async throws {
        let item = try smile()
        let posters = NotoEmojiPosterCache(), animations = NotoEmojiAnimationCache()
        let firstPoster = await posters.image(for: item)
        let secondPoster = await posters.image(for: item)
        XCTAssertNotNil(firstPoster); XCTAssertTrue(firstPoster === secondPoster)
        let firstAnimation = await animations.animation(for: item)
        let secondAnimation = await animations.animation(for: item)
        XCTAssertNotNil(firstAnimation); XCTAssertTrue(firstAnimation === secondAnimation)
    }
    func testPickerLayoutsAtPhoneLargeTextAndWideSizes() async throws {
        let model = browser()
        try await capture(model, size: CGSize(width: 390, height: 844), name: "emoji-picker-browse")
        model.query = "开心"
        try await capture(model, size: CGSize(width: 390, height: 844), name: "emoji-picker-search")
        model.query = ""; model.select(try smile()); model.toggleFavorite(try smile())
        try await capture(model, size: CGSize(width: 320, height: 740), name: "emoji-picker-selection-large-text", largeText: true)
        model.show(.favorites)
        try await capture(model, size: CGSize(width: 820, height: 1100), name: "emoji-picker-favorites-wide", dark: true)
    }
    func testPhoneSheetStartsCompactAndExpandsForRealSearchInput() async throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Phone sheet detents are verified in iPhone CI") }
        let model = browser(), presentation = NotoPickerPresentation()
        let host = try makeHost(NotoPickerSheetHarness(browser: model, presentation: presentation), size: CGSize(width: 390, height: 844))
        defer { host.close() }
        try await waitUntil("mount the sheet presenter") { host.controller.view.window === host.window }
        presentation.presented = true
        try await waitUntil("present the medium emoji sheet") {
            host.controller.presentedViewController?.sheetPresentationController?.selectedDetentIdentifier == .medium
                && host.controller.presentedViewController?.isBeingPresented == false
        }
        try await Task.sleep(for: .milliseconds(500))
        attach(host.window, name: "emoji-picker-medium-sheet")
        let presented = try XCTUnwrap(host.controller.presentedViewController)
        let field = try XCTUnwrap(descendants(presented.view).compactMap { $0 as? UITextField }.first)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "开心"; field.sendActions(for: .editingChanged)
        try await waitUntil("expand the sheet and apply native search input") {
            presented.sheetPresentationController?.selectedDetentIdentifier == .large
                && model.query == "开心" && model.items.contains { $0.id == "1f600" }
        }
        try await Task.sleep(for: .milliseconds(500))
        attach(host.window, name: "emoji-picker-expanded-search-keyboard")
        presentation.presented = false
        try await waitUntil("dismiss the picker before destroying its window") { host.controller.presentedViewController == nil }
    }
    private func waitUntil(_ stage: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard condition() else {
            XCTFail("Emoji picker must \(stage)")
            throw NSError(domain: "NotoPickerTransition", code: 1)
        }
    }
    private func capture(_ model: NotoEmojiBrowser, size: CGSize, name: String, dark: Bool = false, largeText: Bool = false) async throws {
        let view = NotoEmojiPickerContent(browser: model) { _ in false }
            .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
            .preferredColorScheme(dark ? .dark : .light)
        let host = try makeHost(view, size: size)
        defer { host.close() }
        try await waitUntil("mount its native search field") { self.descendants(host.controller.view).contains { $0 is UITextField } }
        try await Task.sleep(for: .milliseconds(700))
        let field = try XCTUnwrap(descendants(host.controller.view).compactMap { $0 as? UITextField }.first)
        let frame = field.convert(field.bounds, to: host.window)
        XCTAssertGreaterThan(frame.width, 100)
        XCTAssertGreaterThanOrEqual(frame.minX, 0); XCTAssertLessThanOrEqual(frame.maxX, size.width + 1)
        attach(host.window, name: name)
    }
    private func makeHost<V: View>(_ view: V, size: CGSize) throws -> PickerHost {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let controller = UIHostingController(rootView: AnyView(view.environment(\.scenePhase, .active)))
        controller.traitOverrides.horizontalSizeClass = size.width < 700 ? .compact : .regular
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); controller.view.frame = window.bounds; window.layoutIfNeeded()
        return PickerHost(window: window, controller: controller, previous: previous)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor private final class PickerHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    let previous: UIWindow?
    init(window: UIWindow, controller: UIHostingController<AnyView>, previous: UIWindow?) {
        self.window = window; self.controller = controller; self.previous = previous
    }
    func close() {
        window.endEditing(true); controller.dismiss(animated: false)
        controller.rootView = AnyView(EmptyView()); controller.view.layoutIfNeeded()
        window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
    }
}

@MainActor @Observable private final class NotoPickerPresentation { var presented = false }
private struct NotoPickerSheetHarness: View {
    let browser: NotoEmojiBrowser
    @Bindable var presentation: NotoPickerPresentation
    var body: some View {
        Color(uiColor: .systemGroupedBackground).overlay { Text("聊天") }
            .sheet(isPresented: $presentation.presented) { NotoEmojiPickerContent(browser: browser) { _ in false } }
    }
}
