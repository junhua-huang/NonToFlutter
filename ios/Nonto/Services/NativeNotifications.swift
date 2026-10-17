import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class NativeNotifications: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NativeNotifications()
    @Published private(set) var authorized = false
    var activeConversation: Int?
    var userID = 0
    var messageEnabled = false
    var soundEnabled = false
    private let center = UNUserNotificationCenter.current()
    override private init() { super.init(); center.delegate = self }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }
    func requestAuthorization() async throws {
        authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func setBadge(_ count: Int) { Task { try? await center.setBadgeCount(count) } }
    func clear() {
        userID = 0; activeConversation = nil
        center.removeAllDeliveredNotifications(); center.removeAllPendingNotificationRequests(); setBadge(0)
    }
    func test() async throws {
        try await requestAuthorization()
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "南图"; content.body = "系统通知已开启"; content.sound = .default
        let request = UNNotificationRequest(identifier: "nonto.native.test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try await center.add(request)
    }
    func receive(_ payload: JSON, seq: Int) {
        guard authorized, messageEnabled, userID > 0 else { return }
        let event = payload["event"].string, data = payload["data"].or(payload)
        guard event == "new_message" || event == "new_notification" else { return }
        if event == "new_message" {
            guard data["sender_id"].int != userID,
                  data["conversation_id"].int != activeConversation else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = data["title"].string.isEmpty ? "南图" : data["title"].string
        // Avoid exposing private message content in notification previews.
        content.body = event == "new_message" ? "你收到了一条新消息" : "你有一条新通知"
        if soundEnabled { content.sound = .default }
        let request = UNNotificationRequest(identifier: "nonto.\(userID).\(seq > 0 ? String(seq) : UUID().uuidString)", content: content, trigger: nil)
        Task { try? await center.add(request) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
