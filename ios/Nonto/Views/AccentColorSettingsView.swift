import SwiftUI

struct AccentColorSettingsView: View {
    @AppStorage(AppAccent.storageKey) private var selection = AppAccent.blue

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 16)], spacing: 20) {
                    ForEach(AppAccent.allCases) { option in
                        Button { selection = option } label: {
                            VStack(spacing: 10) {
                                Circle().fill(option.color).frame(width: 48, height: 48)
                                    .overlay {
                                        if selection == option {
                                            Image(systemName: "checkmark").font(.title3.bold())
                                                .foregroundStyle(option.foregroundColor)
                                        }
                                    }
                                    .padding(5)
                                    .overlay { Circle().strokeBorder(selection == option ? Color.primary : .clear, lineWidth: 2) }
                                Text(option.name).font(.subheadline).foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity, minHeight: 96).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityElement(children: .ignore).accessibilityLabel(option.name)
                            .accessibilityValue(selection == option ? "已选择" : "")
                            .accessibilityAddTraits(selection == option ? .isSelected : [])
                            .accessibilityIdentifier("accent.option.\(option.rawValue)")
                    }
                }.padding(.vertical, 12)
            } footer: {
                Text("选择后立即应用，并保存在本机。南图蓝为默认颜色。")
            }
            Section("预览") {
                AccentColorPreview(accent: selection)
            }
        }
        .navigationTitle("强调色").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct AccentColorPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let accent: AppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(accent.textColor)
                    .frame(width: 42, height: 42).background(accent.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text("南图").font(.headline)
                    Text("把今天喜欢的瞬间，留在这里。")
                    Text("#生活里的小美好").foregroundStyle(accent.textColor)
                }
            }
            footerLayout {
                Label(accent.name, systemImage: "circle.fill").font(.subheadline)
                    .foregroundStyle(accent.textColor)
                if !dynamicType.isAccessibilitySize { Spacer(minLength: 12) }
                Label("发布动态", systemImage: "square.and.pencil").font(.subheadline.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(accent.foregroundColor).background(accent.color, in: Capsule())
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private var footerLayout: AnyLayout {
        dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}
