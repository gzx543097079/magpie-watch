import SwiftUI

struct UsageSparkline: View {
    let points: [UsagePoint]
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette
    @State private var reveal: CGFloat = 0

    private var lineTint: Color { tint ?? palette.seaBright }

    var body: some View {
        GeometryReader { proxy in
            let values = points.map { Double($0.calls ?? 0) }
            let maximum = max(1, values.max() ?? 1)
            let width = proxy.size.width
            let height = proxy.size.height
            let samples = samplePoints(
                values: values,
                maximum: maximum,
                width: width,
                height: height
            )

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Path { path in
                        let y = height * CGFloat(index + 1) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.white.opacity(0.045), lineWidth: 0.5)
                }

                if samples.count > 1 {
                    let linePath = smoothPath(samples: samples)

                    // 曲线下方的渐变填充，跟随绘制进度从左向右擦除。
                    filledPath(samples: samples, width: width, height: height)
                        .fill(
                            LinearGradient(
                                colors: [lineTint.opacity(0.22), lineTint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask {
                            Rectangle()
                                .scaleEffect(x: reduceMotion ? 1 : reveal, anchor: .leading)
                        }

                    // 辉光层：先画一层更粗更淡的曲线作为光晕。
                    if !reduceMotion {
                        linePath
                            .trim(from: 0, to: reveal)
                            .stroke(
                                lineTint.opacity(0.28),
                                style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 4)
                    }

                    linePath
                        .trim(from: 0, to: reduceMotion ? 1 : reveal)
                        .stroke(
                            LinearGradient(
                                colors: [lineTint.opacity(0.55), lineTint],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )

                    if !reduceMotion, reveal > 0.98, let last = samples.last {
                        endPulse(at: last, tint: lineTint)
                    }
                } else {
                    Text("暂无用量数据")
                        .font(.custom(WatchTheme.bodyFont, size: 9))
                        .foregroundStyle(palette.mist.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .onAppear {
                reveal = reduceMotion ? 1 : 0
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        reveal = 1
                    }
                }
            }
            .onChange(of: values.count) { _, _ in
                guard !reduceMotion else { return }
                reveal = 0
                withAnimation(.easeInOut(duration: 0.9)) {
                    reveal = 1
                }
            }
        }
    }

    private struct Sample {
        let x: CGFloat
        let y: CGFloat
    }

    private func samplePoints(values: [Double], maximum: Double, width: CGFloat, height: CGFloat) -> [Sample] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            let x = width * CGFloat(index) / CGFloat(values.count - 1)
            let normalized = value / maximum
            let y = height - CGFloat(normalized) * height * 0.82 - 2
            return Sample(x: x, y: y)
        }
    }

    /// 通过相邻中点的二次曲线，把折线变成柔和的平滑曲线。
    private func smoothPath(samples: [Sample]) -> Path {
        Path { path in
            path.move(to: CGPoint(x: samples[0].x, y: samples[0].y))
            for index in 1..<samples.count {
                let previous = samples[index - 1]
                let current = samples[index]
                let midX = (previous.x + current.x) / 2
                path.addQuadCurve(
                    to: CGPoint(x: midX, y: (previous.y + current.y) / 2),
                    control: CGPoint(x: midX, y: previous.y)
                )
                path.addQuadCurve(
                    to: CGPoint(x: current.x, y: current.y),
                    control: CGPoint(x: midX, y: current.y)
                )
            }
        }
    }

    private func filledPath(samples: [Sample], width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height))
            path.addPath(smoothPath(samples: samples))
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
    }

    private func endPulse(at point: Sample, tint: Color) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.0) / 2.0
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.55 * (1 - phase)), lineWidth: 1)
                    .frame(width: 6 + phase * 10, height: 6 + phase * 10)
                Circle()
                    .fill(tint)
                    .frame(width: 3.4, height: 3.4)
                    .shadow(color: tint.opacity(0.8), radius: 3)
            }
            .position(x: point.x, y: point.y)
        }
    }
}

struct SignalBars: View {
    let points: [UsagePoint]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let values = points.map { Double($0.calls ?? 0) }
            let maximum = max(1, values.max() ?? 1)
            let count = max(1, values.count)
            let gap: CGFloat = 2
            let barWidth = max(1, (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(
                            value == 0
                                ? Color.white.opacity(0.075)
                                : tint.opacity(0.45 + 0.55 * value / maximum)
                        )
                        .frame(
                            width: barWidth,
                            height: max(2, proxy.size.height * CGFloat(value / maximum))
                        )
                        .animation(WatchMotion.data, value: value)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
