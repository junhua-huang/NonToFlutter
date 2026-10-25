import XCTest
import SwiftUI
import UIKit
@testable import Nonto

@MainActor
final class AccentColorTests: XCTestCase {
    func testSelectionPersistsAndUnknownSavedValuesFallBackToBrandBlue() throws {
        let suite = "nonto-accent-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = AppStorage(wrappedValue: AppAccent.blue, AppAccent.storageKey, store: defaults)
        XCTAssertEqual(preference.wrappedValue, .blue)
        preference.wrappedValue = .purple
        XCTAssertEqual(defaults.string(forKey: AppAccent.storageKey), "purple")
        let restored = AppStorage(wrappedValue: AppAccent.blue, AppAccent.storageKey, store: defaults)
        XCTAssertEqual(restored.wrappedValue, .purple)
        defaults.set("removed-color", forKey: AppAccent.storageKey)
        let fallback = AppStorage(wrappedValue: AppAccent.blue, AppAccent.storageKey, store: defaults)
        XCTAssertEqual(fallback.wrappedValue, .blue)
    }

    func testBrandBlueAndApprovedPurpleKeepTheirNormalAppearanceValues() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = traits(style: style, contrast: .normal)
            XCTAssertEqual(hex(AppAccent.blue.uiColor, traits: traits), 0x1D9BF0)
            XCTAssertEqual(hex(AppAccent.purple.uiColor, traits: traits), 0x7854F6)
        }
    }

    func testLabelsAndSolidButtonForegroundsRemainReadableInAllAppearances() {
        for accent in AppAccent.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = traits(style: style, contrast: contrast)
                    let context = "\(accent.rawValue), \(style.rawValue), \(contrast.rawValue)"
                    let minimum: Double = contrast == .high ? 7 : 4.5
                    for background in [UIColor.systemBackground, .secondarySystemBackground, .tertiarySystemBackground] {
                        XCTAssertGreaterThanOrEqual(ratio(accent.textUIColor, background, traits: traits), minimum - 0.001, context)
                        let backdrop = components(background, traits: traits)
                        let tint = components(accent.uiColor, traits: traits)
                        let mixed = zip(backdrop, tint).map { pair in pair.0 * 0.84 + pair.1 * 0.16 }
                        let selectedSurface = UIColor(red: CGFloat(mixed[0]), green: CGFloat(mixed[1]), blue: CGFloat(mixed[2]), alpha: 1)
                        XCTAssertGreaterThanOrEqual(ratio(accent.textUIColor, selectedSurface, traits: traits), minimum - 0.001, context)
                    }
                    XCTAssertGreaterThanOrEqual(ratio(accent.foregroundUIColor, accent.uiColor, traits: traits), 4.5, context)
                }
            }
        }
    }

    func testTopicAndMentionHighlightsFollowSelectionWithoutChangingContent() {
        let source = "今天的#生活 和 @小明"
        for accent in AppAccent.allCases {
            let styled = PostText.styled(source, accent: accent)
            XCTAssertEqual(String(styled.characters), source)
            let colored = styled.runs.filter { $0.foregroundColor == accent.textColor }
                .map { String(styled[$0.range].characters) }
            XCTAssertEqual(colored, ["#生活", "@小明"])
        }
    }

    private func traits(style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast) -> UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
    }
    private func components(_ color: UIColor, traits: UITraitCollection) -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [Double(red), Double(green), Double(blue)]
    }
    private func hex(_ color: UIColor, traits: UITraitCollection) -> Int {
        let rgb = components(color, traits: traits).map { Int(($0 * 255).rounded()) }
        return rgb[0] << 16 | rgb[1] << 8 | rgb[2]
    }
    private func ratio(_ foreground: UIColor, _ background: UIColor, traits: UITraitCollection) -> Double {
        func luminance(_ color: UIColor) -> Double {
            let rgb = components(color, traits: traits).map { value in
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return zip(rgb, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
