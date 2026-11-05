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
                                          ("en", "Hide this post", "Block this user")] {
            let bundle = try languageBundle(language)
            XCTAssertEqual(bundle.localizedString(forKey: "屏蔽此帖", value: nil, table: nil), hidden)
            XCTAssertEqual(bundle.localizedString(forKey: "屏蔽此用户", value: nil, table: nil), block)
            for key in ["NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
                let value = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
                XCTAssertNotEqual(value, key)
                XCTAssertFalse(value.isEmpty)
                if language == "en" { XCTAssertNil(value.range(of: #"\p{Han}"#, options: .regularExpression)) }
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
        for language in ["zh-Hans", "zh-Hant", "en"] {
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
        StubProtocol.handler = { _ in (200, .object(["blocked_users": .array([]), "has_more": .bool(false)])) }
        defer { StubProtocol.handler = nil }
        let api = APIClient(baseURL: URL(string: "https://localization.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        let session = AppSession(api: api); session.restoring = false
        defer { try? LocalCache.clear(userID: 970091) }
        session.user = Person(.object(["id": .id(970091), "username": .text("原文_Original"), "display_name": .text("原文 Original")]))
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
}
