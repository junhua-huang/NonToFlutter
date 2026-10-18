import XCTest
@testable import Nonto

@MainActor
final class ComplianceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        try await super.setUp()
        suite = "nonto-compliance-\(UUID())"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws {
        StubProtocol.handler = nil
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }
    func testConsentNeedsExplicitAcceptanceAndMatchingVersion() {
        let original = PrivacyConsent(defaults: defaults, revision: "version-A")
        XCTAssertFalse(original.accepted)
        original.accept()
        XCTAssertTrue(PrivacyConsent(defaults: defaults, revision: "version-A").accepted)
        XCTAssertFalse(PrivacyConsent(defaults: defaults, revision: "version-B").accepted)
        XCTAssertNotNil(defaults.object(forKey: "nonto.native.privacy-consent.date"))
    }
    func testWithdrawalRemovesConsentAndTimestamp() {
        let consent = PrivacyConsent(defaults: defaults, revision: "version-A")
        consent.accept(); consent.revoke()
        XCTAssertFalse(consent.accepted)
        XCTAssertNil(defaults.object(forKey: "nonto.native.privacy-consent.date"))
        XCTAssertFalse(PrivacyConsent(defaults: defaults, revision: "version-A").accepted)
    }
    func testSessionDoesNotRestoreOrRequestDataBeforeConsent() async throws {
        var requests = 0
        StubProtocol.handler = { _ in requests += 1; return (200, .null) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let credentials = MemoryCredentials(); credentials.value = "existing-account-token"
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: configuration), credentials: credentials)
        let consent = PrivacyConsent(defaults: defaults, revision: "new-policy")
        let session = AppSession(api: api, consent: consent)
        await session.bootstrap(); session.scene(active: true)
        do { try await session.authenticate(email: "test@example.test", password: "password", code: ""); XCTFail("Expected consent guard") } catch {}
        XCTAssertEqual(requests, 0); XCTAssertNil(api.token); XCTAssertNil(session.user)
        XCTAssertEqual(credentials.value, "existing-account-token")
    }
    func testDeletionClearsOnlyTheSpecifiedAccountsLocalData() throws {
        let userID = 900040, otherID = 9000400
        let own = ["nonto.native.draft.\(userID).0.0.v2", "nonto.native.outbox.\(userID).chat.single.3", "nonto.native.chat-draft.\(userID).chat.single.3", "nonto.native.sequence.\(userID)"]
        let other = "nonto.native.draft.\(otherID).0.0.v2"
        for key in own + [other, "nonto.native.appearance", "nonto.apns.needs-revoke"] { defaults.set("keep-or-remove", forKey: key) }
        LocalCache.write(.text("own"), userID: userID, key: "test")
        LocalCache.write(.text("other"), userID: otherID, key: "test")
        defer { try? LocalCache.clear(userID: userID); try? LocalCache.clear(userID: otherID) }
        try AccountLocalData.clear(userID: userID, defaults: defaults)
        for key in own { XCTAssertNil(defaults.object(forKey: key)) }
        XCTAssertEqual(defaults.string(forKey: other), "keep-or-remove")
        XCTAssertNotNil(defaults.object(forKey: "nonto.apns.needs-revoke"))
        XCTAssertNotNil(defaults.object(forKey: "nonto.native.appearance"))
        XCTAssertNil(LocalCache.read(userID: userID, key: "test"))
        XCTAssertEqual(LocalCache.read(userID: otherID, key: "test"), .text("other"))
    }
    func testMissingOperatorInformationIsVisibleInsteadOfFakeContact() {
        let profile = ComplianceProfile(values: [:])
        let text = profile.render("{{operatorName}}\n{{contactEmail}}")
        XCTAssertTrue(text.contains("开发测试版")); XCTAssertTrue(text.contains("待运营者补全"))
        XCTAssertFalse(text.contains("{{")); XCTAssertNil(profile.contactURL)
    }
    func testConfiguredContactsAndSecurePolicyLinks() {
        let profile = ComplianceProfile(values: ["operatorName": .text("运营者"), "contactEmail": .text("privacy@operator.test"),
                                                  "privacyPolicyURL": .text("https://operator.test/privacy"), "termsURL": .text("http://operator.test/terms"), "releaseReviewed": .bool(true)])
        XCTAssertEqual(profile.render("{{operatorName}}"), "运营者")
        XCTAssertEqual(profile.contactURL?.scheme, "mailto"); XCTAssertNotNil(profile.httpsURL("privacyPolicyURL"))
        XCTAssertNil(profile.httpsURL("termsURL"))
    }
    func testMalformedContactCannotCreateMailHeaders() {
        for value in ["javascript:alert(1)", "a@b.test?bcc=other@b.test", "a@b.test\nBcc: other@b.test"] {
            XCTAssertNil(ComplianceProfile(values: ["contactEmail": .text(value)]).contactURL)
        }
    }
    func testBundledPoliciesRenderLocallyAndRevisionCoversTheirContents() throws {
        let profile = ComplianceProfile.current
        let privacy = profile.document("privacy"), terms = profile.document("terms")
        XCTAssertTrue(privacy.contains("私信")); XCTAssertTrue(terms.contains("举报"))
        XCTAssertFalse(privacy.contains("{{")); XCTAssertFalse(terms.contains("facebookclone"))
        XCTAssertEqual(ComplianceProfile.revision.count, 64)
        XCTAssertEqual(profile.document("../../private"), "暂时无法读取说明，请稍后重试。")
    }
    func testHTTPURLCannotIncludeEvenCallerSuppliedCredentialQuery() throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, credentials: MemoryCredentials())
        let request = try api.makeRequest("/posts/", query: ["access_token": "injected-secret", "page": "2"], token: "account-secret")
        XCTAssertFalse(request.url!.absoluteString.contains("secret"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-secret")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "2")
    }
    func testPublicRequestDoesNotReceiveLoggedInAccountsHeader() async throws {
        StubProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.url!.absoluteString.contains("account-secret"))
            return (200, .object(["ok": .bool(true)]))
        }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: configuration), credentials: MemoryCredentials())
        try api.setToken("account-secret")
        _ = try await api.request("/public", authenticated: false)
    }
    func testWebSocketURLUsesSecureConnectionWithoutTokenQuery() throws {
        let url = try RealtimeClient.connectionURL(URL(string: "wss://api.example.test/ws?access_token=secret&mode=v1")!)
        XCTAssertEqual(url.absoluteString, "wss://api.example.test/ws?mode=v1")
        XCTAssertThrowsError(try RealtimeClient.connectionURL(URL(string: "ws://api.example.test/ws")!))
        XCTAssertThrowsError(try RealtimeClient.connectionURL(URL(string: "wss://user:pass@api.example.test/ws")!))
    }
}
