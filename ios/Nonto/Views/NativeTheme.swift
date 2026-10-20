import SwiftUI

extension Color {
    /// Exact brand and interaction colors from lib/config/app_theme.dart.
    static let brand = Color(red: 29 / 255, green: 155 / 255, blue: 240 / 255)
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
    }

    func timelinePostRow() -> some View {
        self.listRowInsets(EdgeInsets()).listRowSeparator(.hidden).buttonStyle(.plain)
            .listRowBackground(Color.timelineBackground)
    }
}

/// Underlined content navigation stays visually separate from glass controls.
struct TimelineTabs<Selection: Hashable>: View {
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
                                Capsule().fill(Color.brand).frame(width: 32, height: 4)
                            }
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab.value ? .isSelected : [])
            }
        }.background(Color.timelineBackground)
            .overlay(alignment: .bottom) { Color.timelineSeparator.frame(height: 0.5) }
            .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct ComposeButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil").font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white).frame(width: 58, height: 58)
                .glassEffect(.regular.tint(.brand).interactive(), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("发布动态")
            .shadow(color: Color.brand.opacity(0.18), radius: 12, y: 4)
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

private struct ScrollingNavigationBar: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ScrollChrome { ScrollChrome() }
    // Layout updates must never change toolbar visibility. UIKit owns the swipe
    // gesture and its bar animation, without feeding insets back into SwiftUI.
    func updateUIViewController(_ controller: ScrollChrome, context: Context) {}
    static func dismantleUIViewController(_ controller: ScrollChrome, coordinator: ()) {
        controller.restoreNavigationBar()
    }
}
