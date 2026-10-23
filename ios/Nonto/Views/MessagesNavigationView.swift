import SwiftUI

/// One split container owns the selection across window and orientation changes.
/// The system collapses it to a normal push navigation on narrow displays.
struct MessagesNavigationView: View {
    @ObservedObject var session: AppSession
    @StateObject private var detailNavigation = AppNavigation()
    @State private var selection: AppRoute?
    @State private var visibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var compactColumn: NavigationSplitViewColumn

    // The optional conversation is a one-time preview/screenshot seed. Runtime
    // selection stays in this container when its columns collapse or expand.
    init(session: AppSession, initialConversation: Conversation? = nil) {
        self.session = session
        _selection = State(initialValue: initialConversation.map(AppRoute.chat))
        _compactColumn = State(initialValue: initialConversation == nil ? .sidebar : .detail)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            NavigationStack {
                MessagesView(session: session, selectedRouteKey: selection?.key)
                    .accessibilityIdentifier("conversation-list")
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            .environment(\.navigate, select)
        } detail: {
            NavigationStack(path: $detailNavigation.path) {
                Group {
                    if let selection {
                        AppRouteDestination(route: selection).id(selection.key)
                    } else {
                        ContentUnavailableView("选择一个会话", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("在左侧选择好友或群聊，继续你们的对话。"))
                    }
                }
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
                .accessibilityIdentifier("conversation-detail")
            }
            .environment(\.navigate, detailNavigation.open)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func select(_ route: AppRoute) {
        guard route.isValid else { return }
        if selection != route {
            selection = route
            detailNavigation.path.removeAll()
        }
        compactColumn = .detail
    }
}
