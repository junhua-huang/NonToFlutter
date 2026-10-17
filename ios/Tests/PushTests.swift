import XCTest
@testable import Nonto

@MainActor
final class PushTests: XCTestCase {
    private func body(_ request: URLRequest) throws -> JSON {
        if let data = request.httpBody { return try JSON.decode(data) }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return try JSON.decode(data)
    }
    private func setup(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) throws -> (APNsService, APIClient, MemoryCredentials) {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: config), credentials: MemoryCredentials())
        try api.setToken("account-A")
        let identity = MemoryCredentials()
        let service = APNsService(identityStore: identity, defaults: UserDefaults(suiteName: "apns-test-\(UUID())")!,
                                  environment: "production", topic: "online.nonto.native", register: {}, unregister: {})
        service.attach(api: api)
        return (service, api, identity)
    }
    private func ack(_ id: Int = 1, configured: Bool = true) -> JSON {
        .object(["registered": .bool(true), "apns_supported": .bool(true), "apns_configured": .bool(configured),
                 "device": .object(["user_id": .id(id), "apns_environment": .text("production")])])
    }
    func testTokenRegistrationUsesNativeProviderAndDoesNotPersistAPNsToken() async throws {
        var requests: [JSON] = []
        let (service, _, identity) = try setup { request in requests.append(try self.body(request)); return (200, self.ack()) }
        service.setAccount(1, enabled: true); service.didRegister(Data([0, 1, 255])); await service.waitUntilIdle()
        XCTAssertTrue(service.bound); XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0]["apns_token"].string, "0001ff"); XCTAssertEqual(requests[0]["provider"].string, "apns")
        XCTAssertEqual(requests[0]["apns_environment"].string, "production")
        XCTAssertFalse(identity.value?.contains("0001ff") ?? true)
        XCTAssertTrue(requests[0]["device_id"].string.hasPrefix("apns:"))
    }
    func testTokenRotationKeepsInstallationAndUpdatesToken() async throws {
        var requests: [JSON] = []
        let (service, _, _) = try setup { request in requests.append(try self.body(request)); return (200, self.ack()) }
        service.setAccount(1, enabled: true); service.didRegister(Data([1])); await service.waitUntilIdle()
        service.didRegister(Data([2])); await service.waitUntilIdle()
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0]["device_id"], requests[1]["device_id"])
        XCTAssertEqual(requests[1]["apns_token"].string, "02")
    }
    func testDuplicateCallbackCoalescesAndPermissionOffDoesNotBind() async throws {
        var count = 0
        let (service, _, _) = try setup { _ in count += 1; return (200, self.ack()) }
        service.setAccount(1, enabled: false); service.didRegister(Data([1])); await service.waitUntilIdle(); XCTAssertEqual(count, 0)
        service.setAccount(1, enabled: true); service.didRegister(Data([1])); service.didRegister(Data([1])); await service.waitUntilIdle()
        XCTAssertEqual(count, 1)
    }
    func testLogoutRevokesUsingInstallationSecretWithoutAccountToken() async throws {
        var revoke: JSON?, revokedURL: URL?
        let (service, api, _) = try setup { request in
            if request.url!.path.hasSuffix("revoke") { revoke = try self.body(request); revokedURL = request.url; return (200, .object(["revoked": .bool(true)])) }
            return (200, self.ack())
        }
        service.setAccount(1, enabled: true); service.didRegister(Data([1])); await service.waitUntilIdle()
        try api.setToken(nil); service.setAccount(nil, enabled: false); await service.waitUntilIdle()
        XCTAssertFalse(service.bound); XCTAssertEqual(revoke?["binding_secret"].string.count, 64)
        XCTAssertFalse(revokedURL?.absoluteString.contains("access_token") ?? true)
    }
    func testLogoutWaitsForInFlightBindingThenRevokes() async throws {
        var paths: [String] = []
        let (service, _, _) = try setup { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("register") { Thread.sleep(forTimeInterval: 0.03); return (200, self.ack()) }
            return (200, .object(["revoked": .bool(true)]))
        }
        service.setAccount(1, enabled: true); service.didRegister(Data([1]))
        try await Task.sleep(for: .milliseconds(10))
        service.setAccount(nil, enabled: false); await service.waitUntilIdle()
        XCTAssertEqual(paths.map { $0.components(separatedBy: "/").last! }, ["register", "revoke"]); XCTAssertFalse(service.bound)
    }
    func testOldBackendAcknowledgementIsNotReportedAsConnected() async throws {
        let (service, _, _) = try setup { _ in (200, .object(["registered": .bool(true)])) }
        service.setAccount(1, enabled: true); service.didRegister(Data([1])); await service.waitUntilIdle()
        XCTAssertFalse(service.bound); XCTAssertNotNil(service.error)
    }
    func testMissingServerCredentialsHaveExplicitStatus() async throws {
        let (service, _, _) = try setup { _ in (200, self.ack(configured: false)) }
        service.setAccount(1, enabled: true); service.didRegister(Data([1])); await service.waitUntilIdle()
        XCTAssertTrue(service.bound); XCTAssertTrue(service.status.contains("等待服务器"))
    }
    func testPushRouteRequiresRecipientAndPreservesTarget() {
        XCTAssertNil(PushRoute(.object(["related_type": .text("conversation"), "related_id": .id(55)])))
        let route = PushRoute(.object(["recipient_id": .id(1), "related_type": .text("conversation"), "related_id": .id(55)]))
        XCTAssertEqual(route?.destination, .conversation(55)); XCTAssertEqual(route?.recipientID, 1)
    }
    func testColdStartTapWaitsForMatchingLoginAndDropsOtherAccount() {
        let notifications = NativeNotifications.shared; notifications.clear()
        let payload: JSON = .object(["recipient_id": .id(1), "notification_id": .id(10)])
        notifications.open(payload); XCTAssertNil(notifications.route)
        notifications.userID = 2; XCTAssertNil(notifications.route)
        notifications.clear(); notifications.open(payload); notifications.userID = 1
        XCTAssertEqual(notifications.route?.destination, .notification(10)); notifications.clear()
    }
    func testLocalAndRemoteEventsDeduplicateWithExpiry() {
        var dedupe = PushDeduplicator(); let date = Date()
        XCTAssertTrue(dedupe.accept("message:99", now: date)); XCTAssertFalse(dedupe.accept("message:99", now: date.addingTimeInterval(1)))
        XCTAssertTrue(dedupe.accept("notification:99", now: date.addingTimeInterval(2)))
        XCTAssertTrue(dedupe.accept("message:99", now: date.addingTimeInterval(301)))
    }
}
