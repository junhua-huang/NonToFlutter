import SwiftUI

/// One typed path per stack. Interactive list rows never contain competing links.
enum AppRoute: Hashable {
    case profile(Int), post(Int, initial: Post? = nil), chat(Conversation), community(Int)
    case topic(Topic), notice(Notice), communityManage(Community), comic(Int)
    case settings, personalInformation, privacySettings, notificationSettings, password
    case blockedUsers, identity, followedTopics, communities(mine: Bool = false), comics
    case policy(String), deleteAccount, reportHistory, friends

    var key: String {
        switch self {
        case .profile(let id): return "profile/\(id)"
        case .post(let id, _): return "post/\(id)"
        case .chat(let room): return room.isCommunity ? "community-chat/\(room.communityID ?? 0)" : "chat/\(room.id)"
        case .community(let id): return "community/\(id)"
        case .topic(let item): return "topic/\(item.id)"
        case .notice(let item): return "notice/\(item.id)"
        case .communityManage(let item): return "community-manage/\(item.id)"
        case .comic(let id): return "comic/\(id)"
        case .policy(let kind): return "policy/\(kind)"
        case .communities(let mine): return "communities/\(mine)"
        case .settings: return "settings"
        case .personalInformation: return "personal-information"
        case .privacySettings: return "privacy-settings"
        case .notificationSettings: return "notifications-settings"
        case .password: return "password"
        case .blockedUsers: return "blocked-users"
        case .identity: return "identity"
        case .followedTopics: return "followed-topics"
        case .comics: return "comics"
        case .deleteAccount: return "delete-account"
        case .reportHistory: return "report-history"
        case .friends: return "friends"
        }
    }
    var isValid: Bool {
        switch self {
        case .profile(let id), .post(let id, _), .community(let id), .comic(let id): return id > 0
        case .chat(let room): return room.isCommunity ? (room.communityID ?? 0) > 0 : room.id > 0
        case .topic(let value): return value.id > 0
        case .notice(let value): return value.id > 0
        case .communityManage(let value): return value.id > 0
        default: return true
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

@MainActor final class AppNavigation: ObservableObject {
    @Published var path: [AppRoute] = []
    func open(_ route: AppRoute) {
        guard route.isValid, path.last != route else { return }
        path.append(route)
    }
}
private struct NavigateKey: EnvironmentKey { static let defaultValue: (AppRoute) -> Void = { _ in } }
extension EnvironmentValues {
    var navigate: (AppRoute) -> Void {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}
struct RouteButton<Label: View>: View {
    let route: AppRoute
    let label: () -> Label
    @Environment(\.navigate) private var navigate
    init(_ route: AppRoute, @ViewBuilder label: @escaping () -> Label) { self.route = route; self.label = label }
    var body: some View {
        Button { navigate(route) } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(!route.isValid)
    }
}
struct AppNavigationStack<Root: View>: View {
    @StateObject private var navigation = AppNavigation()
    @EnvironmentObject private var session: AppSession
    let root: () -> Root
    init(@ViewBuilder root: @escaping () -> Root) { self.root = root }
    var body: some View {
        NavigationStack(path: $navigation.path) {
            root().navigationDestination(for: AppRoute.self) { route in destination(route) }
        }.environment(\.navigate, navigation.open)
    }
    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .profile(let id): ProfileView(userID: id)
        case .post(let id, let initial): PostDetailView(session: session, postID: id, initial: initial)
        case .chat(let room): ChatRoomView(conversation: room)
        case .community(let id): CommunityDetailView(communityID: id)
        case .topic(let topic): TopicDetailView(topic: topic)
        case .notice(let notice): NoticeDestination(notice: notice)
        case .communityManage(let community): CommunityManageView(community: community)
        case .comic(let id): ComicDetailView(eventID: id)
        case .settings: SettingsView()
        case .personalInformation: PersonalInformationView()
        case .privacySettings: PrivacySettingsView()
        case .notificationSettings: NotificationSettingsView()
        case .password: PasswordView()
        case .blockedUsers: BlockedUsersView(session: session)
        case .identity: IdentityCenterView()
        case .followedTopics: FollowedTopicsView(session: session)
        case .communities(let mine): CommunityListView(session: session, mine: mine)
        case .comics: ComicListView()
        case .policy(let kind): PolicyView(kind: kind)
        case .deleteAccount: DeleteAccountView()
        case .reportHistory: ReportHistoryView(session: session)
        case .friends: FriendsView(session: session)
        }
    }
}
