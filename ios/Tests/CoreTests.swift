import XCTest
@testable import Nonto

final class CoreTests: XCTestCase {
    func json(_ text: String) throws -> JSON { try JSON.decode(Data(text.utf8)) }
    func testWireRoundTrip() throws {
        let value = try json("{\"id\":42,\"liked\":true,\"missing\":null,\"items\":[\"中文\",1]}")
        XCTAssertEqual(try JSON.decode(value.encoded()), value)
        XCTAssertEqual(value["id"].int, 42); XCTAssertTrue(value["liked"].bool)
    }
    func testStringIDsAndBareLists() throws {
        let value = try json("[{\"id\":\"23\"}]")
        XCTAssertEqual(value.list("items").first?["id"].int, 23)
    }
    func testPartialPostUpdatePreservesMediaAndOwner() throws {
        let post = Post(try json("{\"id\":1,\"user_id\":7,\"images\":[\"https://example.test/p.jpg\"],\"visibility\":\"friends\",\"content\":\"hi\"}"))
        let updated = Post(post.raw.merging(try json("{\"like_count\":4,\"is_liked\":true}")))
        XCTAssertEqual(updated.userID, 7); XCTAssertEqual(updated.images, post.images)
        XCTAssertEqual(updated.visibilityForEdit, "friends"); XCTAssertTrue(updated.liked)
    }
    func testLegacyVisibilityNeverBroadensWhenEditing() throws {
        for v in ["private", "friends_only", "unknown"] {
            XCTAssertEqual(Post(.object(["visibility": .text(v)])).visibilityForEdit, "friends")
        }
        XCTAssertEqual(Post(.object(["is_public": .bool(false)])).visibilityForEdit, "friends")
        XCTAssertEqual(Post(.object(["visibility": .text("public")])).visibilityForEdit, "public")
    }
    func testMissingEmailPermissionHidesEmail() throws {
        XCTAssertNil(Person(try json("{\"id\":1,\"email\":\"private@example.test\"}")).publicEmail)
        XCTAssertNil(Person(try json("{\"id\":1,\"show_email\":false,\"email\":\"private@example.test\"}")).publicEmail)
        XCTAssertEqual(Person(try json("{\"show_email\":true,\"email\":\"visible@example.test\"}")).publicEmail, "visible@example.test")
    }
    func testUnverifiedRolesDoNotBecomeVerifiedBadges() throws {
        let user = Person(try json("{\"roles\":[\"admin\"],\"role_labels\":[\"管理员\"],\"verified_role_labels\":[\"认证\"]}"))
        XCTAssertTrue(user.verifiedLabels.isEmpty)
    }
    func testUnavailableQuoteIsNotRenderedAsPost() throws {
        let post = Post(try json("{\"id\":1,\"quoted_post\":{\"unavailable\":true}}"))
        XCTAssertNil(post.quoted)
    }
    func testMessageHistoryDeduplicatesAndUsesServerTime() throws {
        let a = ChatMessage(try json("{\"id\":1,\"content\":\"missing date\"}"))
        let b = ChatMessage(try json("{\"id\":2,\"created_at\":\"2026-01-01T00:00:00Z\"}"))
        let replacement = ChatMessage(b.raw.merging(.object(["content": .text("updated")])))
        let list = Records.messages([b, a], [replacement])
        XCTAssertEqual(list.map(\.id), [1, 2]); XCTAssertEqual(list.last?.content, "updated"); XCTAssertNil(a.date)
    }
    func testBeijingLegacyDateAndNumericEpoch() throws {
        XCTAssertEqual(ServerDate.parse(.text("2026-01-01T08:00:00")), ServerDate.parse(.text("2026-01-01T00:00:00Z")))
        XCTAssertEqual(ServerDate.parse(.number(1_700_000_000_000)), ServerDate.parse(.number(1_700_000_000)))
        XCTAssertNil(ServerDate.parse(.null))
    }
    func testMultipartIsNotJSON() {
        let data = Multipart.encode(["content": "你好\nhello", "visibility": "friends", "image_urls": "[\"x\"]"], boundary: "test")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"content\"\r\n\r\n你好\nhello\r\n"))
        XCTAssertTrue(text.hasSuffix("--test--\r\n"))
    }
    func testStructuredModerationError() {
        let data = Data("{\"detail\":{\"code\":\"MODERATION_UNAVAILABLE\",\"message\":\"internal stack\"}}".utf8)
        let error = APIError.parse(status: 503, data: data)
        XCTAssertEqual(error.code, "MODERATION_UNAVAILABLE")
        XCTAssertEqual(error.message, "内容审核服务暂不可用，请稍后重试")
    }
    @MainActor
    func testLogoutClearsNativeNotificationAccountPreferences() {
        let notifications = NativeNotifications.shared
        notifications.userID = 900001; notifications.activeConversation = 33
        notifications.messageEnabled = true; notifications.soundEnabled = true
        notifications.clear()
        XCTAssertEqual(notifications.userID, 0); XCTAssertNil(notifications.activeConversation)
        XCTAssertFalse(notifications.messageEnabled); XCTAssertFalse(notifications.soundEnabled)
    }
}
