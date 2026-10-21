import Foundation
import Combine
import UserNotifications
import UIKit

@MainActor
final class NativeNotifications: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NativeNotifications()
    @Published private(set) var authorized = false
    @Published var route: PushRoute?
    var onAuthorizationChanged: (() -> Void)?
    private var deduplicator = PushDeduplicator()
    private var queuedRoute: PushRoute?
    var pushEnabled = false
    var activeConversation: Int?
    var userID = 0 {
        didSet {
            if userID > 0, let queuedRoute {
                self.queuedRoute = nil
                if queuedRoute.recipientID == userID { route = queuedRoute }
            }
        }
    }
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
        onAuthorizationChanged?()
    }
    func setBadge(_ count: Int) { Task { try? await center.setBadgeCount(count) } }
    func clear() {
        userID = 0; activeConversation = nil; messageEnabled = false; soundEnabled = false; pushEnabled = false
        route = nil; queuedRoute = nil; deduplicator = PushDeduplicator()
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
        guard authorized, pushEnabled, userID > 0 else { return }
        let event = payload["event"].string, envelope = payload["data"].or(payload)
        guard event == "new_message" || event == "new_notification" else { return }
        let chat = ChatRealtimeEvent(payload)
        let data = event == "new_message" ? chat.message.raw : envelope["notification"].or(envelope)
        if event == "new_message", data["sender_id"].int == userID { return }
        // Message notifications and message socket events share the same dedupe key.
        let messageID = event == "new_message" ? data["id"].or(data["message_id"]).int : data["message_id"].int
        let key = messageID > 0 ? "message:\(messageID)" : (data["id"].int > 0 ? "notification:\(data["id"].int)" : "event:\(seq)")
        guard deduplicator.accept(key) else { return }
        let conversationID = event == "new_message" ? chat.conversationID : data["conversation_id"].int
        if event == "new_message" && (!messageEnabled || conversationID == activeConversation) { return }
        let content = UNMutableNotificationContent()
        content.title = data["title"].string.isEmpty ? "南图" : data["title"].string
        // Avoid exposing private message content in notification previews.
        content.body = event == "new_message" ? "你收到了一条新消息" : "你有一条新通知"
        if soundEnabled { content.sound = .default }
        content.userInfo = ["recipient_id": userID, "dedupe_key": key, "message_id": messageID,
                            "notification_id": event == "new_notification" ? data["id"].int : 0,
                            "related_type": conversationID > 0 ? "conversation" : data["related_type"].string,
                            "related_id": conversationID > 0 ? conversationID : data["related_id"].int,
                            "nonto_local": true]
        let request = UNNotificationRequest(identifier: "nonto.\(userID).\(key)", content: content, trigger: nil)
        Task { try? await center.add(request) }
    }
    func open(_ payload: JSON) {
        guard let target = PushRoute(payload) else { return }
        if userID == 0 { queuedRoute = target }
        else if target.recipientID == userID { route = target }
    }
    func presentationOptions(for json: JSON) -> UNNotificationPresentationOptions {
        guard pushEnabled, userID > 0, json["recipient_id"].int == userID else { return [] }
        // Remember suppressed messages too, so a late APNs copy cannot alert after leaving the chat.
        if !json["nonto_local"].bool && !deduplicator.accept(json["dedupe_key"].string) { return [] }
        let isMessage = json["message_id"].int > 0 || json["type"].string == "message"
        if isMessage && (!messageEnabled || (json["related_type"].string == "conversation" && json["related_id"].int == activeConversation)) { return [] }
        return soundEnabled ? [.banner, .sound, .list] : [.banner, .list]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "nonto.native.test" { completionHandler([.banner, .sound, .list]); return }
        let json = PushRoute.decode(notification.request.content.userInfo)
        Task { @MainActor in
            completionHandler(json.map { self.presentationOptions(for: $0) } ?? [])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let json = PushRoute.decode(response.notification.request.content.userInfo)
        Task { @MainActor in
            if response.actionIdentifier != UNNotificationDismissActionIdentifier, let json { self.open(json) }
            completionHandler()
        }
    }
}
