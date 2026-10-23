import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: WatchPalette { model.theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAGPIE 观测台")
                        .font(.custom(WatchTheme.displayCNFont, size: 20).weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(palette.ice)
                    Text("桌面用量与路由观测 · 仅限本机")
                        .font(.custom(WatchTheme.displayCNFont, size: 8.5).weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(palette.mist)
                }
                Spacer()
                statusPill
            }
            .padding(22)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    themeSection

                    section("小组件") {
                        Toggle("显示桌面小组件", isOn: $model.isWidgetVisible)
                        Toggle("始终置顶", isOn: $model.isPinned)
                        Toggle("鼠标穿透", isOn: $model.clickThrough)
                    }

                    section("动态壁纸") {
                        Toggle("显示动态壁纸（桌面图标下方）", isOn: $model.isWallpaperEnabled)
                        Toggle("显示喜鹊鲸桌面小宠物", isOn: $model.isPetEnabled)
                            .disabled(!model.isWallpaperEnabled)
                        Text("壁纸在所有显示器常驻显示实时路由与用量，鼠标事件会直接穿透，不影响正常使用。")
                            .font(.custom(WatchTheme.bodyFont, size: 10))
                            .foregroundStyle(palette.mist)
                    }

                    section("动态屏保") {
                        Toggle("空闲后自动进入屏保", isOn: $model.autoScreensaver)
                        HStack {
                            Text("等待时间")
                                .foregroundStyle(palette.ice.opacity(0.8))
                            Spacer()
                            Picker("等待时间", selection: $model.idleMinutes) {
                                Text("1 分钟").tag(1)
                                Text("3 分钟").tag(3)
                                Text("5 分钟").tag(5)
                                Text("10 分钟").tag(10)
                                Text("20 分钟").tag(20)
                            }
                            .labelsHidden()
                            .frame(width: 130)
                            .disabled(!model.autoScreensaver)
                        }
                    }

                    section("隐私") {
                        Toggle("默认隐藏邮箱地址", isOn: $model.maskEmails)
                        Text("小组件只读取本机 Magpie API，不上传数据，也不截屏。")
                            .font(.custom(WatchTheme.bodyFont, size: 10))
                            .foregroundStyle(palette.mist)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 440, height: 640)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow)
                palette.abyss.opacity(0.92)
                RadialGradient(
                    colors: [palette.sea.opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 360
                )
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.watchPalette, palette)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: model.theme)
    }

    private var themeSection: some View {
        section("视觉主题") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(WatchThemeID.allCases) { theme in
                    ThemeChoice(theme: theme, selected: model.theme == theme) {
                        model.theme = theme
                    }
                }
            }
            Text("小组件、动态壁纸和屏保会一起换上所选主题，并记住这个选择。缓存、输入、输出始终分成三种颜色。")
                .font(.custom(WatchTheme.bodyFont, size: 10))
                .foregroundStyle(palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.isOnline ? palette.seaBright : palette.coral)
                .frame(width: 5, height: 5)
            Text(model.isOnline ? "在线" : "离线")
                .font(.custom(WatchTheme.monoFont, size: 7))
                .foregroundStyle(model.isOnline ? palette.seaBright : palette.coral)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .panelLabel()
                .foregroundStyle(palette.seaBright.opacity(0.8))
            VStack(alignment: .leading, spacing: 11) {
                content()
            }
            .font(.custom(WatchTheme.bodyFont, size: 12))
            .foregroundStyle(palette.ice)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .watchCard(fillOpacity: 0.30, borderOpacity: 0.07)
    }
}

private struct ThemeChoice: View {
    let theme: WatchThemeID
    let selected: Bool
    let action: () -> Void

    private var palette: WatchPalette { theme.palette }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(theme.title)
                        .font(.custom(WatchTheme.displayCNFont, size: 13).weight(.semibold))
                        .foregroundStyle(palette.ice)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.seaBright)
                    }
                }
                Text(theme.detail)
                    .font(.custom(WatchTheme.bodyFont, size: 9))
                    .foregroundStyle(palette.mist)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    palette.cache
                    palette.input
                    palette.output
                }
                .frame(height: 5)
                .clipShape(Capsule())
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.deep.opacity(0.95), palette.abyss.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? palette.seaBright.opacity(0.85) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.4 : 0.7
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title)，\(theme.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
