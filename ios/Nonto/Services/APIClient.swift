import Foundation
import Combine
import Security

struct APIError: LocalizedError, Equatable {
    var status: Int
    var message: String
    var code: String = ""
    var errorDescription: String? { message }
    static let sessionChanged = APIError(status: 0, message: "登录状态已变化，请重试")
    static func parse(status: Int, data: Data) -> APIError {
        let j = (try? JSON.decode(data)) ?? .null
        let detail = j["detail"]
        let code = detail["code"].string
        let text = detail["message"].or(detail.array.first?["msg"] ?? .null).or(j["message"]).string
        var message = text.isEmpty ? detail.string : text
        switch code {
        case "CONTENT_REJECTED": message = "内容未通过审核"
        case "MODERATION_UNAVAILABLE": message = "内容审核服务暂不可用，请稍后重试"
        case "ACCOUNT_DISABLED": message = "账号已停用"
        default:
            if message.isEmpty || ["traceback", "exception", "stack trace", "threshold", "regex"].contains(where: { message.lowercased().contains($0) }) {
                message = status == 401 ? "登录已过期，请重新登录" : "请求失败（\(status)），请稍后重试"
            }
        }
        return APIError(status: status, message: message, code: code)
    }
}

protocol CredentialStore {
    func read() throws -> String?
    func write(_ token: String?) throws
}
struct KeychainStore: CredentialStore {
    private let account: String
    init(account: String = "access_token") { self.account = account }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "online.nonto.native.session",
         kSecAttrAccount as String: account]
    }
    func read() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return String(data: data, encoding: .utf8)
    }
    func write(_ token: String?) throws {
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }; return
        }
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(values) { _, v in v } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw keychainError(status) }
    }
    private func keychainError(_ status: OSStatus) -> APIError {
        APIError(status: Int(status), message: "无法访问安全存储，请解锁设备后重试")
    }
}

/// Never let a redirect forward a query credential or upload body to another origin.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              original.scheme == target.scheme, original.host == target.host,
              original.port == target.port, original.path.hasPrefix("/api/"), target.path.hasPrefix("/api/") else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

@MainActor
final class APIClient: ObservableObject {
    let baseURL: URL
    let socketURL: URL
    private let session: URLSession
    private let credentials: CredentialStore
    private(set) var token: String?
    private(set) var generation = UUID()
    private var refreshTask: Task<String, Error>?
    var onSessionExpired: (() -> Void)?
    var onTokenRefreshed: (() -> Void)?

    init(baseURL: URL = URL(string: "https://www.nonto.online/api")!,
         socketURL: URL = URL(string: "wss://www.nonto.online/ws")!,
         session: URLSession? = nil, credentials: CredentialStore = KeychainStore()) {
        self.baseURL = baseURL; self.socketURL = socketURL; self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 300
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        self.session = session ?? URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }
    func restore() throws { token = try credentials.read() }
    func setToken(_ value: String?) throws {
        try credentials.write(value)
        refreshTask?.cancel(); refreshTask = nil; generation = UUID(); token = value
    }
    func request(_ path: String, method: String = "GET", query: [String: String] = [:],
                 body: JSON? = nil, form: [String: String]? = nil, authenticated: Bool = true) async throws -> JSON {
        let epoch = generation, usedToken = authenticated ? token : nil
        var result = try await perform(path, method: method, query: query, body: body, form: form, token: usedToken)
        guard generation == epoch else { throw APIError.sessionChanged }
        if result.status == 401, authenticated, usedToken != nil, path != "/auth/refresh" {
            // Another concurrent request may already have refreshed the same session.
            let next: String
            if let current = token, current != usedToken { next = current }
            else { next = try await refresh(expectedGeneration: epoch) }
            guard generation == epoch else { throw APIError.sessionChanged }
            result = try await perform(path, method: method, query: query, body: body, form: form, token: next)
        }
        guard generation == epoch else { throw APIError.sessionChanged }
        if !(200..<300).contains(result.status) {
            let error = APIError.parse(status: result.status, data: result.data)
            if authenticated && (result.status == 401 || error.code == "ACCOUNT_DISABLED") { expire(epoch) }
            throw error
        }
        if result.data.isEmpty { return .null }
        guard let json = try? JSON.decode(result.data) else { throw APIError(status: result.status, message: "服务器返回了无法识别的数据") }
        return json
    }
    private func refresh(expectedGeneration epoch: UUID) async throws -> String {
        if let task = refreshTask { return try await task.value }
        let old = token
        let task = Task<String, Error> { @MainActor [self] in
            let result = try await perform("/auth/refresh", method: "POST", query: [:], body: nil, form: nil, token: old)
            guard generation == epoch else { throw APIError.sessionChanged }
            guard (200..<300).contains(result.status) else {
                if result.status == 401 || result.status == 403 { expire(epoch) }
                throw APIError.parse(status: result.status, data: result.data)
            }
            let json = try JSON.decode(result.data), next = json["access_token"].string
            guard !next.isEmpty else { throw APIError(status: 502, message: "登录续期失败，请重新登录") }
            try credentials.write(next); token = next; onTokenRefreshed?()
            return next
        }
        refreshTask = task
        defer { if generation == epoch { refreshTask = nil } }
        return try await task.value
    }
    private func expire(_ epoch: UUID) {
        guard generation == epoch else { return }
        try? credentials.write(nil); token = nil; generation = UUID(); refreshTask = nil
        onSessionExpired?()
    }
    private func perform(_ path: String, method: String, query: [String: String], body: JSON?,
                         form: [String: String]?, token: String?) async throws -> (status: Int, data: Data) {
        var request = try makeRequest(path, method: method, query: query, token: token)
        if let form {
            let boundary = "Nonto-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = Multipart.encode(form, boundary: boundary)
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try body.encoded()
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (response.statusCode, data)
    }
    func makeRequest(_ path: String, method: String = "GET", query: [String: String] = [:], token: String?) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains("?"), !path.contains("#"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.path = baseURL.path + path
        var params = query
        if let token { params["access_token"] = token }
        components.queryItems = params.keys.sorted().map { URLQueryItem(name: $0, value: params[$0]) }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    func upload(_ data: Data, filename: String, mime: String, type: String = "post") async throws -> String {
        guard data.count <= 50 * 1024 * 1024 else { throw APIError(status: 0, message: "文件不能超过 50 MB") }
        let epoch = generation
        let presign = try await request("/upload/presign", method: "POST", body: .object([
            "filename": .text(filename), "file_type": .text((filename as NSString).pathExtension), "upload_type": .text(type)]))
        let link = presign["upload_url"].or(presign["presigned_url"]).or(presign["url"]).string
        guard let url = URL(string: link), url.scheme == "https", url.host != nil else {
            throw APIError(status: 0, message: "上传地址不可用")
        }
        // A new request contains only COS's signed URL and content type; no Nonto credentials.
        var put = URLRequest(url: url); put.httpMethod = "PUT"; put.httpBody = data
        put.setValue(mime, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: put)
        guard generation == epoch else { throw APIError.sessionChanged }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(status: 0, message: "文件上传失败，请重试")
        }
        var publicURL = presign["public_url"].string
        if !presign["cos_key"].string.isEmpty {
            let confirm = try await request("/upload/confirm", method: "POST", body: .object([
                "cos_key": presign["cos_key"], "final_filename": .text(filename)]))
            if !confirm["url"].string.isEmpty { publicURL = confirm["url"].string }
        }
        if publicURL.isEmpty { var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!; c.query = nil; publicURL = c.url!.absoluteString }
        if type == "avatar" || type == "cover" {
            _ = try await request("/upload/\(type)/confirm", method: "POST", body: .object(["url": .text(publicURL)]))
        }
        return publicURL
    }
}

enum Multipart {
    static func encode(_ fields: [String: String], boundary: String) -> Data {
        var value = ""
        for key in fields.keys.sorted() {
            let safeKey = key.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            value += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(safeKey)\"\r\n\r\n\(fields[key]!)\r\n"
        }
        value += "--\(boundary)--\r\n"; return Data(value.utf8)
    }
}
