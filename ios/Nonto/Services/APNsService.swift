import Foundation
import Combine
import UIKit
import Security

struct PushInstallation: Codable {
    let id: String
    let secret: String
    static func load(from store: CredentialStore) throws -> PushInstallation {
        if let value = try store.read(), let data = value.data(using: .utf8), let saved = try? JSONDecoder().decode(Self.self, from: data) { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError(status: 0, message: "无法创建设备推送凭据，请重试") }
        let value = Self(id: "apns:" + UUID().uuidString.lowercased(), secret: bytes.map { String(format: "%02x", $0) }.joined())
        try store.write(String(decoding: JSONEncoder().encode(value), as: UTF8.self))
        return value
    }
}

@MainActor
final class APNsService: ObservableObject {
    static let shared = APNsService()
    @Published private(set) var status = "尚未开启系统推送"
    @Published private(set) var error: String?
    @Published private(set) var bound = false
    private let identityStore: CredentialStore
    private let defaults: UserDefaults
    private let register: () -> Void
    private let unregister: () -> Void
    private let environment: String
    private let topic: String
    private var api: APIClient?
    private var installation: PushInstallation?
    private var deviceToken: String? // APNs tokens are obtained afresh; never persisted.
    private var accountID: Int?
    private var foreground = true
    private var enabled = false
    private var revision = 0
    private var tail: Task<Void, Never>?
    private var bindingKey: String?
    private var lastState: String?
    private var lastStateAt = Date.distantPast
    private let boundUserKey = "nonto.apns.bound-user"
    private let revokeKey = "nonto.apns.needs-revoke"

    init(identityStore: CredentialStore = KeychainStore(account: "push_installation"), defaults: UserDefaults = .standard,
         environment: String? = nil, topic: String? = nil,
         register: @escaping () -> Void = { UIApplication.shared.registerForRemoteNotifications() },
         unregister: @escaping () -> Void = { UIApplication.shared.unregisterForRemoteNotifications() }) {
        self.identityStore = identityStore; self.defaults = defaults
        self.environment = environment ?? (Bundle.main.object(forInfoDictionaryKey: "NontoAPNSEnvironment") as? String ?? "development")
        self.topic = topic ?? Bundle.main.bundleIdentifier ?? "online.nonto.native"
        self.register = register; self.unregister = unregister
    }
    func attach(api: APIClient) { self.api = api }
    func setAccount(_ id: Int?, enabled: Bool) {
        let id = id.flatMap { $0 > 0 ? $0 : nil }
        if accountID != id || self.enabled != enabled { revision += 1; bindingKey = nil }
        accountID = id; self.enabled = enabled
        let oldUser = defaults.integer(forKey: boundUserKey)
        if oldUser > 0 && (id != oldUser || !enabled) { defaults.set(true, forKey: revokeKey) }
        if id == nil || !enabled {
            unregister(); deviceToken = nil; bound = false
            status = id == nil ? "登录后可接收系统推送" : "系统推送已关闭"
        } else {
            status = bound ? status : "正在注册系统推送…"
            register()
        }
        schedule()
    }
    func setForeground(_ active: Bool) { foreground = active; if active { bindingKey = nil }; schedule() }
    func didRegister(_ token: Data) {
        guard !token.isEmpty else { didFail(APIError(status: 0, message: "系统未返回有效的推送令牌")); return }
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        error = nil; schedule()
    }
    func didFail(_ error: Error) { self.error = "系统推送注册失败，请检查网络并重试"; status = "系统推送未连接" }
    func retry() { error = nil; bindingKey = nil; if enabled && accountID != nil { register() }; schedule() }
    func testRemote() async throws {
        guard bound, let installation, let api else { throw APIError(status: 0, message: "请先开启系统推送并完成设备连接") }
        let result = try await api.request("/push/devices/test", method: "POST", body: .object(["device_id": .text(installation.id)]))
        guard result["submitted"].bool else { throw APIError(status: 0, message: "远程测试未提交成功，请检查服务器推送配置") }
    }
    func waitUntilIdle() async { await tail?.value }
    private func schedule() {
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            await self?.reconcile()
        }
    }
    private func reconcile() async {
        guard let api else { return }
        do {
            let identity = try installation ?? PushInstallation.load(from: identityStore)
            installation = identity
            if defaults.bool(forKey: revokeKey) {
                let result = try await api.request("/push/devices/revoke", method: "POST", body: .object([
                    "device_id": .text(identity.id), "binding_secret": .text(identity.secret)
                ]), authenticated: false)
                guard result["revoked"].bool else { throw APIError(status: 0, message: "设备解绑未确认，请重试") }
                defaults.set(false, forKey: revokeKey); defaults.removeObject(forKey: boundUserKey)
                bindingKey = nil; bound = false
            }
            guard enabled, let id = accountID, let deviceToken, api.token != nil else { return }
            let ticket = revision, epoch = api.generation
            let key = "\(id):\(epoch):\(deviceToken)"
            if key != bindingKey {
                // Record before the request so logout queues revocation even if its response is lost.
                defaults.set(id, forKey: boundUserKey)
                let result = try await api.request("/push/devices/register", method: "POST", body: .object([
                    "device_id": .text(identity.id), "platform": .text("ios"), "provider": .text("apns"),
                    "apns_token": .text(deviceToken), "apns_environment": .text(environment), "apns_topic": .text(topic),
                    "binding_secret": .text(identity.secret), "app_state": .text(foreground ? "foreground" : "background"),
                    "manufacturer": .text("Apple"), "model": .text(UIDevice.current.model),
                    "app_version": .text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                ]))
                guard ticket == revision, epoch == api.generation else { return }
                guard result["registered"].bool, result["apns_supported"].bool,
                      result["device"]["user_id"].int == id,
                      result["device"]["apns_environment"].string == environment else { throw APIError(status: 0, message: "服务器尚未支持此版本的系统推送") }
                bound = true; error = nil
                let configured = result["apns_configured"].bool
                bindingKey = key
                status = configured ? "系统推送已连接" : "设备已绑定，等待服务器启用推送"
                lastState = foreground ? "foreground" : "background"; lastStateAt = Date()
            } else {
                let state = foreground ? "foreground" : "background"
                if state != lastState || Date().timeIntervalSince(lastStateAt) > 60 {
                    _ = try await api.request("/push/devices/state", method: "POST", body: .object([
                        "device_id": .text(identity.id), "provider": .text("apns"), "app_state": .text(state)
                    ]))
                    guard epoch == api.generation, ticket == revision else { return }
                    lastState = state; lastStateAt = Date()
                }
            }
        } catch {
            self.error = error.localizedDescription
            if enabled && accountID != nil { status = "系统推送暂未连接" }
        }
    }
}

final class NontoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = NativeNotifications.shared
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { APNsService.shared.didRegister(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { APNsService.shared.didFail(error) }
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Give a lifecycle update a bounded opportunity to reach the server.
        var task: UIBackgroundTaskIdentifier = .invalid
        task = application.beginBackgroundTask(withName: "Push device state") { if task != .invalid { application.endBackgroundTask(task); task = .invalid } }
        APNsService.shared.setForeground(false)
        Task { await APNsService.shared.waitUntilIdle(); if task != .invalid { application.endBackgroundTask(task); task = .invalid } }
    }
}
