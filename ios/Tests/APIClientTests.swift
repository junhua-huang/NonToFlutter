import XCTest
@testable import Nonto

final class MemoryCredentials: CredentialStore {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String?) throws { value = token }
}
final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, JSON))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, json) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try json.encoded()); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class APIClientTests: XCTestCase {
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, JSON)) -> (APIClient, MemoryCredentials) {
        StubProtocol.handler = handler
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]
        let credentials = MemoryCredentials()
        let api = APIClient(baseURL: URL(string: "https://api.example.test/api")!, session: URLSession(configuration: c), credentials: credentials)
        return (api, credentials)
    }
    func testBearerTokenPreservesPaginationAndFilters() throws {
        let (api, _) = client { _ in (200, .null) }
        let request = try api.makeRequest("/search/posts", query: ["q": "a & 中文", "page": "3"], token: "secret")
        let values = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(values.first { $0.name == "q" }?.value, "a & 中文")
        XCTAssertEqual(values.first { $0.name == "page" }?.value, "3")
        XCTAssertNil(values.first { $0.name == "access_token" })
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }
    func testAbsolutePathsAndTraversalAreRejected() throws {
        let (api, _) = client { _ in (200, .null) }
        XCTAssertThrowsError(try api.makeRequest("https://other.test/api", token: "secret"))
        XCTAssertThrowsError(try api.makeRequest("/../outside", token: "secret"))
    }
    func testRefreshRetriesWithSameSearchQuery() async throws {
        var calls = 0
        let (api, store) = client { request in
            if request.url!.path == "/api/auth/refresh" { return (200, .object(["access_token": .text("new")])) }
            calls += 1
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(q.first { $0.name == "page" }?.value, "4")
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer old" ? (401, .null) : (200, .object(["ok": .bool(true)]))
        }
        try api.setToken("old")
        let result = try await api.request("/posts/", query: ["page": "4"])
        XCTAssertTrue(result["ok"].bool); XCTAssertEqual(store.value, "new"); XCTAssertEqual(calls, 2)
    }
    func testRefreshRejectionExpiresSessionOnce() async throws {
        var expired = 0
        let (api, store) = client { _ in (401, .null) }
        try api.setToken("old"); api.onSessionExpired = { expired += 1 }
        do { _ = try await api.request("/posts/"); XCTFail("Expected an error") } catch {}
        XCTAssertNil(api.token); XCTAssertNil(store.value); XCTAssertEqual(expired, 1)
    }
    func testConcurrentUnauthorizedRequestsShareRefresh() async throws {
        let lock = NSLock()
        var refreshes = 0
        let (api, _) = client { request in
            if request.url!.path == "/api/auth/refresh" {
                lock.lock(); refreshes += 1; lock.unlock()
                return (200, .object(["access_token": .text("new")]))
            }
            XCTAssertFalse(request.url!.absoluteString.contains("access_token"))
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer old" ? (401, .null) : (200, .object(["ok": .bool(true)]))
        }
        try api.setToken("old")
        async let first = api.request("/posts/")
        async let second = api.request("/notifications/")
        let (a, b) = try await (first, second)
        XCTAssertTrue(a["ok"].bool); XCTAssertTrue(b["ok"].bool); XCTAssertEqual(refreshes, 1)
    }
    func testNetworkFailureDoesNotDeleteCredentials() async throws {
        let (api, store) = client { _ in throw URLError(.notConnectedToInternet) }
        try api.setToken("valid")
        do { _ = try await api.request("/auth/profile"); XCTFail("Expected an error") } catch {}
        XCTAssertEqual(store.value, "valid"); XCTAssertEqual(api.token, "valid")
    }
    func testLoginDoesNotRefresh401() async throws {
        var count = 0
        let (api, _) = client { request in count += 1; XCTAssertEqual(request.url?.path, "/api/auth/login"); return (401, .null) }
        do { _ = try await api.request("/auth/login", method: "POST", authenticated: false); XCTFail("Expected an error") } catch {}
        XCTAssertEqual(count, 1)
    }
    func testUploadDoesNotSendAppCredentialsToCOS() async throws {
        var uploaded = false
        let (api, _) = client { request in
            if request.url?.host == "cos.example.test" {
                uploaded = true; XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertFalse(request.url!.absoluteString.contains("app-secret")); XCTAssertEqual(request.httpMethod, "PUT")
                return (200, .null)
            }
            if request.url!.path.hasSuffix("presign") { return (200, .object(["upload_url": .text("https://cos.example.test/p.jpg?signature=cos-secret"), "cos_key": .text("p.jpg"), "public_url": .text("https://cos.example.test/p.jpg")])) }
            return (200, .object(["url": .text("https://cos.example.test/p.jpg")]))
        }
        try api.setToken("app-secret")
        let url = try await api.upload(Data([1, 2, 3]), filename: "p.jpg", mime: "image/jpeg")
        XCTAssertTrue(uploaded); XCTAssertEqual(url, "https://cos.example.test/p.jpg")
    }
    func testFailedUploadConfirmationIsNotSuccess() async throws {
        let (api, _) = client { request in
            if request.url!.path.hasSuffix("presign") { return (200, .object(["upload_url": .text("https://cos.example.test/p.jpg"), "cos_key": .text("p.jpg")])) }
            if request.url?.host == "cos.example.test" { return (200, .null) }
            return (503, .object(["detail": .object(["code": .text("MODERATION_UNAVAILABLE")])]))
        }
        try api.setToken("secret")
        do { _ = try await api.upload(Data([1]), filename: "p.jpg", mime: "image/jpeg"); XCTFail("Must not publish an unconfirmed upload") }
        catch let error as APIError { XCTAssertEqual(error.code, "MODERATION_UNAVAILABLE") }
    }
    func testCacheIsScopedByUser() throws {
        let key = "isolation-test-\(UUID())"
        LocalCache.write(.array([.text("account A")]), userID: 900001, key: key)
        XCTAssertEqual(LocalCache.read(userID: 900001, key: key)?.array, [.text("account A")])
        XCTAssertNil(LocalCache.read(userID: 900002, key: key))
        try LocalCache.clear(userID: 900001); try LocalCache.clear(userID: 900002)
    }
}
