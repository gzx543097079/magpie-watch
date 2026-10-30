import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: WatchPalette { .watch }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAGPIE 观测台")
                        .font(.custom(WatchTheme.displayCNFont, size: 20).weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(palette.ice)
                    Text("桌面数据壁纸与屏保 · 仅限本机")
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
                    section("动态壁纸") {
                        Toggle("显示动态壁纸（桌面图标下方）", isOn: $model.isWallpaperEnabled)
                        HStack {
                            Text("右侧留白（放文件夹）")
                                .foregroundStyle(palette.ice.opacity(0.8))
                            Spacer()
                            Picker("右侧留白", selection: $model.wallpaperRightInset) {
                                Text("不留").tag(0)
                                Text("120").tag(120)
                                Text("150").tag(150)
                                Text("200").tag(200)
                                Text("260").tag(260)
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            .disabled(!model.isWallpaperEnabled)
                        }
                        Text("左侧始终让开 Dock。全屏时两边留白都取消，画面顶满左右。")
                            .font(.custom(WatchTheme.bodyFont, size: 10))
                            .foregroundStyle(palette.mist)
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
                        Text("只读取本机 Magpie API，不上传数据，也不截屏。")
                            .font(.custom(WatchTheme.bodyFont, size: 10))
                            .foregroundStyle(palette.mist)
                    }

                    section("菜单栏行情") {
                        Toggle("显示指数与黄金行情", isOn: $model.marketBarEnabled)
                        marketPicker("白天 · A股", group: .aShare)
                        marketPicker("夜盘 · 美股 / A50 / 黄金", group: .night)
                        Text("白天 9:00–17:15 显示 A股一组，17:15 起到次日 9:00 显示夜盘一组，黄金两组都附带；取消勾选的品种不显示、也不请求，壁纸全屏顶栏同步。各品种只在自己开市时刷新（美股按美东时间 9:30–16:00 换算，夏令时自动），周末不显示。")
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
    }

    /// 一组品种的勾选；菜单栏和壁纸全屏顶栏同时生效。
    private func marketPicker(_ title: String, group: MarketFeed.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom(WatchTheme.bodyFont, size: 10))
                .foregroundStyle(palette.mist)
            HStack(spacing: 14) {
                ForEach(MarketFeed.options.filter { $0.group == group }, id: \.code) { option in
                    Toggle(option.label, isOn: Binding(
                        get: { !model.hiddenMarkets.contains(option.code) },
                        set: { shown in
                            if shown { model.hiddenMarkets.remove(option.code) }
                            else { model.hiddenMarkets.insert(option.code) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
        .disabled(!model.marketBarEnabled)
        .opacity(model.marketBarEnabled ? 1 : 0.45)
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


