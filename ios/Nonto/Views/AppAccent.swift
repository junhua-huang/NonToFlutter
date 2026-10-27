import SwiftUI
import UIKit

/// A device-wide preference. Brand marks and semantic colors remain independent.
enum AppAccent: String, CaseIterable, Identifiable, Sendable {
    case blue, purple, pink, orange, green, yellow

    static let storageKey = "nonto.native.accent"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .blue: return "南图蓝"
        case .purple: return "紫色"
        case .pink: return "柔粉"
        case .orange: return "橙色"
        case .green: return "绿色"
        case .yellow: return "黄色"
        }
    }

    var color: Color { Color(uiColor: uiColor) }
    /// Nonto Blue keeps its approved hue in the standard appearance. Increased
    /// Contrast can adapt text and symbols separately for their backgrounds.
    var textColor: Color { Color(uiColor: textUIColor) }
    /// Use for icons and selection outlines, including Increased Contrast.
    var symbolColor: Color { Color(uiColor: palette.symbol) }
    var foregroundColor: Color { Color(uiColor: foregroundUIColor) }
    var uiColor: UIColor { palette.fill }
    var textUIColor: UIColor { palette.text }
    var symbolUIColor: UIColor { palette.symbol }
    var foregroundUIColor: UIColor { palette.foreground }

    private var palette: AccentPalette {
        switch self {
        case .blue: return Self.bluePalette
        case .purple: return Self.purplePalette
        case .pink: return Self.pinkPalette
        case .orange: return Self.orangePalette
        case .green: return Self.greenPalette
        case .yellow: return Self.yellowPalette
        }
    }

    // Cache immutable dynamic UIColors so repeated reads have stable identity.
    private static let bluePalette = AccentPalette(fill: UIColor(named: "AccentColor") ?? custom(
        light: 0x1D9BF0, dark: 0x1D9BF0, highLight: 0x0876BC, highDark: 0x6CC6FF), preservesStandardColor: true)
    private static let purplePalette = AccentPalette(fill: custom(
        light: 0x7854F6, dark: 0x7854F6, highLight: 0x5936CA, highDark: 0xAD96FF))
    private static let pinkPalette = AccentPalette(fill: custom(
        light: 0xE992B3, dark: 0xECA2C0, highLight: 0xB64B7B, highDark: 0xF3B9D2))
    private static let orangePalette = AccentPalette(fill: .systemOrange)
    private static let greenPalette = AccentPalette(fill: .systemGreen)
    private static let yellowPalette = AccentPalette(fill: .systemYellow)

    private static func custom(light: UInt32, dark: UInt32, highLight: UInt32, highDark: UInt32) -> UIColor {
        UIColor { traits in
            let darkMode = traits.userInterfaceStyle == .dark
            let hex = traits.accessibilityContrast == .high
                ? (darkMode ? highDark : highLight) : (darkMode ? dark : light)
            return AccentRGB(hex: hex).uiColor
        }
    }
}

extension EnvironmentValues {
    @Entry var appAccent: AppAccent = .blue
}

private struct AccentPalette {
    let fill: UIColor
    let text: UIColor
    let symbol: UIColor
    let foreground: UIColor

    init(fill: UIColor, preservesStandardColor: Bool = false) {
        self.fill = fill
        text = Self.legible(fill, normal: 4.5, high: 7, preservesStandardColor: preservesStandardColor)
        symbol = Self.legible(fill, normal: 3, high: 4.5, preservesStandardColor: preservesStandardColor)
        foreground = UIColor { traits in
            let base = AccentRGB(fill, traits: traits)
            return base.contrast(with: .white) >= base.contrast(with: .black) ? .white : .black
        }
    }
    private static func legible(_ fill: UIColor, normal: Double, high: Double, preservesStandardColor: Bool) -> UIColor {
        UIColor { traits in
            // A normal text/icon must not silently become a different brand
            // color from the swatch, cursor, native tint or selection fill.
            if preservesStandardColor && traits.accessibilityContrast != .high {
                return fill.resolvedColor(with: traits)
            }
            let base = AccentRGB(fill, traits: traits)
            let surfaces = [UIColor.systemBackground, .secondarySystemBackground, .tertiarySystemBackground]
                .map { AccentRGB($0, traits: traits) }
            let backgrounds = surfaces + surfaces.map { $0.mixed(with: base, amount: 0.16) }
            let minimum = traits.accessibilityContrast == .high ? high : normal
            let target: AccentRGB = traits.userInterfaceStyle == .dark ? .white : .black
            guard !backgrounds.allSatisfy({ base.contrast(with: $0) >= minimum }) else { return base.uiColor }
            var lower = 0.0, upper = 1.0
            for _ in 0..<16 {
                let middle = (lower + upper) / 2
                let candidate = base.mixed(with: target, amount: middle)
                if backgrounds.allSatisfy({ candidate.contrast(with: $0) >= minimum }) { upper = middle }
                else { lower = middle }
            }
            return base.mixed(with: target, amount: upper).uiColor
        }
    }
}

private struct AccentRGB {
    let red: Double
    let green: Double
    let blue: Double
    static let black = AccentRGB(hex: 0x000000)
    static let white = AccentRGB(hex: 0xFFFFFF)

    init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    init(_ color: UIColor, traits: UITraitCollection) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b)
    }
    private init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    var uiColor: UIColor { UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1) }
    private var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func contrast(with other: AccentRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    func mixed(with other: AccentRGB, amount: Double) -> AccentRGB {
        AccentRGB(red: red + (other.red - red) * amount,
                  green: green + (other.green - green) * amount,
                  blue: blue + (other.blue - blue) * amount)
    }
}
