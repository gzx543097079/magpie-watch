import AppKit
import SwiftUI

// MARK: - 配色

/// 固定的单一配色。语义角色保持不变：`sea` / `seaBright` 是主能量与缓存流，
/// `blue` 是输入流，`amber` 是输出流和费用，`violet` 是氛围，`coral` 是错误。
struct WatchPalette: Equatable {
    var abyss: Color
    var deep: Color
    var panel: Color
    var sea: Color
    var seaBright: Color
    var ice: Color
    var mist: Color
    var amber: Color
    var coral: Color
    var blue: Color
    var green: Color
    var violet: Color
    var hairline: Color

    /// 上行缓存流。
    var cache: Color { seaBright }
    /// 上行输入流。
    var input: Color { blue }
    /// 下行输出流，同时用于费用。
    var output: Color { amber }

    func tone(_ tone: RouteTone) -> Color {
        switch tone {
        case .teal: return sea
        case .amber: return amber
        case .blue: return blue
        case .green: return green
        case .coral: return coral
        case .neutral: return mist
        }
    }

    static let watch = WatchPalette(
        abyss: rgb(0.016, 0.024, 0.055),
        deep: rgb(0.043, 0.070, 0.130),
        panel: rgb(0.065, 0.100, 0.175),
        sea: rgb(0.130, 0.830, 0.930),
        seaBright: rgb(0.400, 0.910, 0.980),
        ice: rgb(0.945, 0.960, 0.985),
        mist: rgb(0.560, 0.635, 0.720),
        amber: rgb(0.985, 0.750, 0.290),
        coral: rgb(0.985, 0.370, 0.400),
        blue: rgb(0.380, 0.645, 0.985),
        green: rgb(0.205, 0.830, 0.600),
        violet: rgb(0.655, 0.545, 0.980),
        hairline: Color.white.opacity(0.12)
    )
}

private struct WatchPaletteKey: EnvironmentKey {
    static let defaultValue = WatchPalette.watch
}

extension EnvironmentValues {
    var watchPalette: WatchPalette {
        get { self[WatchPaletteKey.self] }
        set { self[WatchPaletteKey.self] = newValue }
    }
}

private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Color(red: red, green: green, blue: blue)
}

// MARK: - 字体

enum WatchTheme {
    static let displayFont = "DIN Condensed"
    static let displayCNFont = "PingFang SC"
    static let bodyFont = "Avenir Next"
    static let monoFont = "Menlo"
}

// MARK: - 动效常量

enum WatchMotion {
    /// 面板尺寸、展开收起等布局变化的弹簧。
    static let layout = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// 数值、进度条等数据变化的柔和弹簧。
    static let data = Animation.spring(response: 0.55, dampingFraction: 0.9)
    /// 悬停、按压等快速反馈。
    static let press = Animation.easeOut(duration: 0.14)
    /// 分段入场的基础缓动。
    static func entrance(delay: Double) -> Animation {
        .spring(response: 0.6, dampingFraction: 0.85).delay(delay)
    }
}

// MARK: - 材质视图

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - 玻璃面板

struct GlassPanel: View {
    var cornerRadius: CGFloat = 26

    @Environment(\.watchPalette) private var palette

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            LinearGradient(
                colors: [
                    palette.deep.opacity(0.86),
                    palette.abyss.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    palette.violet.opacity(0.14),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 340
            )
            RadialGradient(
                colors: [
                    palette.sea.opacity(0.09),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 300
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color.white.opacity(0.05),
                            palette.sea.opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.42), radius: 36, x: 0, y: 20)
        .shadow(color: palette.violet.opacity(0.12), radius: 60, x: 0, y: 8)
    }
}

// MARK: - 卡片样式

private struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 17
    var tintOverride: Color?
    var fillOpacity: Double = 0.42
    var borderOpacity: Double = 0.09

    @Environment(\.watchPalette) private var palette

    private var tint: Color { tintOverride ?? palette.deep }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(fillOpacity + 0.06),
                                tint.opacity(fillOpacity - 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.7)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.white.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .padding(.horizontal, cornerRadius)
            }
    }
}

extension View {
    /// 统一的观测台卡片底色：轻微渐变、发丝描边和顶部高光。
    func watchCard(
        cornerRadius: CGFloat = 17,
        tint: Color? = nil,
        fillOpacity: Double = 0.42,
        borderOpacity: Double = 0.09
    ) -> some View {
        modifier(
            CardBackground(
                cornerRadius: cornerRadius,
                tintOverride: tint,
                fillOpacity: fillOpacity,
                borderOpacity: borderOpacity
            )
        )
    }
}

// MARK: - 按钮

struct WatchButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        WatchButtonBody(
            configuration: configuration,
            prominent: prominent
        )
    }
}

private struct WatchButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.watchPalette) private var palette

    var body: some View {
        configuration.label
            .font(.custom(WatchTheme.bodyFont, size: 11).weight(.medium))
            .foregroundStyle(prominent ? palette.abyss : palette.ice)
            .frame(minWidth: 28, minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        prominent
                            ? Color.white.opacity(hovering ? 0.4 : 0.18)
                            : Color.white.opacity(hovering ? 0.22 : 0.10),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: prominent ? palette.seaBright.opacity(hovering ? 0.35 : 0.18) : .clear,
                radius: hovering ? 9 : 5,
                y: 2
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : hovering ? 1.03 : 1)
            .animation(WatchMotion.press, value: configuration.isPressed)
            .animation(WatchMotion.press, value: hovering)
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        if prominent {
            return palette.seaBright.opacity(configuration.isPressed ? 0.75 : 1)
        }
        return Color.white.opacity(
            configuration.isPressed ? 0.16 : hovering ? 0.13 : 0.07
        )
    }
}

struct LiveDot: View {
    let isLive: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !isLive)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .overlay {
                    if isLive {
                        Circle()
                            .stroke(color.opacity(0.65), lineWidth: 1)
                            .scaleEffect(1 + (phase.truncatingRemainder(dividingBy: 1.6) / 1.6) * 1.9)
                            .opacity(1 - (phase.truncatingRemainder(dividingBy: 1.6) / 1.6))
                    }
                }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(WatchButtonStyle(prominent: prominent))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct BrandMark: View {
    var size: CGFloat = 34

    @Environment(\.watchPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.deep, palette.abyss.opacity(0.85)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [palette.seaBright.opacity(0.85), palette.sea.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            Path { path in
                let inset = size * 0.26
                path.move(to: CGPoint(x: inset, y: size * 0.72))
                path.addCurve(
                    to: CGPoint(x: size * 0.51, y: size * 0.34),
                    control1: CGPoint(x: size * 0.30, y: size * 0.72),
                    control2: CGPoint(x: size * 0.35, y: size * 0.34)
                )
                path.addCurve(
                    to: CGPoint(x: size - inset, y: size * 0.52),
                    control1: CGPoint(x: size * 0.68, y: size * 0.34),
                    control2: CGPoint(x: size * 0.71, y: size * 0.52)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [palette.seaBright, palette.amber],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: max(1.2, size * 0.052), lineCap: .round)
            )
            Circle()
                .fill(palette.amber)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: -size * 0.24, y: size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 入场动画辅助

/// 包住一整段内容，按给定延迟从下方轻微上浮并淡入。
struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(WatchMotion.entrance(delay: Double(index) * 0.07)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// 分段入场：index 越大出现得越晚，形成依次浮入的节奏。
    func entrance(index: Int) -> some View {
        modifier(Entrance(index: index))
    }
}

private struct PanelLabel: ViewModifier {
    @Environment(\.watchPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.custom(WatchTheme.bodyFont, size: 9).weight(.semibold))
            .tracking(1.3)
            .foregroundStyle(palette.mist)
            .textCase(.uppercase)
    }
}

extension View {
    func panelLabel() -> some View {
        modifier(PanelLabel())
    }
}
