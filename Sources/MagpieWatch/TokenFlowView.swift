import SwiftUI

/// Token 流向图：上行车道是请求（缓存读取 + 输入令牌，青/蓝），下行车道是
/// 响应（输出令牌，琥珀）。车道厚度与粒子密度跟随真实 token 体量，
/// 让「今天流了多少 token、往哪个方向流」一眼可读。
struct TokenFlowView: View {
    let route: RoutePresentation
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var upVolume: Int { route.inputTokens + route.cacheTokens }
    private var cacheFraction: Double {
        guard upVolume > 0 else { return 0 }
        return Double(route.cacheTokens) / Double(upVolume)
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            if !compact {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("TOKEN 流向")
                        .panelLabel()
                        .foregroundStyle(WatchTheme.ice.opacity(0.75))
                    Text(route.tokenScopeText)
                        .font(.custom(WatchTheme.displayCNFont, size: 8).weight(.medium))
                        .tracking(0.5)
                        .foregroundStyle(WatchTheme.violet.opacity(0.85))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(WatchMotion.data, value: route.tokenScopeText)
                    Spacer()
                    if route.tokensPerSec > 0 {
                        Text("\(Int(route.tokensPerSec.rounded())) tok/s")
                            .font(.custom(WatchTheme.monoFont, size: 8))
                            .foregroundStyle(WatchTheme.amber.opacity(0.9))
                    }
                }
            }

            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let upLane = laneHeight(volume: upVolume, compact: compact)
                    let downLane = laneHeight(volume: route.outputTokens, compact: compact)
                    let gap: CGFloat = compact ? 4 : 7
                    let total = upLane + gap + downLane
                    let top = (size.height - total) / 2

                    drawLane(
                        context: &context,
                        size: size,
                        y: top + upLane / 2,
                        thickness: upLane,
                        count: particleCount(volume: upVolume, compact: compact),
                        colors: upLaneColors(count: particleCount(volume: upVolume, compact: compact)),
                        direction: .outbound,
                        elapsed: elapsed,
                        tint: WatchTheme.seaBright
                    )
                    drawLane(
                        context: &context,
                        size: size,
                        y: top + upLane + gap + downLane / 2,
                        thickness: downLane,
                        count: particleCount(volume: route.outputTokens, compact: compact),
                        colors: Array(repeating: WatchTheme.amber, count: particleCount(volume: route.outputTokens, compact: compact)),
                        direction: .inbound,
                        elapsed: elapsed,
                        tint: WatchTheme.amber
                    )
                }
            }
            .frame(height: compact ? 26 : 46)

            if !compact {
                HStack(spacing: 14) {
                    flowLabel(
                        arrow: "arrow.up.right",
                        title: "上行 · 缓存 + 输入",
                        value: Fmt.compact(upVolume),
                        tint: WatchTheme.seaBright
                    )
                    Spacer()
                    flowLabel(
                        arrow: "arrow.down.left",
                        title: "下行 · 输出",
                        value: Fmt.compact(route.outputTokens),
                        tint: WatchTheme.amber
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        "Token 流向：上行缓存加输入 \(Fmt.compact(upVolume))，下行输出 \(Fmt.compact(route.outputTokens))"
    }

    private enum FlowDirection {
        case outbound
        case inbound
    }

    /// log 刻度的车道厚度：10M token 时达到最大值。
    private func laneHeight(volume: Int, compact: Bool) -> CGFloat {
        let maximum: CGFloat = compact ? 7 : 13
        let minimum: CGFloat = compact ? 2.2 : 3.2
        let normalized = min(1, log10(1 + Double(volume)) / 7)
        return minimum + (maximum - minimum) * CGFloat(normalized)
    }

    private func particleCount(volume: Int, compact: Bool) -> Int {
        let normalized = min(1, log10(1 + Double(volume)) / 7)
        let base = compact ? 3.0 : 5.0
        let extra = compact ? 5.0 : 9.0
        return Int((base + extra * normalized).rounded())
    }

    private func upLaneColors(count: Int) -> [Color] {
        let cacheCount = Int((Double(count) * cacheFraction).rounded())
        return (0..<count).map { $0 < cacheCount ? WatchTheme.seaBright : WatchTheme.blue }
    }

    private func drawLane(
        context: inout GraphicsContext,
        size: CGSize,
        y: CGFloat,
        thickness: CGFloat,
        count: Int,
        colors: [Color],
        direction: FlowDirection,
        elapsed: TimeInterval,
        tint: Color
    ) {
        let margin: CGFloat = 8
        let width = size.width - margin * 2

        // 车道轴：一条带相位流动的细线。
        var axis = Path()
        axis.move(to: CGPoint(x: margin, y: y))
        axis.addLine(to: CGPoint(x: margin + width, y: y))
        context.stroke(
            axis,
            with: .color(tint.opacity(0.16)),
            style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
        )

        let endpoints: (CGPoint, CGPoint) = direction == .outbound
            ? (CGPoint(x: margin, y: y), CGPoint(x: margin + width, y: y))
            : (CGPoint(x: margin + width, y: y), CGPoint(x: margin, y: y))

        for index in 0..<max(count, 1) {
            let seed = Double(index) * 61.7 + (direction == .outbound ? 0 : 29.3)
            let speed = 0.055 + (seed.truncatingRemainder(dividingBy: 7) / 7) * 0.05
            let progress = ((elapsed * speed) + (seed / 9.7).truncatingRemainder(dividingBy: 1))
                .truncatingRemainder(dividingBy: 1)
            let x = endpoints.0.x + (endpoints.1.x - endpoints.0.x) * CGFloat(progress)
            let wobble = sin(elapsed * 1.4 + seed) * thickness * 0.22
            let point = CGPoint(x: x, y: y + wobble)
            let radius = thickness * (0.20 + (seed.truncatingRemainder(dividingBy: 5) / 5) * 0.14)
            let color = colors.isEmpty ? tint : colors[index % colors.count]
            let fade = sin(progress * .pi)

            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius * 2.4,
                    y: point.y - radius * 2.4,
                    width: radius * 4.8,
                    height: radius * 4.8
                )),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.16 * fade), .clear]),
                    center: point,
                    startRadius: 0,
                    endRadius: radius * 2.4
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color.opacity(0.45 + 0.5 * fade))
            )
        }

        // 端点箭头：标记流向。
        let arrowX = direction == .outbound ? size.width - 3 : 3
        var arrow = Path()
        let tip = CGPoint(x: arrowX, y: y)
        let back = direction == .outbound ? -5.0 : 5.0
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x + back, y: y - 3))
        arrow.addLine(to: CGPoint(x: tip.x + back, y: y + 3))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(tint.opacity(0.55)))
    }

    private func flowLabel(arrow: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: arrow)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.custom(WatchTheme.bodyFont, size: 7.5).weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 9.5).weight(.medium))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(WatchMotion.data, value: value)
        }
    }
}
