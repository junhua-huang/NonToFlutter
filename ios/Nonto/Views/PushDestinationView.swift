import SwiftUI

struct PushDestinationView: View {
    let route: PushRoute
    @EnvironmentObject private var session: AppSession
    @State private var conversation: Conversation?
    @State private var notice: Notice?
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if route.recipientID != session.user?.id {
                ContentUnavailableView("此通知属于其他账号", systemImage: "person.crop.circle.badge.exclamationmark")
            } else {
                switch route.destination {
                case .conversation:
                    if let conversation { ChatRoomView(conversation: conversation) }
                    else if let error { ContentUnavailableView { Label("暂时无法打开会话", systemImage: "bubble.left") } description: { Text(error) } actions: { Button("重试") { attempt += 1 }.buttonStyle(.glass) } }
                    else { ProgressView("正在打开会话…") }
                case .community(let id): CommunityDetailView(communityID: id)
                case .post(let id): PostDetailView(session: session, postID: id)
                case .notification:
                    if let notice { NoticeDestination(notice: notice) }
                    else if let error { ErrorBanner(text: error) { attempt += 1 } }
                    else { ProgressView("正在打开通知…") }
                case .inbox: NotificationsView(session: session)
                }
            }
        }.task(id: attempt) {
            guard route.recipientID == session.user?.id else { return }
            let epoch = session.api.generation
            if case .conversation(let id) = route.destination {
                do {
                    // This read-only endpoint applies current membership and block checks.
                    let value = try await ConversationLookup.find(id, api: session.api)
                    guard epoch == session.api.generation else { return }
                    conversation = value; error = nil
                } catch { if epoch == session.api.generation { self.error = error.localizedDescription } }
            }
            if case .notification(let id) = route.destination {
                do {
                    let json = try await session.api.request("/notifications/\(id)")
                    guard epoch == session.api.generation else { return }
                    notice = Notice(json["notification"].or(json)); error = nil
                } catch { if epoch == session.api.generation { self.error = error.localizedDescription } }
            } else if route.payload["notification_id"].int > 0 {
                _ = try? await session.api.request("/notifications/\(route.payload["notification_id"].int)/read", method: "POST")
            }
            await session.refreshCounts()
        }
    }
}
