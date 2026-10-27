import SwiftUI
import UIKit

/// Match the theme picker: the system owns presentation, selection and dismissal.
struct AccentColorMenu: View {
    @Binding var selection: AppAccent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Picker("强调色", selection: $selection) {
            ForEach(AppAccent.allCases) { option in
                Label { Text(option.name) } icon: {
                    Image(uiImage: swatch(option)).accessibilityHidden(true)
                }.tag(option).accessibilityIdentifier("accent.option.\(option.rawValue)")
            }
        }.pickerStyle(.menu).accessibilityValue(selection.name)
            .accessibilityHint("选择应用的强调色")
            .accessibilityIdentifier("settings.accent")
            .sensoryFeedback(.selection, trigger: selection)
    }
    private func swatch(_ option: AppAccent) -> UIImage {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal)
        ])
        return (UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14)) ?? UIImage())
            .withTintColor(option.uiColor.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
    }
}

struct AccentColorOptions: View {
    @Binding var selection: AppAccent
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(AppAccent.allCases) { option in
                    Button { selection = option; dismiss() } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundStyle(selection.symbolColor)
                                .frame(width: 20).opacity(selection == option ? 1 : 0).accessibilityHidden(true)
                            Circle().fill(option.color).frame(width: swatchSize, height: swatchSize).accessibilityHidden(true)
                            Text(option.name).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.foregroundStyle(.primary).padding(.horizontal, 16).frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).hoverEffect(.highlight)
                        .accessibilityLabel(option.name).accessibilityValue(selection == option ? "已选择" : "")
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                        .accessibilityIdentifier("accent.option.\(option.rawValue)")
                }
            }.padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 256).frame(idealHeight: min(rowHeight * CGFloat(AppAccent.allCases.count) + 16, 480), maxHeight: 480)
        .accessibilityIdentifier("accent.options")
    }
}

struct AccentColorSettingsView: View {
    @AppStorage(AppAccent.storageKey) private var selection = AppAccent.blue

    var body: some View {
        Form {
            Section {
                AccentColorMenu(selection: $selection)
            } footer: {
                Text("选择后立即应用，并保存在本机。南图蓝为默认颜色。")
            }
            Section("预览") {
                AccentColorPreview(accent: selection)
            }
        }
        .navigationTitle("强调色").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccentColorPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let accent: AppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(accent.symbolColor)
                    .frame(width: 42, height: 42).background(accent.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text("南图").font(.headline)
                    Text("把今天喜欢的瞬间，留在这里。")
                    Text("#生活里的小美好").foregroundStyle(accent.textColor)
                }
            }
            footerLayout {
                Label {
                    Text(accent.name).foregroundStyle(accent.textColor)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(accent.color)
                }.font(.subheadline)
                if !dynamicType.isAccessibilitySize { Spacer(minLength: 12) }
                Button {} label: {
                    Label("发布动态", systemImage: "square.and.pencil").font(.subheadline.bold())
                }.buttonStyle(.glassProminent).tint(accent.color)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private var footerLayout: AnyLayout {
        dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}
