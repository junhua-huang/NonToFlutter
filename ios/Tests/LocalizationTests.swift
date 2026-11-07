import XCTest
import SwiftUI
import UIKit
import CryptoKit
@testable import Nonto

@MainActor
final class LocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    func testCompiledResourcesIncludeAllLanguagesAndSystemPermissions() throws {
        for (language, hidden, block) in [("zh-Hans", "屏蔽此帖", "屏蔽此用户"),
                                          ("zh-Hant", "隱藏這則貼文", "封鎖此使用者"),
                                          ("en", "Hide this post", "Block this user"),
                                          ("fr", "Masquer cette publication", "Bloquer cet utilisateur"),
                                          ("ru", "Скрыть эту публикацию", "Заблокировать этого пользователя"),
                                          ("es", "Ocultar esta publicación", "Bloquear a este usuario"),
                                          ("ja", "この投稿を非表示", "このユーザーをブロック")] {
            let bundle = try languageBundle(language)
            XCTAssertEqual(bundle.localizedString(forKey: "屏蔽此帖", value: nil, table: nil), hidden)
            XCTAssertEqual(bundle.localizedString(forKey: "屏蔽此用户", value: nil, table: nil), block)
            for key in ["NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
                let value = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
                XCTAssertNotEqual(value, key)
                XCTAssertFalse(value.isEmpty)
                if ["en", "fr", "ru", "es"].contains(language) { XCTAssertNil(value.range(of: #"\p{Han}"#, options: .regularExpression)) }
            }
        }
    }

    func testCompiledInterpolationAndEnglishPlurals() throws {
        let bundle = try languageBundle("en")
        let one = 1, many = 3, percent = 25
        XCTAssertEqual(String(localized: "\(one) 条新消息", bundle: bundle, locale: Locale(identifier: "en")), "1 new message")
        XCTAssertEqual(String(localized: "\(many) 条新消息", bundle: bundle, locale: Locale(identifier: "en")), "3 new messages")
        XCTAssertEqual(String(localized: "正在上传 \(one)/\(many) · \(percent)%", bundle: bundle, locale: Locale(identifier: "en")), "Uploading 1/3 · 25%")
        let username = "小明_%@"
        XCTAssertEqual(String(localized: "屏蔽 @\(username)？", bundle: bundle), "Block @小明_%@?")
        XCTAssertEqual(AppLocalization.serverError("验证码无效或已过期", bundle: bundle), "The verification code is invalid or has expired.")
        XCTAssertEqual(AppLocalization.serverError("unknown server text 小明", bundle: bundle), "unknown server text 小明")
        XCTAssertEqual(ChatSticker.messageContent, "[贴纸]", "Protocol markers must remain stable in every language")
    }

    func testPolicyTranslationAndLanguageSelectionDoNotChangeConsentRevision() throws {
        let profile = ComplianceProfile.current
        for language in AppLanguage.supported {
            for kind in LegalDocument.allCases {
                let url = try XCTUnwrap(Bundle.main.url(forResource: kind.rawValue, withExtension: "txt", subdirectory: nil, localization: language))
                let template = try String(contentsOf: url, encoding: .utf8)
                XCTAssertFalse(profile.render(template).contains("{{"))
                XCTAssertGreaterThan(PolicySection.parse(template).count, 7)
                if language == "en" { XCTAssertTrue(template.contains("1. Scope")) }
            }
        }
        // Hash canonical source files, not the language chosen for presentation.
        var canonical = Data()
        canonical.append(try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "Compliance", withExtension: "json"))))
        for kind in LegalDocument.allCases {
            canonical.append(try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: kind.rawValue, withExtension: "txt", subdirectory: nil, localization: "zh-Hans"))))
        }
        let expected = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ComplianceProfile.revision, expected)
    }

    func testSelectedLanguageResolvesDynamicLabelsAndEmojiWithoutChangingIDs() throws {
        let language = AppLocalization.language
        print("Localization run language: \(language)")
        let labels = [AppAccent.blue.name, ChatAttachmentAction.camera.title, ServiceAgeGroup.adult.title]
        if language == "en" {
            XCTAssertEqual(labels, ["NonTo Blue", "Camera", "18 or older"])
            XCTAssertEqual(String(localized: "注销"), "DELETE")
            XCTAssertEqual(AppLocalization.emojiCategory("笑脸与情感"), "Smileys and emotion")
        } else if language == "zh-Hant" {
            XCTAssertEqual(AppAccent.blue.name, "南圖藍")
            XCTAssertEqual(String(localized: "注销"), "註銷")
        }
        let item = try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600"))
        XCTAssertFalse(item.localizedName.isEmpty)
        if language == "en" { XCTAssertEqual(item.localizedName, "smile") }
        XCTAssertEqual(item.id, "1f600")
        XCTAssertEqual(item.category, "笑脸与情感")
        XCTAssertEqual(NotoEmojiScope.category(item.category).id, "category/笑脸与情感")
        XCTAssertTrue(NotoEmojiSearchIndex(items: [item]).search(item.localizedName).contains(item))
        XCTAssertTrue(item.matches(item.localizedName))
        XCTAssertEqual(StagedChatSticker(source: .noto(item)).name, item.localizedName)
    }

    func testSelectedLanguageScreensAtNarrowAndLargeTextSizes() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { _ in (200, .object(["blocks": .array([]), "posts": .array([]), "has_more": .bool(false)])) }
        defer { StubProtocol.handler = nil }
        let api = APIClient(baseURL: URL(string: "https://localization.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        let session = AppSession(api: api); session.restoring = false
        defer { try? LocalCache.clear(userID: 970091) }
        session.user = Person(.object(["id": .id(970091), "username": .text("原文_Original"), "display_name": .text("原文 Original")]))
        await session.refreshContentSafety()
        XCTAssertNil(session.contentSafetyError)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let screens: [(String, AnyView)] = [
            ("sign-in", AnyView(AuthView())),
            ("settings", AnyView(NavigationStack { SettingsView() })),
            ("blocked", AnyView(NavigationStack { BlockedUsersView(session: session) })),
            ("delete", AnyView(NavigationStack { DeleteAccountView() }))
        ]
        for (name, view) in screens {
            for width in [CGFloat(320), CGFloat(834)] {
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
                let controller = UIHostingController(rootView: view.environmentObject(session)
                    .environment(\.dynamicTypeSize, .accessibility1))
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.loadViewIfNeeded(); controller.view.frame = window.bounds
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(300))
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                XCTAssertEqual(controller.view.bounds.width, width, accuracy: 1)
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "localization-\(AppLocalization.language)-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        previous?.makeKeyAndVisible()
    }

    func testInAppPreferencePersistsAndOverridesOnlyAppLanguage() throws {
        let suite = "language-preference-\(UUID())"
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppLanguage.stored(in: isolated), .system)
        isolated.set(AppLanguage.traditionalChinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.stored(in: isolated), .traditionalChinese)
        isolated.set("unknown", forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.stored(in: isolated), .system)
        XCTAssertEqual(AppLanguage.system.resolvedLanguage(preferences: ["en-GB"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedLanguage(preferences: ["zh-Hant-TW"]), "zh-Hant")
        for (preference, expected) in [("fr-CA", "fr"), ("ru-RU", "ru"), ("es-MX", "es"), ("ja-JP", "ja")] {
            XCTAssertEqual(AppLanguage.system.resolvedLanguage(preferences: [preference]), expected)
            let choice = try XCTUnwrap(AppLanguage(rawValue: expected))
            isolated.set(choice.rawValue, forKey: AppLanguage.storageKey)
            XCTAssertEqual(AppLanguage.stored(in: isolated), choice)
            XCTAssertEqual(choice.resolvedLanguage(preferences: ["en-US"]), expected)
        }
        XCTAssertFalse(AppLanguage.supported.contains("ar"))
        XCTAssertEqual(Set(AppLanguage.supported), ["zh-Hans", "zh-Hant", "en", "fr", "ru", "es", "ja"])
        let base = Locale(identifier: "zh_CN@calendar=buddhist")
        let english = AppLanguage.english.locale(base: base)
        XCTAssertEqual(english.language.languageCode?.identifier, "en")
        XCTAssertEqual(english.region, base.region)
        XCTAssertEqual(english.calendar.identifier, base.calendar.identifier)
    }

    func testNewLanguagePluralRulesAndEmojiLabels() throws {
        let expected = [
            "fr": ["1 nouveau message", "2 nouveaux messages", "5 nouveaux messages", "21 nouveaux messages"],
            "ru": ["1 новое сообщение", "2 новых сообщения", "5 новых сообщений", "21 новое сообщение"],
            "es": ["1 mensaje nuevo", "2 mensajes nuevos", "5 mensajes nuevos", "21 mensajes nuevos"],
            "ja": ["新しいメッセージ1件", "新しいメッセージ2件", "新しいメッセージ5件", "新しいメッセージ21件"]
        ]
        for language in ["fr", "ru", "es", "ja"] {
            let bundle = try languageBundle(language)
            for (index, count) in [1, 2, 5, 21].enumerated() {
                XCTAssertEqual(String(localized: "\(count) 条新消息", bundle: bundle, locale: Locale(identifier: language)), expected[language]?[index])
            }
        }
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.storageKey)
        defer { if let original { defaults.set(original, forKey: AppLanguage.storageKey) } else { defaults.removeObject(forKey: AppLanguage.storageKey) } }
        let item = try XCTUnwrap(NotoEmojiCatalog.item(id: "1f600"))
        for language in ["fr", "ru", "es", "ja"] {
            defaults.set(language, forKey: AppLanguage.storageKey)
            XCTAssertNotEqual(item.localizedName, item.name)
            XCTAssertTrue(item.matches(item.localizedName))
            XCTAssertEqual(item.id, "1f600")
            XCTAssertNotEqual(AppLocalization.serverError("验证码无效或已过期"), "验证码无效或已过期")
        }
    }

    func testRuntimePreferenceChangesImperativeCopyPoliciesAndCachedStatus() throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.storageKey)
        defer { if let original { defaults.set(original, forKey: AppLanguage.storageKey) } else { defaults.removeObject(forKey: AppLanguage.storageKey) } }
        let revision = ComplianceProfile.revision
        let wire = ChatSticker.messageContent
        let push = APNsService(register: {}, unregister: {})
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.storageKey)
        let oldError = APIError(status: 0, message: AppLocalization.string("无法读取照片"))
        for (choice, title, policy) in [(AppLanguage.english, "NonTo Blue", "NonTo Privacy Policy"),
                                        (.traditionalChinese, "南圖藍", "南圖隱私政策"),
                                        (.french, "Bleu NonTo", "Politique de confidentialité de NonTo"),
                                        (.russian, "Синий NonTo", "Политика конфиденциальности NonTo"),
                                        (.spanish, "Azul NonTo", "Política de privacidad de NonTo"),
                                        (.japanese, "NonToブルー", "NonToプライバシーポリシー"),
                                        (.simplifiedChinese, "南图蓝", "南图隐私政策")] {
            defaults.set(choice.rawValue, forKey: AppLanguage.storageKey)
            XCTAssertEqual(AppAccent.blue.name, title)
            XCTAssertTrue(ComplianceProfile.current.document("privacy").hasPrefix(policy))
            XCTAssertEqual(push.status, AppLocalization.string("尚未开启系统推送"))
            XCTAssertEqual(oldError.localizedDescription, AppLocalization.string("无法读取照片"))
            XCTAssertEqual(ComplianceProfile.revision, revision)
            XCTAssertEqual(ChatSticker.messageContent, wire)
        }
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let count = 1
        XCTAssertEqual(AppLocalization.string("\(count) 条新消息"), "1 new message")
        XCTAssertEqual(AppLocalization.serverError("验证码无效或已过期"), "The verification code is invalid or has expired.")
        XCTAssertEqual(AppLocalization.relocalizedUI("user-owned unknown status 原文"), "user-owned unknown status 原文")
    }

    func testLiveLanguageSwitchKeepsSettingsNavigationAndDraft() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.storageKey)
        defer { if let original { defaults.set(original, forKey: AppLanguage.storageKey) } else { defaults.removeObject(forKey: AppLanguage.storageKey) } }
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.storageKey)
        let probe = LiveLanguageProbe()
        let session = AppSession(); session.restoring = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: LiveLanguageHarness(probe: probe).environmentObject(session))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); controller.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await waitForLanguageUI { probe.editDraft != nil && probe.path == ["settings"] }
        let stateIdentity = try XCTUnwrap(probe.identity)
        probe.editDraft?("未发送的草稿 · draft %@")
        try await waitForLanguageUI { probe.draft == "未发送的草稿 · draft %@" }
        for (choice, title, accent) in [(AppLanguage.english, "Settings", "NonTo Blue"),
                                       (.traditionalChinese, "設置", "南圖藍"),
                                       (.french, "Paramètres", "Bleu NonTo"),
                                       (.russian, "Настройки", "Синий NonTo"),
                                       (.spanish, "Ajustes", "Azul NonTo"),
                                       (.japanese, "設定", "NonToブルー"),
                                       (.simplifiedChinese, "设置", "南图蓝")] {
            defaults.set(choice.rawValue, forKey: AppLanguage.storageKey)
            try await waitForLanguageUI {
                probe.accent == accent && self.views(window).compactMap { $0 as? UINavigationBar }.contains { $0.topItem?.title == title }
            }
            print("Live language \(choice.rawValue): accent=\(probe.accent), titles=\(self.views(window).compactMap { ($0 as? UINavigationBar)?.topItem?.title })")
            XCTAssertEqual(probe.path, ["settings"])
            XCTAssertEqual(probe.identity, stateIdentity, "Changing language must not replace the active screen")
            XCTAssertEqual(probe.draft, "未发送的草稿 · draft %@")
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
            attachment.name = "live-language-menu-\(choice.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testMainTabsHaveImagesWithoutVisibleTitlesAndKeepBadges() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let user: JSON = .object(["id": .id(970092), "username": .text("tabs-fixture")])
        StubProtocol.handler = { request in
            if request.url?.path.contains("unread-count") == true { return (200, .object(["unread_count": .id(3), "total_unread": .id(3)])) }
            return (200, .object(["user": user, "posts": .array([]), "blocks": .array([]), "has_more": .bool(false)]))
        }
        defer { StubProtocol.handler = nil; try? LocalCache.clear(userID: 970092) }
        let api = APIClient(baseURL: URL(string: "https://tabs.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        let session = AppSession(api: api); session.user = Person(user); session.restoring = false
        session.messageUnread = 3; session.noticeUnread = 3
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: MainTabs(initialTab: 4).environmentObject(session).environment(\.locale, AppLocalization.locale))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded(); controller.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await waitForLanguageUI { self.controllers(controller).contains { $0 is UITabBarController } }
        let tabController = try XCTUnwrap(controllers(controller).compactMap { $0 as? UITabBarController }.first)
        try await waitForLanguageUI { tabController.tabBar.items?.count == 5 }
        let items = try XCTUnwrap(tabController.tabBar.items)
        guard items.count == 5 else { XCTFail("Expected five tabs"); return }
        XCTAssertTrue(items.allSatisfy { ($0.title ?? "").isEmpty }, "Visible tab labels must be absent")
        XCTAssertTrue(items.allSatisfy { $0.image != nil })
        try await waitForLanguageUI {
            guard let current = tabController.tabBar.items, current.count == 5 else { return false }
            return current[2].badgeValue == "3" && current[3].badgeValue == "3"
        }
        let names = ["首页", "发现", "通知", "私信", "我的"].map { AppLocalization.lookup($0) }
        try await waitForLanguageUI {
            let labels = items.compactMap(\.accessibilityLabel) + self.views(tabController.tabBar).compactMap(\.accessibilityLabel)
            return names.allSatisfy { name in labels.contains { $0.localizedStandardContains(name) } }
        }
        let accessibility = items.compactMap(\.accessibilityLabel) + views(tabController.tabBar).compactMap(\.accessibilityLabel)
        print("Icon-only tab accessibility: \(accessibility)")
        for name in names { XCTAssertTrue(accessibility.contains(where: { $0.localizedStandardContains(name) }), "Missing accessible tab name: \(name)") }
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
        attachment.name = "icon-only-tabs-\(AppLocalization.language)"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func waitForLanguageUI(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "The mounted UI did not update")
    }
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }

}

@MainActor private final class LiveLanguageProbe {
    var accent = ""
    var draft = ""
    var identity: UUID?
    var path: [String] = []
    var editDraft: ((String) -> Void)?
}

private struct LiveLanguageStateView: View {
    // Read the injected locale as the real screens do, preserving the same State storage.
    @Environment(\.locale) private var appLocale
    @State private var draft = ""
    @State private var identity = UUID()
    let probe: LiveLanguageProbe
    var body: some View {
        let _ = appLocale
        let _ = record()
        TextField("消息内容", text: $draft).accessibilityIdentifier("language.test.draft")
            .onAppear { probe.editDraft = { draft = $0 } }
    }
    private func record() { probe.accent = AppAccent.blue.name; probe.draft = draft; probe.identity = identity }
}

private struct LiveLanguageHarness: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system
    @State private var path = ["settings"]
    let probe: LiveLanguageProbe
    var body: some View {
        let _ = { probe.path = path }()
        NavigationStack(path: $path) {
            Text("root").navigationDestination(for: String.self) { _ in
                VStack(spacing: 0) { SettingsView(); LiveLanguageStateView(probe: probe) }
            }
        }.environment(\.locale, appLanguage.locale())
    }
}
