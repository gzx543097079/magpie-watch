import SwiftUI

/// Token 流向的呈现尺度。紧凑和面板服务小组件；
/// 环境与电影感舞台服务壁纸和屏保。
enum TokenFlowStyle {
    case compact
    case panel
    case ambient
    case cinematic
}

/// Token 流向：上行是缓存（主能量色）与输入（第二能量色）两股交织光带，
/// 下行是输出。厚度、彗星数量和流速跟随真实 token 体量与生成速度。
/// 体量为 0 的车道只保留静止虚线，不播放粒子。
struct TokenFlowView: View {
    let route: RoutePresentation
    var style: TokenFlowStyle

    init(route: RoutePresentation, compact: Bool = false, style: TokenFlowStyle? = nil) {
        self.route = route
        if let style {
            self.style = style
        } else {
            self.style = compact ? .compact : .panel
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    var body: some View {
        Group {
            switch style {
            case .compact:
                flowCanvas
                    .frame(height: 26)
            case .panel:
                VStack(spacing: 7) {
                    header
                    flowCanvas
                        .frame(height: 68)
                    legend
                }
            case .ambient, .cinematic:
                VStack(spacing: style == .cinematic ? 8 : 6) {
                    header
                    flowCanvas
                        .frame(maxHeight: .infinity)
                    legend
                }
                .padding(.horizontal, style == .cinematic ? 16 : 14)
                .padding(.vertical, style == .cinematic ? 10 : 8)
                .background { stageChrome }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        "令牌流向，\(route.tokenScopeText)。上行缓存 \(Fmt.compact(route.cacheTokens))，输入 \(Fmt.compact(route.inputTokens))，下行输出 \(Fmt.compact(route.outputTokens))"
    }

    private var flowCanvas: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                TokenFlowCanvas.drawStage(
                    context: &context,
                    size: size,
                    route: route,
                    style: style,
                    palette: palette,
                    elapsed: timeline.date.timeIntervalSinceReferenceDate,
                    motion: !reduceMotion
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("TOKEN 流向")
                .panelLabel()
                .foregroundStyle(palette.ice.opacity(0.78))
            Text(route.tokenScopeText)
                .font(.custom(WatchTheme.displayCNFont, size: style == .cinematic ? 11 : 8).weight(.medium))
                .tracking(0.4)
                .foregroundStyle(palette.violet.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
                .animation(WatchMotion.data, value: route.tokenScopeText)
            Spacer(minLength: 8)
            if route.isLive && (style == .ambient || style == .cinematic) {
                HStack(spacing: 4) {
                    LiveDot(isLive: true, color: palette.seaBright)
                    Text("传输中")
                        .font(.custom(WatchTheme.displayCNFont, size: style == .cinematic ? 11 : 9).weight(.medium))
                        .foregroundStyle(palette.seaBright.opacity(0.9))
                }
            }
            if route.tokensPerSec > 0 {
                Text("\(Int(route.tokensPerSec.rounded())) 字/秒")
                    .font(.custom(WatchTheme.monoFont, size: style == .cinematic ? 12 : 8))
                    .foregroundStyle(palette.amber.opacity(0.92))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            flowStat(symbol: "arrow.right", title: "缓存", value: Fmt.compact(route.cacheTokens), tint: palette.cache)
            flowStat(symbol: "arrow.right", title: "输入", value: Fmt.compact(route.inputTokens), tint: palette.input)
            Spacer(minLength: 6)
            flowStat(symbol: "arrow.left", title: "输出", value: Fmt.compact(route.outputTokens), tint: palette.output)
        }
    }

    private func flowStat(symbol: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: style == .cinematic ? 9 : 7, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.custom(WatchTheme.bodyFont, size: style == .cinematic ? 10 : 7.5).weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(palette.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: style == .cinematic ? 13 : 9.5).weight(.medium))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(WatchMotion.data, value: value)
        }
        .lineLimit(1)
    }

    private var stageChrome: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(palette.abyss.opacity(style == .cinematic ? 0.46 : 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                palette.seaBright.opacity(0.45),
                                Color.white.opacity(0.08),
                                palette.amber.opacity(0.40)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .shadow(color: palette.sea.opacity(style == .cinematic ? 0.18 : 0.08), radius: 22, y: 8)
    }
}

/// 铺在壁纸和屏保底层的淡色 token 河。只在对应方向有真实用量时才放行彗星。
struct TokenRiverBackdrop: View {
    let route: RoutePresentation
    var strength: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                TokenFlowCanvas.drawBackdrop(
                    context: &context,
                    size: size,
                    route: route,
                    palette: palette,
                    elapsed: timeline.date.timeIntervalSinceReferenceDate,
                    motion: !reduceMotion,
                    strength: strength
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum FlowDirection {
    case outbound
    case inbound
}

private enum TokenFlowCanvas {
    static func drawStage(
        context: inout GraphicsContext,
        size: CGSize,
        route: RoutePresentation,
        style: TokenFlowStyle,
        palette: WatchPalette,
        elapsed: TimeInterval,
        motion: Bool
    ) {
        guard size.width > 8, size.height > 8 else { return }

        if style != .compact {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(size.width, size.height) * 0.48
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius * 0.42,
                    width: radius * 2,
                    height: radius * 0.84
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        palette.violet.opacity(style == .cinematic ? 0.16 : 0.09),
                        .clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }

        let lanes = laneRects(in: size, style: style)
        let drift = motion ? elapsed * 0.33 : 0.45
        let upActive = route.cacheTokens > 0 || route.inputTokens > 0
        let braid = upActive && route.cacheTokens > 0 && route.inputTokens > 0
            ? min(braidOffset(style), lanes.up.height * 0.22)
            : 0

        if route.cacheTokens <= 0, route.inputTokens <= 0 {
            paintLane(
                context: &context,
                rect: lanes.up,
                amplitude: amplitude(style, rect: lanes.up) * 0.35,
                phase: 0.4,
                frequency: 1,
                color: palette.cache,
                thickness: 1,
                volume: 0,
                count: 0,
                direction: .outbound,
                elapsed: elapsed,
                motion: false,
                pace: 0,
                glow: 0.55
            )
        } else {
            if route.cacheTokens > 0 {
                paintLane(
                    context: &context,
                    rect: lanes.up.offsetBy(dx: 0, dy: -braid),
                    amplitude: amplitude(style, rect: lanes.up),
                    phase: drift,
                    frequency: 1.15,
                    color: palette.cache,
                    thickness: thickness(route.cacheTokens, style: style),
                    volume: route.cacheTokens,
                    count: streamCount(total: particleCount(route.cacheTokens + route.inputTokens, style: style), share: cacheShare(route), index: 0),
                    direction: .outbound,
                    elapsed: elapsed,
                    motion: motion,
                    pace: pace(route, volume: route.cacheTokens),
                    glow: 1
                )
            }
            if route.inputTokens > 0 {
                paintLane(
                    context: &context,
                    rect: lanes.up.offsetBy(dx: 0, dy: braid),
                    amplitude: amplitude(style, rect: lanes.up),
                    phase: drift + 1.75,
                    frequency: 1.35,
                    color: palette.input,
                    thickness: thickness(route.inputTokens, style: style),
                    volume: route.inputTokens,
                    count: streamCount(total: particleCount(route.cacheTokens + route.inputTokens, style: style), share: cacheShare(route), index: 1),
                    direction: .outbound,
                    elapsed: elapsed,
                    motion: motion,
                    pace: pace(route, volume: route.inputTokens),
                    glow: 1
                )
            }
        }

        paintLane(
            context: &context,
            rect: lanes.down,
            amplitude: route.outputTokens > 0 ? amplitude(style, rect: lanes.down) : amplitude(style, rect: lanes.down) * 0.35,
            phase: drift * 0.82 + 0.6,
            frequency: 1.2,
            color: palette.output,
            thickness: route.outputTokens > 0 ? thickness(route.outputTokens, style: style) : 1.0,
            volume: route.outputTokens,
            count: particleCount(route.outputTokens, style: style),
            direction: .inbound,
            elapsed: elapsed,
            motion: motion && route.outputTokens > 0,
            pace: pace(route, volume: route.outputTokens),
            glow: route.outputTokens > 0 ? 1 : 0.55
        )

        if style == .ambient || style == .cinematic {
            let radius: CGFloat = style == .cinematic ? 7 : 5.5
            let upColor = route.cacheTokens >= route.inputTokens ? palette.cache : palette.input
            portal(
                context: &context,
                at: CGPoint(x: lanes.up.minX, y: lanes.up.midY),
                color: upColor,
                radius: radius,
                intensity: upActive ? 1 : 0.28
            )
            portal(
                context: &context,
                at: CGPoint(x: lanes.up.maxX, y: lanes.up.midY),
                color: upColor,
                radius: radius * 0.72,
                intensity: upActive ? 0.45 : 0.18
            )
            portal(
                context: &context,
                at: CGPoint(x: lanes.down.maxX, y: lanes.down.midY),
                color: palette.output,
                radius: radius,
                intensity: route.outputTokens > 0 ? 1 : 0.28
            )
            portal(
                context: &context,
                at: CGPoint(x: lanes.down.minX, y: lanes.down.midY),
                color: palette.output,
                radius: radius * 0.72,
                intensity: route.outputTokens > 0 ? 0.45 : 0.18
            )
        } else {
            chevron(
                context: &context,
                at: CGPoint(x: lanes.up.maxX + 1, y: lanes.up.midY),
                color: palette.cache,
                pointingRight: true
            )
            chevron(
                context: &context,
                at: CGPoint(x: lanes.down.minX - 1, y: lanes.down.midY),
                color: palette.output,
                pointingRight: false
            )
        }

        if style == .cinematic {
            drawReflection(
                context: &context,
                lanes: lanes,
                route: route,
                palette: palette,
                elapsed: elapsed,
                drift: drift
            )
        }
    }

    static func drawBackdrop(
        context: inout GraphicsContext,
        size: CGSize,
        route: RoutePresentation,
        palette: WatchPalette,
        elapsed: TimeInterval,
        motion: Bool,
        strength: Double
    ) {
        guard size.width > 8, size.height > 8 else { return }
        let drift = motion ? elapsed * 0.18 : 0.4
        let upRect = CGRect(x: -30, y: size.height * 0.16, width: size.width + 60, height: size.height * 0.20)
        let downRect = CGRect(x: -30, y: size.height * 0.64, width: size.width + 60, height: size.height * 0.18)
        let glow = 0.55 * strength

        if route.cacheTokens > 0 {
            paintLane(
                context: &context,
                rect: upRect.offsetBy(dx: 0, dy: -size.height * 0.012),
                amplitude: min(28, upRect.height * 0.28),
                phase: drift,
                frequency: 1.05,
                color: palette.cache,
                thickness: CGFloat(10 + intensity(route.cacheTokens) * 16),
                volume: route.cacheTokens,
                count: min(5, particleCount(route.cacheTokens, style: .ambient)),
                direction: .outbound,
                elapsed: elapsed,
                motion: motion,
                pace: pace(route, volume: route.cacheTokens) * 0.55,
                glow: glow
            )
        }
        if route.inputTokens > 0 {
            paintLane(
                context: &context,
                rect: upRect.offsetBy(dx: 0, dy: size.height * 0.018),
                amplitude: min(24, upRect.height * 0.24),
                phase: drift + 1.6,
                frequency: 1.25,
                color: palette.input,
                thickness: CGFloat(8 + intensity(route.inputTokens) * 12),
                volume: route.inputTokens,
                count: min(4, particleCount(route.inputTokens, style: .ambient)),
                direction: .outbound,
                elapsed: elapsed,
                motion: motion,
                pace: pace(route, volume: route.inputTokens) * 0.5,
                glow: glow * 0.85
            )
        }
        if route.cacheTokens <= 0, route.inputTokens <= 0 {
            paintLane(
                context: &context,
                rect: upRect,
                amplitude: 10,
                phase: 0.4,
                frequency: 1,
                color: palette.cache,
                thickness: 2,
                volume: 0,
                count: 0,
                direction: .outbound,
                elapsed: elapsed,
                motion: false,
                pace: 0,
                glow: glow * 0.35
            )
        }
        paintLane(
            context: &context,
            rect: downRect,
            amplitude: route.outputTokens > 0 ? min(26, downRect.height * 0.3) : 8,
            phase: drift * 0.7 + 0.8,
            frequency: 1.1,
            color: palette.output,
            thickness: route.outputTokens > 0 ? CGFloat(9 + intensity(route.outputTokens) * 14) : 2.0,
            volume: route.outputTokens,
            count: min(5, particleCount(route.outputTokens, style: .ambient)),
            direction: .inbound,
            elapsed: elapsed,
            motion: motion && route.outputTokens > 0,
            pace: pace(route, volume: route.outputTokens) * 0.5,
            glow: route.outputTokens > 0 ? glow : glow * 0.35
        )
    }

    private static func drawReflection(
        context: inout GraphicsContext,
        lanes: (up: CGRect, down: CGRect),
        route: RoutePresentation,
        palette: WatchPalette,
        elapsed: TimeInterval,
        drift: Double
    ) {
        let shift = lanes.down.height * 0.72
        if route.cacheTokens > 0 {
            strokeRibbon(
                context: &context,
                rect: lanes.up.offsetBy(dx: 0, dy: shift),
                amplitude: amplitude(.cinematic, rect: lanes.up) * 0.65,
                phase: drift,
                frequency: 1.15,
                color: palette.cache,
                thickness: thickness(route.cacheTokens, style: .cinematic) * 0.7,
                elapsed: elapsed,
                motion: false,
                travel: 1,
                glow: 0.18,
                core: false
            )
        }
        if route.outputTokens > 0 {
            strokeRibbon(
                context: &context,
                rect: lanes.down.offsetBy(dx: 0, dy: shift * 0.45),
                amplitude: amplitude(.cinematic, rect: lanes.down) * 0.55,
                phase: drift * 0.82 + 0.6,
                frequency: 1.2,
                color: palette.output,
                thickness: thickness(route.outputTokens, style: .cinematic) * 0.65,
                elapsed: elapsed,
                motion: false,
                travel: 1,
                glow: 0.16,
                core: false
            )
        }
    }

    private static func paintLane(
        context: inout GraphicsContext,
        rect: CGRect,
        amplitude: CGFloat,
        phase: Double,
        frequency: Double,
        color: Color,
        thickness: CGFloat,
        volume: Int,
        count: Int,
        direction: FlowDirection,
        elapsed: TimeInterval,
        motion: Bool,
        pace: Double,
        glow: Double
    ) {
        if volume <= 0 {
            let path = wavePath(rect: rect, amplitude: amplitude, phase: phase, frequency: frequency, steps: 28)
            context.stroke(
                path,
                with: .color(color.opacity(0.30 * glow)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.2, 5.5])
            )
            return
        }

        strokeRibbon(
            context: &context,
            rect: rect,
            amplitude: amplitude,
            phase: phase,
            frequency: frequency,
            color: color,
            thickness: thickness,
            elapsed: elapsed,
            motion: motion,
            travel: max(pace, 0.04),
            glow: glow,
            core: true
        )

        guard motion, count > 0 else { return }
        let tail = min(8, 3 + count / 2)
        let headRadius = max(1.15, thickness * 0.34)
        for index in 0..<count {
            let seed = Double(index) * 0.618 + (direction == .outbound ? 0.17 : 0.41)
            let speedJitter = 0.82 + (seed.truncatingRemainder(dividingBy: 0.36))
            let progress = ((elapsed * pace * speedJitter) + seed)
                .truncatingRemainder(dividingBy: 1)
            drawComet(
                context: &context,
                rect: rect,
                amplitude: amplitude,
                phase: phase,
                frequency: frequency,
                progress: progress,
                direction: direction,
                color: color,
                headRadius: headRadius,
                tail: tail,
                glow: glow
            )
        }
    }

    private static func strokeRibbon(
        context: inout GraphicsContext,
        rect: CGRect,
        amplitude: CGFloat,
        phase: Double,
        frequency: Double,
        color: Color,
        thickness: CGFloat,
        elapsed: TimeInterval,
        motion: Bool,
        travel: Double,
        glow: Double,
        core: Bool
    ) {
        let path = wavePath(rect: rect, amplitude: amplitude, phase: phase, frequency: frequency, steps: 42)
        context.stroke(
            path,
            with: .color(color.opacity(0.14 * glow)),
            style: StrokeStyle(lineWidth: thickness * 3.3, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(color.opacity(0.40 * glow)),
            style: StrokeStyle(lineWidth: max(1.15, thickness), lineCap: .round, lineJoin: .round)
        )
        guard core else { return }
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.05),
                    Color.white.opacity(0.92),
                    color,
                    color.opacity(0.15)
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            ),
            style: StrokeStyle(lineWidth: max(0.8, thickness * 0.18), lineCap: .round, lineJoin: .round)
        )
        guard motion else { return }
        context.stroke(
            path,
            with: .color(Color.white.opacity(0.72 * glow)),
            style: StrokeStyle(
                lineWidth: max(0.7, thickness * 0.12),
                lineCap: .round,
                dash: [1.6, 18],
                dashPhase: -CGFloat(elapsed * 36 * travel)
            )
        )
    }

    private static func drawComet(
        context: inout GraphicsContext,
        rect: CGRect,
        amplitude: CGFloat,
        phase: Double,
        frequency: Double,
        progress: Double,
        direction: FlowDirection,
        color: Color,
        headRadius: CGFloat,
        tail: Int,
        glow: Double
    ) {
        let head = direction == .outbound ? progress : 1 - progress
        let sign: CGFloat = direction == .outbound ? -1 : 1
        for segment in stride(from: tail, through: 0, by: -1) {
            let t = CGFloat(head) + sign * CGFloat(segment) * 0.015
            guard t > 0.02, t < 0.98 else { continue }
            let point = wavePoint(rect: rect, t: t, amplitude: amplitude, phase: phase, frequency: frequency)
            let edge = sin(Double(t) * .pi)
            let falloff = 1 - CGFloat(segment) / CGFloat(tail + 1)
            let radius = headRadius * falloff
            let alpha = (0.28 + 0.72 * edge) * Double(falloff) * glow
            if segment == 0 {
                let bloom = radius * 3.1
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - bloom, y: point.y - bloom, width: bloom * 2, height: bloom * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.28 * alpha), .clear]),
                        center: point,
                        startRadius: 0,
                        endRadius: bloom
                    )
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(alpha))
            )
        }
    }

    private static func portal(
        context: inout GraphicsContext,
        at point: CGPoint,
        color: Color,
        radius: CGFloat,
        intensity: Double
    ) {
        let glow = radius * 3.3
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.50 * intensity), .clear]),
                center: point,
                startRadius: 0,
                endRadius: glow
            )
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(color.opacity(0.88 * intensity)),
            lineWidth: 1.15
        )
        let core = radius * 0.28
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
            with: .color(Color.white.opacity(0.85 * intensity))
        )
    }

    private static func chevron(
        context: inout GraphicsContext,
        at point: CGPoint,
        color: Color,
        pointingRight: Bool
    ) {
        var path = Path()
        let direction: CGFloat = pointingRight ? 1 : -1
        path.move(to: CGPoint(x: point.x + 4.5 * direction, y: point.y))
        path.addLine(to: CGPoint(x: point.x - 3 * direction, y: point.y - 3.2))
        path.addLine(to: CGPoint(x: point.x - 3 * direction, y: point.y + 3.2))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.75)))
    }

    private static func wavePath(
        rect: CGRect,
        amplitude: CGFloat,
        phase: Double,
        frequency: Double,
        steps: Int
    ) -> Path {
        var path = Path()
        guard steps > 0 else { return path }
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = wavePoint(rect: rect, t: t, amplitude: amplitude, phase: phase, frequency: frequency)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private static func wavePoint(
        rect: CGRect,
        t: CGFloat,
        amplitude: CGFloat,
        phase: Double,
        frequency: Double
    ) -> CGPoint {
        let clamped = min(1, max(0, Double(t)))
        let envelope = sin(clamped * .pi)
        let wave = sin(clamped * .pi * frequency + phase) * Double(amplitude) * envelope
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(clamped),
            y: rect.midY + CGFloat(wave)
        )
    }

    private static func laneRects(in size: CGSize, style: TokenFlowStyle) -> (up: CGRect, down: CGRect) {
        let insetX: CGFloat
        switch style {
        case .compact: insetX = 7
        case .panel: insetX = 10
        case .ambient: insetX = 22
        case .cinematic: insetX = 30
        }
        let gap: CGFloat
        switch style {
        case .compact: gap = 3
        case .panel: gap = 8
        case .ambient: gap = 10
        case .cinematic: gap = 12
        }
        let laneHeight = max(4, (size.height - gap) / 2)
        let width = max(4, size.width - insetX * 2)
        return (
            CGRect(x: insetX, y: 0, width: width, height: laneHeight),
            CGRect(x: insetX, y: laneHeight + gap, width: width, height: laneHeight)
        )
    }

    private static func amplitude(_ style: TokenFlowStyle, rect: CGRect) -> CGFloat {
        switch style {
        case .compact: return 0.7
        case .panel: return min(3.2, rect.height * 0.18)
        case .ambient: return min(9, rect.height * 0.24)
        case .cinematic: return min(13, rect.height * 0.28)
        }
    }

    private static func braidOffset(_ style: TokenFlowStyle) -> CGFloat {
        switch style {
        case .compact: return 2.1
        case .panel: return 3.6
        case .ambient: return 5.5
        case .cinematic: return 7
        }
    }

    private static func thickness(_ volume: Int, style: TokenFlowStyle) -> CGFloat {
        let span = CGFloat(intensity(volume))
        let minimum: CGFloat
        let maximum: CGFloat
        switch style {
        case .compact:
            minimum = 1.25
            maximum = 4.2
        case .panel:
            minimum = 1.8
            maximum = 7.5
        case .ambient:
            minimum = 2.2
            maximum = 11
        case .cinematic:
            minimum = 2.6
            maximum = 15
        }
        return minimum + (maximum - minimum) * span
    }

    private static func particleCount(_ volume: Int, style: TokenFlowStyle) -> Int {
        guard volume > 0 else { return 0 }
        let span = intensity(volume)
        let value: Double
        switch style {
        case .compact: value = 2 + 4 * span
        case .panel: value = 3 + 6 * span
        case .ambient: value = 4 + 8 * span
        case .cinematic: value = 5 + 11 * span
        }
        return max(1, Int(value.rounded()))
    }

    /// 把上行彗星按缓存占比分到两股光带。`index` 0 是缓存，1 是输入。
    private static func streamCount(total: Int, share: Double, index: Int) -> Int {
        guard total > 0 else { return 0 }
        let cacheCount = min(total, max(0, Int((Double(total) * share).rounded())))
        let inputCount = total - cacheCount
        if index == 0 {
            return share > 0 ? max(cacheCount, 1) : 0
        }
        if share >= 1 {
            return inputCount
        }
        return inputCount > 0 || share < 1 ? max(inputCount, share < 1 ? 1 : 0) : 0
    }

    private static func cacheShare(_ route: RoutePresentation) -> Double {
        let total = route.cacheTokens + route.inputTokens
        guard total > 0 else { return 0 }
        return Double(route.cacheTokens) / Double(total)
    }

    private static func pace(_ route: RoutePresentation, volume: Int) -> Double {
        guard volume > 0 else { return 0 }
        let body = 0.055 + 0.08 * intensity(volume)
        let rateBoost: Double
        if route.tokensPerSec > 0 {
            rateBoost = min(1.75, 1 + log10(1 + route.tokensPerSec) / 6)
        } else {
            rateBoost = 1
        }
        let liveBoost = route.isLive ? 1.08 : 1
        return body * rateBoost * liveBoost
    }

    private static func intensity(_ volume: Int) -> Double {
        min(1, log10(1 + Double(max(volume, 0))) / 7)
    }
}
