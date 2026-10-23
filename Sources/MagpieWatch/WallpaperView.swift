import SwiftUI

/// 桌面动态壁纸：常驻在桌面图标下方，半透明底色让系统壁纸隐约透出，
/// 内容复用路由动画与用量指标，整体比屏保更安静。
struct WallpaperView: View {
    @ObservedObject var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var palette: WatchPalette { model.theme.palette }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
            background
            AmbientOrbField()
            TokenRiverBackdrop(route: model.routePresentation, strength: 0.48)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 64)
                    .padding(.top, 36)

                hero
                    .padding(.horizontal, 64)
                    .padding(.top, 8)

                TokenFlowView(route: model.routePresentation, style: .ambient)
                    .frame(maxWidth: 1_280)
                    .frame(height: tokenStageHeight(proxy.size.height))
                    .padding(.horizontal, 48)
                    .padding(.top, 8)

                RouteNetworkView(route: model.routePresentation, immersive: true)
                    .frame(maxWidth: 1_360)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 70)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                footer
                    .padding(.horizontal, 64)
                    .padding(.bottom, 34)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.99)
            }
        }
        .ignoresSafeArea()
        .environment(\.watchPalette, palette)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: model.theme)
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 1.1)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wallpaperSummary)
    }

    private func tokenStageHeight(_ total: CGFloat) -> CGFloat {
        min(150, max(108, total * 0.155))
    }

    private var wallpaperSummary: String {
        let selected = model.routePresentation.candidates.first(where: \.isSelected)
        return "动态壁纸：今日 \(model.todayCalls) 次请求，当前路由到 \(selected?.providerName ?? "等待路由")"
    }

    /// 半透明深色底：压暗壁纸保证内容可读，同时保留壁纸的色彩氛围。
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.abyss.opacity(0.72),
                    palette.deep.opacity(0.60),
                    palette.abyss.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [palette.sea.opacity(0.10), .clear],
                center: UnitPoint(x: 0.30, y: 0.24),
                startRadius: 20,
                endRadius: 760
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("MAGPIE 观测台")
                    .font(.custom(WatchTheme.displayCNFont, size: 19).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.ice.opacity(0.92))
                HStack(spacing: 6) {
                    LiveDot(
                        isLive: model.isOnline,
                        color: model.isOnline ? palette.seaBright : palette.coral
                    )
                    Text(model.isOnline ? "本地网关在线" : "网关离线")
                        .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
                        .tracking(1.4)
                        .foregroundStyle(model.isOnline ? palette.seaBright.opacity(0.85) : palette.coral.opacity(0.85))
                }
            }

            Spacer()

            TimelineView(.animation(minimumInterval: 1, paused: reduceMotion)) { _ in
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.clock())
                        .font(.custom(WatchTheme.monoFont, size: 22).weight(.medium))
                        .foregroundStyle(palette.ice.opacity(0.90))
                    Text(Fmt.shortDate())
                        .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(palette.mist.opacity(0.8))
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("\(model.todayCalls)")
                .font(.custom(WatchTheme.displayFont, size: 74).weight(.medium))
                .tracking(2)
                .foregroundStyle(palette.ice.opacity(0.95))
                .contentTransition(.numericText())
                .animation(WatchMotion.data, value: model.todayCalls)

            VStack(alignment: .leading, spacing: 3) {
                Text("今日请求")
                    .font(.custom(WatchTheme.displayCNFont, size: 11).weight(.medium))
                    .tracking(1)
                    .foregroundStyle(palette.mist.opacity(0.9))
                Text("全部经由本地网关 127.0.0.1:3425")
                    .font(.custom(WatchTheme.displayCNFont, size: 11))
                    .foregroundStyle(palette.ice.opacity(0.55))
            }

            Spacer(minLength: 40)

            HStack(spacing: 30) {
                wallpaperMetric("预估费用", Fmt.currency(model.usage?.cost), tint: palette.amber.opacity(0.92))
                wallpaperMetric("缓存命中", Fmt.percent(model.cacheHitRate), tint: palette.seaBright.opacity(0.9))
                wallpaperMetric("输出令牌", Fmt.compact(model.usage?.output), tint: palette.ice.opacity(0.85))
                wallpaperMetric(
                    "错误",
                    "\(model.usage?.errors ?? 0)",
                    tint: (model.usage?.errors ?? 0) > 0 ? palette.coral.opacity(0.9) : palette.ice.opacity(0.6)
                )
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [palette.sea.opacity(0.28), Color.white.opacity(0.05), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.7)
        }
    }

    private func wallpaperMetric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 8).weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(palette.mist.opacity(0.85))
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 17).weight(.medium))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(WatchMotion.data, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            footerMetric("智能体", model.routePresentation.agentName)
            divider
            footerMetric("模型", model.routePresentation.modelName)
            divider
            footerMetric("请求", "\(model.routePresentation.requests)")
            divider
            footerMetric("延迟", model.routePresentation.latency)
            Spacer()
            Text(model.isOnline ? "实时更新" : "等待重连")
                .font(.custom(WatchTheme.bodyFont, size: 8).weight(.semibold))
                .tracking(1)
                .foregroundStyle(palette.mist.opacity(0.7))
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    private func footerMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 7).weight(.semibold))
                .tracking(1)
                .foregroundStyle(palette.mist.opacity(0.8))
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 10))
                .foregroundStyle(palette.ice.opacity(0.82))
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 0.5, height: 26)
            .padding(.horizontal, 20)
    }
}

/// 缓慢漂移的环境光晕，给壁纸底色增加纵深感；Reduce Motion 时静止。
struct AmbientOrbField: View {
    var opacity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let orbs: [(Color, Double, CGPoint, Double)] = [
                    (palette.sea, 0.05, drift(t: t, period: 47, width: width, height: height, phase: 0), width * 0.30),
                    (palette.blue, 0.04, drift(t: t, period: 61, width: width, height: height, phase: 2.1), width * 0.26),
                    (palette.violet, 0.036, drift(t: t, period: 73, width: width, height: height, phase: 4.4), width * 0.22)
                ]
                ZStack {
                    ForEach(Array(orbs.enumerated()), id: \.offset) { _, orb in
                        let (color, orbOpacity, center, radius) = orb
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(orbOpacity), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: radius
                                )
                            )
                            .frame(width: radius * 2, height: radius * 2)
                            .position(center)
                    }
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drift(
        t: TimeInterval,
        period: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        phase: Double
    ) -> CGPoint {
        let angle = (t / period) * 2 * .pi + phase
        return CGPoint(
            x: width * (0.5 + cos(angle) * 0.06 + sin(angle * 0.5) * 0.02),
            y: height * (0.42 + sin(angle) * 0.08)
        )
    }
}
