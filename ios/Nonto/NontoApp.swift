import SwiftUI
import UIKit

@main
@MainActor
struct NontoApp: App {
    @UIApplicationDelegateAdaptor(NontoAppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system
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
                    } description: { Text(AppLocalization.relocalizedUI(error)) } actions: {
                        Button("重试") { Task { await session.bootstrap() } }.buttonStyle(.glassProminent)
                        Button("重新登录") { Task { try? await session.logout() } }
                    }
                } else if let user = session.user { MainTabs().id(user.id) }
                else { AuthView() }
            }
            .environmentObject(session).environmentObject(consent)
            .environment(\.locale, appLanguage.locale())
            .environment(\.appAccent, accent).tint(accent.color)
            .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
            .task(id: consent.accepted) { if consent.accepted { await session.bootstrap() } }
            .onChange(of: session.user?.id) { _, _ in ImageRepository.shared.clear() }
            .onChange(of: phase) { _, value in if consent.accepted { session.scene(active: value == .active) } }
        }
    }
}

struct MainTabs: View {
    @Environment(\.locale) private var appLocale
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var phase
    // The initial tab is a one-time seed, also used by deterministic previews.
    @State private var selectedTab: Int
    private let initialConversation: Conversation?
    init(initialTab: Int = 0, initialConversation: Conversation? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.initialConversation = initialConversation
    }
    @State private var postComposer = PostComposerPresentation()
    @ObservedObject private var notifications = NativeNotifications.shared
    @State private var pushDestination: PushRoute?
    @State private var pendingPush: PushRoute?
    var body: some View {
        let _ = appLocale
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                AppNavigationStack { FeedView(session: session) }
            } label: { Image(systemName: "house").accessibilityLabel(Text("首页")) }
            Tab(value: 1) {
                AppNavigationStack { ExploreView() }
            } label: { Image(systemName: "magnifyingglass").accessibilityLabel(Text("发现")) }
            Tab(value: 2) {
                AppNavigationStack { NotificationsView(session: session) }
            } label: { Image(systemName: "bell").accessibilityLabel(Text("通知")) }.badge(session.noticeUnread)
            Tab(value: 3) {
                MessagesNavigationView(session: session, initialConversation: initialConversation)
            } label: { Image(systemName: "envelope").accessibilityLabel(Text("私信")) }.badge(session.messageUnread)
            Tab(value: 4) {
                AppNavigationStack { ProfileView(userID: session.user?.id ?? 0) }
            } label: { Image(systemName: "person.crop.circle").accessibilityLabel(Text("我的")) }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(TabBarAccessibility(labels: ["首页", "发现", "通知", "私信", "我的"].map { AppLocalization.lookup($0) })
            .frame(width: 0, height: 0))
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $postComposer.destination, onDismiss: {
            if let pendingPush { pushDestination = pendingPush; self.pendingPush = nil }
        }) { destination in destination.content }
        .sheet(item: $pushDestination) { route in
            AppNavigationStack {
                PushDestinationView(route: route).id(route.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { pushDestination = nil } } }
            }
        }
        .onReceive(notifications.$route.compactMap { $0 }) { route in
            guard route.recipientID == session.user?.id else { return }
            if postComposer.destination != nil { pendingPush = route; postComposer.destination = nil }
            else { pushDestination = route }
            notifications.route = nil
        }
        .environment(\.postComposer, postComposer)
        .environment(\.openComposer, { postComposer.destination = .new })
        .task(id: session.notificationAuthorizationReady && phase == .active && postComposer.destination == nil && pushDestination == nil) {
            guard phase == .active, postComposer.destination == nil, pushDestination == nil else { return }
            await session.requestNotificationAuthorizationIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                await session.refreshCounts()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
}

/// An image-only SwiftUI Tab omits its title, including UIKit's accessibility
/// fallback. Supply names to the public tab items without adding visible text.
private struct TabBarAccessibility: UIViewControllerRepresentable {
    let labels: [String]
    func makeUIViewController(context: Context) -> TabBarAccessibilityController {
        let controller = TabBarAccessibilityController()
        controller.labels = labels
        return controller
    }
    func updateUIViewController(_ controller: TabBarAccessibilityController, context: Context) {
        controller.labels = labels
        controller.applyLabels()
        // The TabView's controller may be attached after this update.
        DispatchQueue.main.async { [weak controller] in controller?.applyLabels() }
    }
}

private final class TabBarAccessibilityController: UIViewController {
    var labels: [String] = []
    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyLabels()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLabels()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyLabels()
    }
    func applyLabels() {
        var ancestor = parent
        while let root = ancestor {
            if let tabs = findTabs(in: root), let items = tabs.tabBar.items, items.count == labels.count {
                for (item, label) in zip(items, labels) where item.accessibilityLabel != label {
                    item.accessibilityLabel = label
                }
                return
            }
            ancestor = root.parent
        }
    }
    private func findTabs(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        return controller.children.lazy.compactMap { self.findTabs(in: $0) }.first
    }
}
private struct ComposerKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var openComposer: () -> Void { get { self[ComposerKey.self] } set { self[ComposerKey.self] = newValue } }
}
