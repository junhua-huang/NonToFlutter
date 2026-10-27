import SwiftUI

extension Color {
    /// Identity and like colors stay fixed; personalized controls use appAccent.
    static let brand = AppAccent.blue.color
    static let brandLike = Color(red: 249 / 255, green: 24 / 255, blue: 128 / 255)
    static let timelineBackground = Color(uiColor: .systemBackground)
    static let timelineSeparator = Color(uiColor: .separator).opacity(0.35)
}

extension View {
    /// Glass belongs to the navigation/control layer; content keeps its native
    /// readable background. SwiftUI handles Reduce Transparency and contrast.
    func floatingGlass() -> some View {
        self.padding(.horizontal, 8).padding(.vertical, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 12).padding(.bottom, 6)
    }

    func timelineList() -> some View {
        self.listStyle(.plain).listRowSpacing(0).buttonStyle(.plain)
            .background(ScrollingNavigationBar().frame(width: 0, height: 0))
            .navigationLinkIndicatorVisibility(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.timelineBackground)
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
            .background(Color.timelineBackground)
    }

    func timelinePostRow() -> some View {
        self.listRowInsets(EdgeInsets()).listRowSeparator(.hidden).buttonStyle(.plain)
            .listRowBackground(Color.timelineBackground)
    }
}

/// Underlined content navigation stays visually separate from glass controls.
struct TimelineTabs<Selection: Hashable>: View {
    @Environment(\.appAccent) private var accent
    let title: String
    let tabs: [(value: Selection, title: String)]
    @Binding var selection: Selection

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let tab = tabs[index]
                Button { selection = tab.value } label: {
                    Text(tab.title).font(.subheadline.weight(selection == tab.value ? .bold : .medium))
                        .foregroundStyle(selection == tab.value ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 15)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .bottom) {
                            if selection == tab.value {
                                Capsule().fill(accent.color).frame(width: 32, height: 4)
                            }
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab.value ? .isSelected : [])
            }
        }.frame(maxWidth: 820).frame(maxWidth: .infinity)
            .background(Color.timelineBackground)
            .overlay(alignment: .bottom) { Color.timelineSeparator.frame(height: 0.5) }
            .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct ComposeButton: View {
    @Environment(\.appAccent) private var accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil").font(.system(size: 23, weight: .semibold))
                .frame(width: 58, height: 58)
        }.buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(accent.color).accessibilityLabel("发布动态")
            .shadow(color: accent.color.opacity(0.18), radius: 12, y: 4)
    }
}

struct TimelineActionSymbol: View {
    let symbol: String
    var count: Int = 0
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 17))
            if count > 0 {
                Text(count, format: .number.notation(.compactName)).font(.caption).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
    }
}

private struct ScrollingNavigationBar: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollChrome { ScrollChrome() }
    // Layout updates must never change toolbar visibility. UIKit owns the swipe
    // gesture and its bar animation, without feeding insets back into SwiftUI.
    func updateUIView(_ marker: ScrollChrome, context: Context) {}
    static func dismantleUIView(_ marker: ScrollChrome, coordinator: ()) {
        marker.restoreNavigationBar()
    }
}
