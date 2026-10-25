import SwiftUI
import Foundation

enum PostText {
    private static let tokens = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_@/#])(?:#[\p{L}\p{N}_]+#?|@[\p{L}\p{N}_-]+)"#)

    static func trimmed(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func styled(_ content: String, accent: AppAccent = .blue) -> AttributedString {
        let text = trimmed(content)
        var result = AttributedString(text)
        result.foregroundColor = .primary
        for match in tokens?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
            guard let range = Range(match.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].foregroundColor = accent.textColor
        }
        return result
    }
}

enum PostThread {
    struct Item: Identifiable {
        let post: Post
        var id: Int { post.id }
    }
    static func items(from post: Post) -> [Item] {
        var result: [Item] = [], seen = Set<Int>(), next: Post? = post
        // Flatten nested wire snapshots instead of recursively nesting views.
        while let item = next, seen.insert(item.id).inserted, result.count < 20 {
            result.append(Item(post: item)); next = item.quoted
        }
        return result
    }
}

struct PostBodyText: View {
    @Environment(\.appAccent) private var accent
    let content: String
    let detailed: Bool
    let route: AppRoute?
    @State private var expanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    init(content: String, detailed: Bool = false, route: AppRoute? = nil) {
        self.content = PostText.trimmed(content); self.detailed = detailed; self.route = route
    }
    private var font: Font { detailed ? .title3 : .body }
    private var fullText: some View {
        Text(PostText.styled(content, accent: accent)).font(font).lineSpacing(detailed ? 4 : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var visibleText: some View {
        fullText.lineLimit(expanded ? nil : 6).fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if !expanded && abs(collapsedHeight - height) > 0.5 { collapsedHeight = height }
            }
            .background(alignment: .topLeading) {
                fullText.lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .hidden().accessibilityHidden(true).allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if abs(fullHeight - height) > 0.5 { fullHeight = height }
                    }
            }
    }
    var body: some View {
        Group {
            if !content.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if let route {
                        RouteButton(route) { visibleText }.accessibilityLabel("查看动态：\(content)")
                    } else { visibleText.textSelection(.enabled) }
                    if expanded || fullHeight > collapsedHeight + 1 {
                        Button(expanded ? "收起" : "显示更多") { expanded.toggle() }
                            .font(.subheadline).foregroundStyle(accent.textColor).buttonStyle(.plain)
                            .frame(minHeight: 28, alignment: .leading)
                    }
                }
            }
        }.onChange(of: content) { _, _ in expanded = false }
    }
}

enum PostMediaLayout {
    struct Item: Identifiable {
        let url: String
        let index: Int
        let occurrence: Int
        var id: String { "\(url)#\(occurrence)" }
    }
    struct Row: Identifiable {
        let items: [Item]
        var id: String { items.first?.id ?? "" }
    }
    static func items(_ images: [String]) -> [Item] {
        var occurrences: [String: Int] = [:]
        return images.enumerated().map { index, url in
            let occurrence = occurrences[url, default: 0]
            occurrences[url] = occurrence + 1
            return Item(url: url, index: index, occurrence: occurrence)
        }
    }
    static func rows(_ images: [String]) -> [Row] {
        let items = items(images)
        guard !items.isEmpty else { return [] }
        let count = (items.count + 2) / 3
        let base = items.count / count, extra = items.count % count
        var start = 0
        return (0..<count).map { row in
            let end = start + base + (row < extra ? 1 : 0)
            defer { start = end }
            return Row(items: Array(items[start..<end]))
        }
    }
    static func aspectRatio(count: Int) -> CGFloat {
        count <= 4 ? 4.0 / 3.0 : 3.0 / CGFloat((count + 2) / 3)
    }
}
