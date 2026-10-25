import SwiftUI

@main
@MainActor
struct NontoApp: App {
    @UIApplicationDelegateAdaptor(NontoAppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()
    @StateObject private var consent = PrivacyConsent.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage("nonto.native.appearance") private var appearance = "system"
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.blue
    var body: some Scene {
        WindowGroup {
            Group {
                if !consent.accepted { PrivacyWelcomeView() }
                else if session.restoring { ProgressView("正在打开南图…") }
                else if let error = session.startupError {
                    ContentUnavailableView {
                        Label("暂时无法恢复登录", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { Task { await session.bootstrap() } }.buttonStyle(.glassProminent)
                        Button("重新登录") { Task { try? await session.logout() } }
                    }
                } else if let user = session.user { MainTabs().id(user.id) }
                else { AuthView() }
            }
            .environmentObject(session).environmentObject(consent)
            .environment(\.appAccent, accent).tint(accent.textColor)
            .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
            .task(id: consent.accepted) { if consent.accepted { await session.bootstrap() } }
            .onChange(of: session.user?.id) { _, _ in ImageRepository.shared.clear() }
            .onChange(of: phase) { _, value in if consent.accepted { session.scene(active: value == .active) } }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: AppSession
    // The initial tab is a one-time seed, also used by deterministic previews.
    @State private var selectedTab: Int
    private let initialConversation: Conversation?
    init(initialTab: Int = 0, initialConversation: Conversation? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.initialConversation = initialConversation
    }
    @State private var compose = false
    @ObservedObject private var notifications = NativeNotifications.shared
    @State private var pushDestination: PushRoute?
    @State private var pendingPush: PushRoute?
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house", value: 0) {
                AppNavigationStack { FeedView(session: session) }
            }
            Tab("发现", systemImage: "magnifyingglass", value: 1) {
                AppNavigationStack { ExploreView() }
            }
            Tab("通知", systemImage: "bell", value: 2) {
                AppNavigationStack { NotificationsView(session: session) }
            }.badge(session.noticeUnread)
            Tab("私信", systemImage: "envelope", value: 3) {
                MessagesNavigationView(session: session, initialConversation: initialConversation)
            }.badge(session.messageUnread)
            Tab("我的", systemImage: "person.crop.circle", value: 4) {
                AppNavigationStack { ProfileView(userID: session.user?.id ?? 0) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $compose, onDismiss: {
            if let pendingPush { pushDestination = pendingPush; self.pendingPush = nil }
        }) { PostComposer() }
        .sheet(item: $pushDestination) { route in
            AppNavigationStack {
                PushDestinationView(route: route).id(route.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { pushDestination = nil } } }
            }
        }
        .onReceive(notifications.$route.compactMap { $0 }) { route in
            guard route.recipientID == session.user?.id else { return }
            if compose { pendingPush = route; compose = false }
            else { pushDestination = route }
            notifications.route = nil
        }
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
