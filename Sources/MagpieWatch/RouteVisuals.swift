import SwiftUI

struct RouteNetworkView: View {
    let route: RoutePresentation
    var compact = false
    var immersive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var nodeScale: CGFloat { compact ? 0.78 : 1 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let leftX = compact ? size.width * 0.14 : size.width * (immersive ? 0.14 : 0.18)
            let centerX = size.width * 0.50
            let rightX = compact ? size.width * 0.84 : size.width * (immersive ? 0.84 : 0.81)
            let centerY = size.height * (compact ? 0.48 : 0.45)
            let candidates = visibleCandidates
            let candidateY = candidateYPositions(
                in: size,
                count: candidates.count,
                compact: compact
            )

            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                Canvas { context, canvasSize in
                    drawBackdrop(
                        in: &context,
                        size: canvasSize,
                        left: CGPoint(x: leftX, y: centerY),
                        hub: CGPoint(x: centerX, y: centerY),
                        candidates: candidateY,
                        candidateModels: candidates,
                        rightX: rightX,
                        elapsed: elapsed,
                        immersive: immersive
                    )
                }
                .opacity(reduceMotion ? 0.82 : 1)

                routeNodes(
                    size: size,
                    leftX: leftX,
                    centerX: centerX,
                    rightX: rightX,
                    centerY: centerY,
                    candidateY: candidateY,
                    candidates: candidates
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let selected = route.candidates.first(where: \.isSelected)
        return "\(route.agentName) 经 Magpie 网关路由到 \(selected?.providerName ?? "等待路由")"
    }

    private var visibleCandidates: [RouteCandidateView] {
        if compact {
            return route.candidates.first(where: \.isSelected).map { [$0] }
                ?? Array(route.candidates.prefix(1))
        }
        if immersive {
            return Array(route.candidates.prefix(4))
        }
        return Array(route.candidates.prefix(3))
    }

    private func candidateYPositions(in size: CGSize, count: Int, compact: Bool) -> [CGFloat] {
        if count == 1 {
            return [size.height * 0.48]
        }
        let topRatio: CGFloat
        let bottomRatio: CGFloat
        switch count {
        case 2:
            topRatio = 0.25
            bottomRatio = 0.75
        case 3:
            topRatio = 0.16
            bottomRatio = 0.84
        default:
            topRatio = compact ? 0.26 : 0.14
            bottomRatio = compact ? 0.74 : 0.86
        }
        let top = size.height * topRatio
        let bottom = size.height * bottomRatio
        return (0..<count).map { index in
            top + (bottom - top) * CGFloat(index) / CGFloat(count - 1)
        }
    }

    private func drawBackdrop(
        in context: inout GraphicsContext,
        size: CGSize,
        left: CGPoint,
        hub: CGPoint,
        candidates: [CGFloat],
        candidateModels: [RouteCandidateView],
        rightX: CGFloat,
        elapsed: TimeInterval,
        immersive: Bool
    ) {
        if immersive, !reduceMotion {
            drawAmbientStars(in: &context, size: size, elapsed: elapsed)
        }

        let incomingStart = CGPoint(x: left.x + (compact ? 20 : (immersive ? 82 : 68)), y: left.y)
        let incomingEnd = CGPoint(x: hub.x - (compact ? 24 : (immersive ? 68 : 49)), y: hub.y)
        let incoming = curve(
            from: incomingStart,
            to: incomingEnd,
            bend: compact ? -4 : -18
        )

        context.stroke(
            incoming,
            with: .color(WatchTheme.sea.opacity(0.22)),
            style: StrokeStyle(lineWidth: compact ? 5 : (immersive ? 12 : 8), lineCap: .round)
        )
        context.stroke(
            incoming,
            with: .linearGradient(
                Gradient(colors: [WatchTheme.sea.opacity(0.18), WatchTheme.seaBright.opacity(0.9)]),
                startPoint: incomingStart,
                endPoint: incomingEnd
            ),
            style: StrokeStyle(lineWidth: compact ? 1.1 : (immersive ? 2.2 : 1.5), lineCap: .round)
        )

        let sourcePoint = CGPoint(x: hub.x - (compact ? 19 : (immersive ? 66 : 47)), y: hub.y)
        let arrivalPoint = CGPoint(x: hub.x + (compact ? 18 : (immersive ? 64 : 46)), y: hub.y)

        if !reduceMotion {
            drawParticle(
                context: &context,
                path: incoming,
                from: sourcePoint,
                to: arrivalPoint,
                progress: elapsed.truncatingRemainder(dividingBy: 2.1) / 2.1,
                color: WatchTheme.seaBright,
                radius: compact ? 2.1 : (immersive ? 4.6 : 3.2)
            )
        }

        for (index, y) in candidates.enumerated() {
            let candidate = candidateModels[index]
            let start = CGPoint(x: hub.x + (compact ? 20 : (immersive ? 67 : 48)), y: hub.y)
            let end = CGPoint(x: rightX - (compact ? 28 : (immersive ? 156 : 108)), y: y)
            let path = curve(
                from: start,
                to: end,
                bend: candidate.isSelected ? -18 : CGFloat(index.isEven ? 13 : -10)
            )

            context.stroke(
                path,
                with: .color(
                    candidate.isSelected
                        ? WatchTheme.tone(candidate.tone).opacity(0.18)
                        : Color.white.opacity(0.035)
                ),
                style: StrokeStyle(
                    lineWidth: candidate.isSelected ? (compact ? 5 : (immersive ? 14 : 9)) : (immersive ? 5 : 3),
                    lineCap: .round
                )
            )
            context.stroke(
                path,
                with: .color(
                    candidate.isSelected
                        ? WatchTheme.tone(candidate.tone).opacity(0.88)
                        : WatchTheme.mist.opacity(0.24)
                ),
                style: StrokeStyle(
                    lineWidth: candidate.isSelected ? (compact ? 1.4 : (immersive ? 2.8 : 2)) : (immersive ? 1.1 : 0.7),
                    lineCap: .round,
                    dash: candidate.isSelected ? [] : [4, 5]
                )
            )

            // 选中路由上的流光短划：亮色小段沿线向服务商移动。
            if candidate.isSelected, !reduceMotion {
                context.stroke(
                    path,
                    with: .color(WatchTheme.seaBright.opacity(0.85)),
                    style: StrokeStyle(
                        lineWidth: compact ? 1.7 : (immersive ? 3.4 : 2.3),
                        lineCap: .round,
                        dash: [1.2, 34],
                        dashPhase: -elapsed * 30
                    )
                )
            }

            if !reduceMotion {
                let duration = candidate.isSelected ? 1.65 : 2.7
                let phase = (elapsed / duration + Double(index) * 0.21)
                    .truncatingRemainder(dividingBy: 1)
                drawParticle(
                    context: &context,
                    path: path,
                    from: start,
                    to: end,
                    progress: phase,
                    color: candidate.isSelected
                        ? WatchTheme.tone(candidate.tone)
                        : WatchTheme.mist.opacity(0.42),
                    radius: candidate.isSelected ? (compact ? 2.2 : (immersive ? 4.8 : 3.4)) : (immersive ? 2.4 : 1.5)
                )

                // 下行响应：输出 token 从服务商流回网关（琥珀色），密度随输出量变化。
                if candidate.isSelected {
                    let normalized = min(1, log10(1 + Double(route.outputTokens)) / 7)
                    let responseCount = max(2, min(5, Int((2 + 3 * normalized).rounded())))
                    for k in 0..<responseCount {
                        let phaseBack = ((elapsed / 2.1) + Double(k) / Double(responseCount))
                            .truncatingRemainder(dividingBy: 1)
                        drawParticleBody(
                            context: &context,
                            from: end,
                            to: start,
                            progress: phaseBack,
                            color: WatchTheme.amber,
                            radius: compact ? 1.9 : (immersive ? 4.2 : 2.9),
                            alphaScale: 0.9
                        )
                    }
                }
            }
        }

        let ringRadius = compact ? 25.0 : (immersive ? 76.0 : 52.0)
        let pulse = reduceMotion ? 0.5 : elapsed.truncatingRemainder(dividingBy: 3.2) / 3.2
        let secondPulse = reduceMotion ? 0.5 : (elapsed + 1.6).truncatingRemainder(dividingBy: 3.2) / 3.2
        for phase in [pulse, secondPulse] {
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: hub.x - ringRadius - CGFloat(phase) * (compact ? 13 : 32),
                        y: hub.y - ringRadius - CGFloat(phase) * (compact ? 13 : 32),
                        width: (ringRadius + CGFloat(phase) * (compact ? 13 : 32)) * 2,
                        height: (ringRadius + CGFloat(phase) * (compact ? 13 : 32)) * 2
                    )
                ),
                with: .color(WatchTheme.sea.opacity(0.20 * (1 - phase))),
                lineWidth: 0.8
            )
        }

        // 网关核心的呼吸光晕（青紫混合的极光色）。
        if !reduceMotion {
            let breathe = 0.5 + 0.5 * sin(elapsed * 1.1)
            let glowRadius = ringRadius * (1.5 + breathe * 0.25)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: hub.x - glowRadius,
                        y: hub.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )
                ),
                with: .radialGradient(
                    Gradient(colors: [WatchTheme.violet.opacity(0.11 + breathe * 0.09), .clear]),
                    center: hub,
                    startRadius: 0,
                    endRadius: glowRadius
                )
            )
        }
    }

    private func drawParticle(
        context: inout GraphicsContext,
        path: Path,
        from: CGPoint,
        to: CGPoint,
        progress: Double,
        color: Color,
        radius: CGFloat
    ) {
        // 主粒子 + 两段拖尾，形成彗星式的运动轨迹。
        for (step, alphaScale) in [(0.0, 1.0), (0.055, 0.45), (0.11, 0.2)] {
            let raw = progress - step
            guard raw > 0.004 else { continue }
            drawParticleBody(
                context: &context,
                from: from,
                to: to,
                progress: raw,
                color: color,
                radius: radius * (1 - step * 3.2),
                alphaScale: alphaScale
            )
        }
    }

    private func drawParticleBody(
        context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        progress: Double,
        color: Color,
        radius: CGFloat,
        alphaScale: Double
    ) {
        let t = min(0.999, max(0.001, progress))
        let point = cubicPoint(
            t: t,
            p0: from,
            p1: CGPoint(
                x: from.x + (to.x - from.x) * 0.36,
                y: from.y + (to.y - from.y) * 0.14
            ),
            p2: CGPoint(
                x: from.x + (to.x - from.x) * 0.72,
                y: from.y + (to.y - from.y) * 0.86
            ),
            p3: to
        )
        let fade = sin(t * .pi)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ),
            with: .color(color.opacity((0.24 + fade * 0.76) * alphaScale))
        )
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: point.x - radius * 2.8,
                    y: point.y - radius * 2.8,
                    width: radius * 5.6,
                    height: radius * 5.6
                )
            ),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.20 * alphaScale), .clear]),
                center: point,
                startRadius: 0,
                endRadius: radius * 3
            )
        )
    }

    /// 沉浸模式下的环境星点：位置固定、亮度缓慢闪烁，营造深度。
    private func drawAmbientStars(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        let count = 26
        for index in 0..<count {
            let seed = Double(index)
            let x = size.width * (0.04 + (sin(seed * 12.9898) * 43758.5453)
                .truncatingRemainder(dividingBy: 1).magnitude * 0.92)
            let y = size.height * (0.05 + (sin(seed * 78.233) * 12345.6789)
                .truncatingRemainder(dividingBy: 1).magnitude * 0.90)
            let twinkle = 0.5 + 0.5 * sin(elapsed * (0.4 + seed * 0.07) + seed * 2.1)
            let radius = 0.7 + (seed.truncatingRemainder(dividingBy: 3)) * 0.4
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ),
                with: .color(WatchTheme.seaBright.opacity(0.06 + twinkle * 0.14))
            )
        }
    }

    @ViewBuilder
    private func routeNodes(
        size: CGSize,
        leftX: CGFloat,
        centerX: CGFloat,
        rightX: CGFloat,
        centerY: CGFloat,
        candidateY: [CGFloat],
        candidates: [RouteCandidateView]
    ) -> some View {
        let sourceWidth = compact ? 54.0 : (immersive ? 190.0 : 124.0)
        let sourceHeight = compact ? 50.0 : (immersive ? 134.0 : 94.0)
        let hubSize = compact ? 64.0 : (immersive ? 184.0 : 118.0)
        let candidateWidth = compact ? 70.0 : (immersive ? 214.0 : 152.0)
        let candidateHeight = compact ? 39.0 : (immersive ? 80.0 : 52.0)

        ZStack {
            AgentNode(
                name: route.agentName,
                detail: route.agentDetail,
                model: route.modelName,
                compact: compact,
                immersive: immersive
            )
            .frame(width: sourceWidth, height: sourceHeight)
            .position(x: leftX, y: centerY)

            GatewayNode(
                address: route.gatewayAddress,
                version: route.gatewayVersion,
                live: route.isLive,
                compact: compact,
                immersive: immersive
            )
            .frame(width: hubSize, height: hubSize)
            .position(x: centerX, y: centerY)

            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateNode(candidate: candidate, compact: compact, immersive: immersive)
                    .frame(width: candidateWidth, height: candidateHeight)
                    .position(x: rightX, y: candidateY[index])
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func curve(from: CGPoint, to: CGPoint, bend: CGFloat) -> Path {
        Path { path in
            let distance = max(16, to.x - from.x)
            path.move(to: from)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + distance * 0.42, y: from.y + bend),
                control2: CGPoint(x: to.x - distance * 0.42, y: to.y + bend)
            )
        }
    }

    private func cubicPoint(
        t: Double,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint
    ) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }
}

private struct AgentNode: View {
    let name: String
    let detail: String
    let model: String
    let compact: Bool
    let immersive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : (immersive ? 10 : 7)) {
            Text(name.uppercased())
                .font(.custom(WatchTheme.displayFont, size: compact ? 13 : (immersive ? 34 : 27)).weight(.semibold))
                .tracking(compact ? 0.7 : (immersive ? 1.4 : 1.1))
                .foregroundStyle(WatchTheme.ice)
                .lineLimit(1)
            if !compact {
                Text(model)
                    .font(.custom(WatchTheme.bodyFont, size: immersive ? 13 : 11).weight(.medium))
                    .foregroundStyle(WatchTheme.seaBright.opacity(0.86))
                    .lineLimit(1)
            }
            Text(detail)
                .font(.custom(WatchTheme.displayCNFont, size: compact ? 7 : (immersive ? 12 : 10)))
                .foregroundStyle(WatchTheme.mist)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : (immersive ? 22 : 16))
        .padding(.vertical, compact ? 5 : (immersive ? 18 : 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 7 : (immersive ? 17 : 13), style: .continuous)
                .fill(WatchTheme.abyss.opacity(0.90))
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 7 : (immersive ? 17 : 13), style: .continuous)
                .strokeBorder(WatchTheme.sea.opacity(0.34), lineWidth: 0.8)
        }
    }
}

private struct GatewayNode: View {
    let address: String
    let version: String?
    let live: Bool
    let compact: Bool
    let immersive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            WatchTheme.deep,
                            WatchTheme.abyss.opacity(0.98)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: compact ? 32 : (immersive ? 118 : 76)
                    )
                )
            Circle()
                .strokeBorder(WatchTheme.seaBright.opacity(live ? 0.72 : 0.26), lineWidth: 0.9)
            Circle()
                .strokeBorder(WatchTheme.sea.opacity(0.13), lineWidth: compact ? 7 : (immersive ? 28 : 18))
                .padding(compact ? 4 : (immersive ? 12 : 8))

            VStack(spacing: compact ? 1 : (immersive ? 8 : 5)) {
                BrandMark(size: compact ? 16 : (immersive ? 42 : 28))
                Text("MAGPIE")
                    .font(.custom(WatchTheme.displayFont, size: compact ? 11 : (immersive ? 32 : 23)).weight(.semibold))
                    .tracking(compact ? 1 : (immersive ? 2.2 : 1.6))
                    .foregroundStyle(WatchTheme.ice)
                if !compact {
                    Text(address)
                        .font(.custom(WatchTheme.monoFont, size: immersive ? 10 : 8))
                        .foregroundStyle(WatchTheme.seaBright.opacity(0.78))
                    Text(live ? "实时路由" : "待机")
                        .font(.custom(WatchTheme.displayCNFont, size: immersive ? 10 : 8).weight(.medium))
                        .tracking(immersive ? 1.4 : 0.8)
                        .foregroundStyle(live ? WatchTheme.seaBright : WatchTheme.mist)
                }
            }
        }
        .shadow(color: WatchTheme.sea.opacity(live ? 0.16 : 0), radius: 24)
    }
}

private struct CandidateNode: View {
    let candidate: RouteCandidateView
    let compact: Bool
    let immersive: Bool

    private var tint: Color { WatchTheme.tone(candidate.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : (immersive ? 8 : 6)) {
            HStack(spacing: 4) {
                Circle()
                    .fill(candidate.isSelected ? tint : WatchTheme.mist.opacity(0.35))
                    .frame(width: compact ? 3 : 5, height: compact ? 3 : 5)
                Text(candidate.providerName)
                    .font(.custom(WatchTheme.bodyFont, size: compact ? 7 : (immersive ? 14 : 11)).weight(.semibold))
                    .foregroundStyle(candidate.isSelected ? WatchTheme.ice : WatchTheme.mist)
                    .lineLimit(1)
                Spacer(minLength: 1)
                if !compact {
                    Text(candidate.stateText)
                        .font(.custom(WatchTheme.displayCNFont, size: immersive ? 10 : 8).weight(.medium))
                        .foregroundStyle(candidate.isSelected ? tint : WatchTheme.mist.opacity(0.74))
                }
            }

            if compact {
                HStack(spacing: 3) {
                    Text(candidate.account)
                        .font(.custom(WatchTheme.monoFont, size: 5.4))
                        .foregroundStyle(WatchTheme.mist.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 1)
                    Text(Fmt.percent(candidate.usedPercent))
                        .font(.custom(WatchTheme.monoFont, size: 5.4))
                        .foregroundStyle(candidate.isSelected ? tint : WatchTheme.mist)
                }
            } else {
                Text(candidate.account)
                    .font(.custom(WatchTheme.monoFont, size: immersive ? 10.5 : 8.4))
                    .foregroundStyle(WatchTheme.mist)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.075))
                    Capsule()
                        .fill(candidate.isSelected ? tint : WatchTheme.mist.opacity(0.30))
                        .frame(width: max(1, proxy.size.width * candidate.usedPercent / 100))
                }
            }
            .frame(height: compact ? 1.5 : (immersive ? 4 : 2.5))
        }
        .padding(.horizontal, compact ? 6 : (immersive ? 18 : 12))
        .padding(.vertical, compact ? 4 : (immersive ? 13 : 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 6 : (immersive ? 15 : 11), style: .continuous)
                .fill(
                    candidate.isSelected
                        ? WatchTheme.deep.opacity(0.95)
                        : WatchTheme.abyss.opacity(0.76)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 6 : (immersive ? 15 : 11), style: .continuous)
                .strokeBorder(
                    candidate.isSelected ? tint.opacity(0.68) : Color.white.opacity(0.075),
                    lineWidth: candidate.isSelected ? 1 : 0.6
                )
        }
        .shadow(color: candidate.isSelected ? tint.opacity(0.10) : .clear, radius: 12)
    }
}

private extension Int {
    var isEven: Bool { self.isMultiple(of: 2) }
}
