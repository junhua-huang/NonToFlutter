import SwiftUI

@main
@MainActor
struct NontoApp: App {
    @StateObject private var session = AppSession()
    @Environment(\.scenePhase) private var phase
    @AppStorage("nonto.native.appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            Group {
                if session.restoring { ProgressView("正在打开南图…") }
                else if let error = session.startupError {
                    ContentUnavailableView {
                        Label("暂时无法恢复登录", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { Task { await session.bootstrap() } }.buttonStyle(.glassProminent)
                        Button("重新登录") { try? session.logout() }
                    }
                } else if let user = session.user { MainTabs().id(user.id) }
                else { AuthView() }
            }
            .environmentObject(session).tint(.brand)
            .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
            .task { await session.bootstrap() }
            .onChange(of: phase) { _, value in session.scene(active: value == .active) }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: AppSession
    @State private var compose = false
    var body: some View {
        TabView {
            NavigationStack { FeedView(session: session) }
                .tabItem { Label("动态", systemImage: "house") }
            NavigationStack { ExploreView() }
                .tabItem { Label("发现", systemImage: "safari") }
            NavigationStack { MessagesView(session: session) }
                .tabItem { Label("消息", systemImage: "bubble.left.and.bubble.right") }.badge(session.messageUnread)
            NavigationStack { NotificationsView(session: session) }
                .tabItem { Label("通知", systemImage: "bell") }.badge(session.noticeUnread)
            NavigationStack { ProfileView(userID: session.user?.id ?? 0) }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $compose) { PostComposer() }
        .environment(\.openComposer, { compose = true })
        .task {
            while !Task.isCancelled {
                await session.refreshCounts()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
}
private struct ComposerKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var openComposer: () -> Void { get { self[ComposerKey.self] } set { self[ComposerKey.self] = newValue } }
}
