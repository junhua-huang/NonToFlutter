import SwiftUI
import Observation

/// Capture the post at the tap, rather than rebuilding a sheet from a live row.
enum PostComposerDestination: Identifiable {
    case new, edit(Post), quote(Post)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let post): return "edit-\(post.id)"
        case .quote(let post): return "quote-\(post.id)"
        }
    }

    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .new: PostComposer()
        case .edit(let post): PostComposer(editing: post)
        case .quote(let post): PostComposer(quoted: post)
        }
    }
}

/// Owned above the scrolling lists so row refreshes cannot re-present a sheet.
@MainActor @Observable
final class PostComposerPresentation {
    var destination: PostComposerDestination?
}

extension EnvironmentValues {
    @Entry var postComposer: PostComposerPresentation? = nil
}
