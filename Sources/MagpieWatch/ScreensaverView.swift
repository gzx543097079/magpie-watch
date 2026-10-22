import SwiftUI

struct ScreensaverView: View {
    @ObservedObject var model: AppModel
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            background
            ambientOrbs
            ambientGrid

            VStack(spacing: 0) {
                screensaverHeader
                    .padding(.horizontal, 58)
                    .padding(.top, 44)

                hero
                    .padding(.horizontal, 58)
                    .padding(.top, 16)

                TokenFlowView(route: model.routePresentation)
                    .frame(maxWidth: 1_160)
                    .frame(height: 62)
                    .padding(.horizontal, 58)
                    .padding(.top, 8)

                RouteNetworkView(route: model.routePresentation, immersive: true)
                    .frame(maxWidth: 1_440)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 60)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                footer
                    .padding(.horizontal, 58)
                    .padding(.bottom, 28)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.985)

            dismissHint
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                appeared = true
            }
        }
        .onExitCommand(perform: onDismiss)
        .onTapGesture(perform: onDismiss)
        .accessibilityAddTraits(.isModal)
    }

    private var background: some View {
        ZStack {
            WatchTheme.abyss
            RadialGradient(
                colors: [
                    WatchTheme.deep.opacity(0.92),
                    WatchTheme.abyss.opacity(0.98)
                ],
                center: UnitPoint(x: 0.54, y: 0.38),
                startRadius: 10,
                endRadius: 850
            )
            RadialGradient(
                colors: [
                    WatchTheme.sea.opacity(0.085),
                    .clear
                ],
                center: UnitPoint(x: 0.72, y: 0.26),
                startRadius: 20,
                endRadius: 700
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    /// 三团缓慢漂移的光晕，像深水中的浮游生物，让静止的屏保有生命感。
    private var ambientOrbs: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let orbs: [(Color, Double, CGPoint, Double)] = [
                    (WatchTheme.sea, 0.055, drift(t: t, period: 47, width: width, height: height, phase: 0), width * 0.30),
                    (WatchTheme.blue, 0.045, drift(t: t, period: 61, width: width, height: height, phase: 2.1), width * 0.26),
                    (WatchTheme.violet, 0.040, drift(t: t, period: 73, width: width, height: height, phase: 4.4), width * 0.22)
                ]
                ZStack {
                    ForEach(Array(orbs.enumerated()), id: \.offset) { _, orb in
                        let (color, opacity, center, radius) = orb
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(opacity), .clear],
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
        .ignoresSafeArea()
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

    private var ambientGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 62
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color.white.opacity(0.018)), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Color.white.opacity(0.018)), lineWidth: 0.5)
                y += step
            }
        }
        .mask {
            RadialGradient(
                colors: [.white.opacity(0.82), .clear],
                center: .center,
                startRadius: 100,
                endRadius: 720
            )
        }
    }

    private var screensaverHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("MAGPIE 观测台")
                    .font(.custom(WatchTheme.displayCNFont, size: 23).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(WatchTheme.ice)
                Text("本地路由观测站")
                    .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
                    .tracking(2)
                    .foregroundStyle(WatchTheme.mist)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.clock())
                    .font(.custom(WatchTheme.monoFont, size: 18).weight(.medium))
                    .foregroundStyle(WatchTheme.ice)
                Text("\(Fmt.shortDate()) · \(model.isOnline ? "网关在线" : "网关离线")")
                    .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(model.isOnline ? WatchTheme.seaBright : WatchTheme.coral)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 36) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    LiveDot(
                        isLive: model.routePresentation.isLive,
                        color: model.routePresentation.isLive ? WatchTheme.seaBright : WatchTheme.amber
                    )
                    Text(model.routePresentation.isLive ? "路由传输中" : "正在观测网关")
                        .font(.custom(WatchTheme.displayCNFont, size: 10).weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(WatchTheme.seaBright.opacity(0.9))
                }

                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text("\(model.todayCalls)")
                        .font(.custom(WatchTheme.displayFont, size: 94).weight(.medium))
                        .tracking(2)
                        .foregroundStyle(WatchTheme.ice)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日请求")
                            .font(.custom(WatchTheme.displayCNFont, size: 11).weight(.medium))
                            .tracking(0.8)
                            .foregroundStyle(WatchTheme.mist)
                        Text("全部经由一个本地网关")
                            .font(.custom(WatchTheme.displayCNFont, size: 13))
                            .foregroundStyle(WatchTheme.ice.opacity(0.60))
                    }
                }
            }

            Spacer()

            HStack(spacing: 28) {
                heroMetric("预估费用", Fmt.currency(model.usage?.cost), tint: WatchTheme.amber)
                heroMetric("缓存命中", Fmt.percent(model.cacheHitRate), tint: WatchTheme.seaBright)
                heroMetric("输出令牌", Fmt.compact(model.usage?.output), tint: WatchTheme.ice)
                heroMetric("错误", "\(model.usage?.errors ?? 0)", tint: (model.usage?.errors ?? 0) > 0 ? WatchTheme.coral : WatchTheme.ice)
            }
        }
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [WatchTheme.sea.opacity(0.34), Color.white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.7)
        }
    }

    private func heroMetric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 8).weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 18).weight(.medium))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
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
            footerMetric("重路由", "\(model.routePresentation.rerouted)")
            divider
            footerMetric("延迟", model.routePresentation.latency)
            Spacer()
            Text("127.0.0.1:3425")
                .font(.custom(WatchTheme.monoFont, size: 8))
                .foregroundStyle(WatchTheme.mist.opacity(0.72))
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.065))
                .frame(height: 0.5)
        }
    }

    private func footerMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 7).weight(.semibold))
                .tracking(1)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 10))
                .foregroundStyle(WatchTheme.ice.opacity(0.88))
                .lineLimit(1)
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 22)
    }

    private var dismissHint: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "cursorarrow")
                        Text("移动鼠标或按任意键退出")
                    }
                    .font(.custom(WatchTheme.bodyFont, size: 9))
                    .foregroundStyle(WatchTheme.mist.opacity(0.72))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
    }
}
