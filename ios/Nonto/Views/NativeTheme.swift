import SwiftUI

extension Color {
    /// Exact brand and interaction colors from lib/config/app_theme.dart.
    static let brand = Color(red: 29 / 255, green: 155 / 255, blue: 240 / 255)
    static let brandLike = Color(red: 249 / 255, green: 24 / 255, blue: 128 / 255)
}

extension View {
    /// Glass belongs to the navigation/control layer; content keeps its native
    /// readable background. SwiftUI handles Reduce Transparency and contrast.
    func floatingGlass() -> some View {
        self.padding(10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
            .padding(.horizontal, 12).padding(.bottom, 8)
    }
}
