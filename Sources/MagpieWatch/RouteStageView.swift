import SwiftUI

// MARK: - Magpie Routing 舞台的复刻
//
// 复刻 yetone/magpie 的 Routing 页 token 流向模块（internal/gui/assets/plugins/routing）：
// 左侧是发出请求的 agent 节点，中间是 magpie 网关，右侧是路由的账号行；
// 细线连在节点之间，请求来时一只喜鹊叼着请求点飞进去，账号作答时点停在
// 线头闪烁，回信是空心点、由另一只喜鹊带回。线的颜色是各 agent 自己的
// 色相（HUES 表 + 备用色哈希），流动时 dash 前进。布局同 Magpie：宽时
// 三列并排，窄时（同 .max560）agent 与 magpie 并排、账号挂在下面一条
// 左侧竖巷上。紧凑模式是托盘面板的小舞台（pr-stage）：药丸节点、圆形
// hub、小点沿线飞行。

/// 各 agent 的请求与回信飞行的颜色，与 Magpie 的 hueOf 一致：
/// 有官方色的用官方色，其余按 id 哈希取备用色，红色除外。
enum AgentHue {
    private static let table: [String: UInt32] = [
        "claude": 0xd97757, "codex": 0x6366f1, "gemini": 0x0ea5e9, "copilot": 0xa855f7,
        "cursor": 0x14b8a6, "opencode": 0xeab308, "crush": 0xec4899, "goose": 0x84cc16,
        "pi": 0x10b981, "omp": 0xd946ef, "omo": 0x7c3aed, "dsh": 0x06b6d4,
        "commandcode": 0xf97316, "mimocode": 0x3b82f6, "deveco": 0x3c99cc,
    ]
    private static let spare: [UInt32] = [
        0x8b5cf6, 0x22c55e, 0x0d9488, 0x0891b2, 0xca8a04, 0xdb2777, 0x2563eb, 0x65a30d,
    ]

    static func of(_ name: String) -> Color {
        let lowered = name.lowercased()
        for (key, hex) in table where lowered.contains(key) {
            return Color(hex: hex)
        }
        var h: UInt32 = 0
        for scalar in lowered.unicodeScalars { h = h &* 31 &+ scalar.value }
        return Color(hex: spare[Int(h % UInt32(spare.count))])
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - 线的几何

enum WireSegment {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case quad(control: CGPoint, to: CGPoint)
    case cubic(c1: CGPoint, c2: CGPoint, to: CGPoint)
}

/// 一条线：Magpie 的 wire d 属性，平展成折线供 pointAt / tangent 查询
/// （对应 client.js 的 measure / pointAt，ptStep = 8 的做法）。
struct StageWire {
    let path: Path
    let length: CGFloat
    private let samples: [CGPoint]
    private let starts: [CGFloat]

    init(segments: [WireSegment]) {
        var path = Path()
        var points: [CGPoint] = []
        var current = CGPoint.zero
        for segment in segments {
            switch segment {
            case let .move(to: p):
                current = p
                path.move(to: p)
                points.append(p)
            case let .line(to: p):
                path.addLine(to: p)
                Self.appendLine(from: current, to: p, into: &points)
                current = p
            case let .quad(control: c, to: p):
                path.addQuadCurve(to: p, control: c)
                Self.appendCurve(from: current, c1: current, c2: c, to: p, into: &points)
                current = p
            case let .cubic(c1: a, c2: b, to: p):
                path.addCurve(to: p, control1: a, control2: b)
                Self.appendCurve(from: current, c1: a, c2: b, to: p, into: &points)
                current = p
            }
        }
        var cumulative: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            cumulative.append(total)
        }
        samples = points
        starts = cumulative
        length = total
        self.path = path
    }

    private static func appendLine(from a: CGPoint, to b: CGPoint, into points: inout [CGPoint]) {
        let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 8))
        for s in 1...steps {
            let t = CGFloat(s) / CGFloat(steps)
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }

    private static func appendCurve(from p0: CGPoint, c1: CGPoint, c2: CGPoint, to p3: CGPoint, into points: inout [CGPoint]) {
        let chord = hypot(p3.x - p0.x, p3.y - p0.y)
        let steps = max(12, Int(chord / 4))
        for s in 1...steps {
            let t = CGFloat(s) / CGFloat(steps)
            let mt = 1 - t
            let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
            points.append(CGPoint(
                x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
            ))
        }
    }

    var startPoint: CGPoint { point(0) }
    var endPoint: CGPoint { point(length) }

    /// 线上从起点算起 s 处的点（超出即夹住）。
    func point(_ s: CGFloat) -> CGPoint {
        guard samples.count > 1 else { return samples.first ?? .zero }
        let d = min(max(0, s), length)
        var lo = 0, hi = starts.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if starts[mid] <= d { lo = mid } else { hi = mid }
        }
        let span = starts[hi] - starts[lo]
        let f: CGFloat = span > 0 ? (d - starts[lo]) / span : 0
        let a = samples[lo], b = samples[hi]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// 线上 s 处的行进方向（单位向量）。
    func tangent(_ s: CGFloat) -> CGPoint {
        let ahead = point(s + 2), behind = point(s - 2)
        var dx = ahead.x - behind.x, dy = ahead.y - behind.y
        let n = hypot(dx, dy)
        guard n > 0.0001 else { return CGPoint(x: 1, y: 0) }
        dx /= n; dy /= n
        return CGPoint(x: dx, y: dy)
    }
}

/// 一次飞行要走的几条线（含正反），对应 pose() 的 legs。
struct FlightPath {
    struct Leg {
        let wire: StageWire
        var reversed = false
    }
    let legs: [Leg]
    let length: CGFloat

    init(_ legs: [Leg]) {
        self.legs = legs
        length = legs.reduce(0) { $0 + $1.wire.length }
    }

    func point(_ distance: CGFloat) -> CGPoint {
        var d = min(max(0, distance), length)
        for leg in legs {
            let l = leg.wire.length
            if d > l && l > 0 { d -= l; continue }
            return leg.wire.point(leg.reversed ? l - d : d)
        }
        return legs.last?.wire.point(legs.last?.wire.length ?? 0) ?? .zero
    }

    func tangent(_ distance: CGFloat) -> CGPoint {
        var d = min(max(0, distance), length)
        for leg in legs {
            let l = leg.wire.length
            if d > l && l > 0 { d -= l; continue }
            var t = leg.wire.tangent(leg.reversed ? l - d : d)
            if leg.reversed { t = CGPoint(x: -t.x, y: -t.y) }
            return t
        }
        return CGPoint(x: 1, y: 0)
    }
}

/// 经停 magpie 内部的弧：从一条线的头到另一条线的尾，port via()。
/// 它只做飞行的引导，从不画出来。
private func viaWire(from: CGPoint, fromTangent: CGPoint, to: CGPoint, toTangent: CGPoint) -> StageWire {
    let dx = to.x - from.x, dy = to.y - from.y
    let dist = hypot(dx, dy)
    let c1: CGPoint, c2: CGPoint
    if dist < 4 {
        let k: CGFloat = 10 * 0.42, m = k * 0.6
        let nx = fromTangent.y, ny = -fromTangent.x
        c1 = CGPoint(x: from.x + fromTangent.x * k - nx * m, y: from.y + fromTangent.y * k - ny * m)
        c2 = CGPoint(x: to.x - toTangent.x * k + nx * m, y: to.y - toTangent.y * k + ny * m)
    } else {
        let k = CGFloat(dist * 0.38), l = CGFloat(min(16, dist * 0.12))
        let nx = dy / dist, ny = -dx / dist
        c1 = CGPoint(x: from.x + fromTangent.x * k + nx * l, y: from.y + fromTangent.y * k + ny * l)
        c2 = CGPoint(x: to.x - toTangent.x * k + nx * l, y: to.y - toTangent.y * k + ny * l)
    }
    return StageWire(segments: [.move(to: from), .cubic(c1: c1, c2: c2, to: to)])
}

// MARK: - easing

/// cubic-bezier(x1,y1,x2,y2) 的进度换算（翅膀拍动等 CSS 动画用）。
private func bezierEase(_ t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
    guard t > 0, t < 1 else { return t <= 0 ? 0 : 1 }
    var lo = 0.0, hi = 1.0, mid = t
    for _ in 0..<24 {
        mid = (lo + hi) / 2
        let x = 3 * (1 - mid) * (1 - mid) * mid * x1 + 3 * (1 - mid) * mid * mid * x2 + mid * mid * mid
        if x < t { lo = mid } else { hi = mid }
    }
    let u = mid
    return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u
}

/// 大舞台的飞行缓动：(1 - cos(π·k)) / 2，鸟滑翔降落的那种（frame()）。
private func glideEase(_ k: Double) -> Double { (1 - cos(.pi * k)) / 2 }

/// 托盘小舞台的缓动：quad in-out（pTick）。
private func quadEase(_ k: Double) -> Double { k < 0.5 ? 2 * k * k : 1 - pow(-2 * k + 2, 2) / 2 }

private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

// MARK: - 喜鹊图标

/// hub 上的喜鹊图标：Magpie index.html 里 44×44 的 #bird，三段子路径，
/// 后两段是翅膀的镂空（原 path 为 evenodd），画时用底色补出。
enum MagpieBird {
    static let rawData = "M1.5 5.5C1.3 5.7 1.2 6.5 1.2 6.9C1.2 6.9 1.2 7 1.2 7.1C1.1 7.4 1.3 8 1.4 8.3C1.4 8.4 1.5 8.5 1.5 8.7C1.5 8.9 1.7 9 1.8 9.3C2.2 9.9 2.2 10 2.3 10.1C2.4 10.2 2.5 10.3 2.6 10.5C2.8 10.8 3 11.1 3.2 11.3C3.3 11.3 3.4 11.6 3.6 11.8C3.8 12 4.1 12.4 4.2 12.5C4.7 13 5.2 13.7 5.4 13.9C6 14.5 6.5 15.1 6.7 15.3C6.7 15.4 6.9 15.5 6.9 15.7C7.3 15.9 7.7 16.5 7.9 16.8C7.9 16.8 8 16.9 8 16.9C8.1 16.9 8.2 17.2 8.2 17.3C8.2 17.3 8.1 17.2 8.1 17.1C7.9 16.9 7.9 16.9 7.6 16.6C7.5 16.5 7.4 16.5 7.4 16.3C7.2 16.2 6.7 15.7 6.3 15.2C6.1 15.1 6 14.9 6 14.9C5.9 14.8 5.7 14.7 5.7 14.6C5.6 14.5 5.4 14.3 5.3 14.2C5.1 14.1 4.9 13.8 4.7 13.5C4.5 13.3 4.2 13.1 4.1 12.9C4.1 12.9 3.8 12.7 3.8 12.5C3.5 12.3 3 11.8 2.8 11.4C1.8 10.5 0.9 9.6 0.7 9.6C0.6 9.7 0.6 9.8 0.5 10C0.5 10.1 0.6 10.2 0.5 10.3C0.5 10.4 0.6 10.5 0.6 10.6C0.5 10.7 0.5 10.9 0.6 11C0.5 11.1 0.6 11.4 0.6 11.5C0.9 12.9 1.3 13.8 2.8 14.9C2.9 15.1 3.3 15.3 3.4 15.4C3.4 15.5 3.6 15.6 3.7 15.7C4.2 16 6.4 17.8 7 18.4C7.4 18.8 7.4 18.8 7.5 18.9C7.6 19 7.7 19 7.7 19.1C7.7 19.2 7.8 19.2 7.9 19.2C7.9 19.3 8.1 19.4 8.1 19.5C8.2 19.6 8.2 19.7 8.3 19.7C8.3 19.7 8.3 19.7 8.2 19.7C8.2 19.6 8.1 19.6 8 19.6C7.9 19.5 7.9 19.4 7.8 19.4C7.7 19.3 7.6 19.2 7.6 19.2C7.6 19.1 7.5 19 7.3 18.9C7.2 18.9 6.9 18.6 6.7 18.4C6.1 17.8 4.5 16.6 3.5 16C3.4 15.8 3 15.6 2.9 15.5C2.6 15.3 1.5 14.6 0.9 14.3C0.7 14.1 0.6 14.1 0.6 14.2C0.5 14.5 0.8 15.9 0.9 16.1C0.9 16.2 1 16.2 0.9 16.3C1.2 16.8 1.9 17.6 2.7 18.3C2.8 18.5 4 19.2 4.7 19.5C6.2 20.5 6.6 20.7 7.4 21.5C8.2 22.2 8.7 22.7 9.3 23.6C9.5 24.1 9.9 24.4 10.3 25.3C10.4 25.5 10.5 25.8 10.5 25.8C10.7 25.8 10.8 25.7 11 25.4C11.6 25 11.9 24.6 12.3 24.3C12.8 24 13 23.8 13 23.7C13.1 23.7 13.1 23.8 13 24C12 24.8 11 26 10.2 26.9C10.1 27.1 9.9 27.5 9.7 27.7C9.5 27.8 9.4 28 9.4 28C9.4 28 9.3 28.3 9.1 28.5C8.6 29.2 7.7 30.8 7.7 30.9C7.7 31 7.8 31 8.3 30.8C9 30.4 9.5 30.2 10.4 30C11.7 29.6 12.5 29.6 11.6 30C10.5 30.2 9.7 30.6 9.2 31.2C8.8 31.7 8.8 31.7 9.3 31.7C10.1 31.8 10.9 31.9 11.6 32.2C12.8 32.7 13.5 33.1 15.5 34.8C16.4 35.5 17.3 36.2 17.8 36.4C17.9 36.5 18.1 36.7 18.2 36.8C19.1 37.3 21.2 38.1 22.3 38.3C22.4 38.3 22.7 38.3 22.8 38.3C22.8 38.5 23 38.5 23 38.5C23.1 38.5 23.2 38.5 23.3 38.5C23.6 38.6 25.9 38.6 26.1 38.5C26.2 38.5 26.3 38.5 26.4 38.5C26.5 38.5 26.6 38.5 26.7 38.3C26.7 38.3 27 38.3 27.1 38.3C28.3 38.1 30.2 37.3 31.4 36.7C31.5 36.7 31.7 36.4 31.8 36.4C32.2 36.2 33.2 35.4 33.4 35.2C34.2 34.5 35.5 33 35.8 32.6C35.8 32.5 36 32.2 36.1 32C36.4 31.8 36.6 31.4 36.6 31.2C36.7 31.1 36.8 30.9 36.9 30.8C37.2 30.4 37.5 29.6 37.7 29.2C37.7 29.1 37.8 28.7 37.9 28.7C38.1 28.5 38.4 27.1 38.5 26.8C39 25.2 39.1 23.7 39 22.4C39 22.2 38.9 21.9 38.9 21.8C38.9 21.7 38.9 21.6 38.9 21.4C38.6 20.5 38.5 19.9 38.2 19C37.9 18.5 37.5 17.5 37.3 17.2C37 16.8 36.8 15.8 36.8 15.2C36.8 13.8 37.7 12.7 39.6 12.2C40.1 12.1 41.3 11.8 42.1 11.7C43.5 11.5 43.5 11.5 43.4 11.3C42.9 10.7 40.9 9.9 39.2 9.7C37.9 9.5 38.1 9.5 37.6 9C37 8.6 36.4 8 36 7.9C36 7.8 35.8 7.8 35.7 7.7C35.1 7.3 34.2 7 33.1 6.9C32.6 6.7 31.6 6.9 31 7C29.6 7.3 28.3 8 27.3 9.2C26.7 9.8 26.2 10.8 25.7 11.7C25.5 12.1 24.8 13.4 24.7 13.7C24.6 13.9 24.5 14.1 24.1 14.7C23.5 15.7 22.1 16.9 20.6 17.8C20.5 18 20.3 18.2 20.1 18.3C19.7 18.5 19.4 18.8 19.1 19C18.9 19.1 18.7 19.3 18.5 19.4C18 19.8 17.2 20.3 17 20.5C16.9 20.5 16.8 20.6 16.7 20.7C16.3 20.8 16.1 20.9 16 20.9C15.5 20.8 14.9 20.5 14.2 20.2C13.7 19.8 12.7 18.9 12.4 18.6C12.3 18.5 12.2 18.4 12.1 18.2C11.9 18 11.2 17.1 11 16.6C10.9 16.5 10.8 16.4 10.7 16.3C10.7 16.2 10.6 16.1 10.6 15.9C10.5 15.9 10.4 15.7 10.4 15.6C10.3 15.5 10.2 15.2 10.1 15C10 14.8 9.8 14.4 9.7 14.2C9.6 14 9.5 13.7 9.4 13.6C9.4 13.4 9.3 13.2 9.2 13C9.2 12.8 9 12.6 9 12.5C8.9 12.3 8.7 12.1 8.7 12C8.7 12 8.5 11.7 8.5 11.7C8.3 11.2 8.2 10.9 7.5 10C6.4 8.3 4.2 6.4 2.7 5.8C2 5.5 1.6 5.4 1.5 5.5ZM28.4 16.7C29.2 16.9 29.7 17.2 29.9 17.7C30.1 18.2 30 18.9 29.6 19.4C29.2 19.9 28.2 20.9 27.6 21.2C26.8 21.7 25.3 22.4 24.2 22.7C23.9 22.8 23.6 22.9 23.5 22.9C22.8 23.2 20.7 23.7 19.6 24C19 24.2 18.4 24.3 18.1 24.4C17.9 24.4 16.1 24.9 15.3 25.1C14.6 25.2 14.7 25.1 15.7 23.6C16.4 22.7 18.5 20.6 19.4 19.9C20.8 18.8 21.4 18.4 23.2 17.6C23.8 17.4 25.6 16.8 25.9 16.8C25.9 16.8 26.3 16.8 26.6 16.7C26.8 16.7 28.2 16.7 28.4 16.7ZM30.4 20.2C30.5 20.3 30.6 20.6 30.6 20.7C31.7 23.1 33.4 24.6 35.6 25.3C36.1 25.5 36.7 25.7 37.2 25.8C37.7 25.8 37.8 25.9 37.8 26.1C37.7 26.2 37.7 26.3 37.7 26.5C37.7 26.6 37.7 26.8 37.6 27C37.4 28.5 36.8 29.9 36.1 31C36.1 31.2 35.9 31.4 35.9 31.6C35.7 31.9 35.2 32.6 34.7 33.3C32.6 35.6 29.7 37.3 26.6 37.8C26.5 37.8 26.3 37.9 26.2 37.9C25.8 37.9 23.7 37.9 23.3 37.9C23.2 37.9 23 37.8 22.9 37.8C21.1 37.6 19.3 36.8 18 35.7C17.7 35.4 17 34.7 16.8 34.5C16.3 33.8 16.1 33 16.3 32.5C16.5 31.8 16.8 31.6 17.9 31.1C19.1 30.5 19.4 30.4 20.2 30C21.4 29.4 23.2 28.4 23.9 27.9C23.9 27.8 24.2 27.7 24.5 27.6C26.3 26.3 28 24.6 28.9 22.9C29.5 22.2 29.7 21.6 29.9 20.7C30.1 20 30.2 19.9 30.4 20.2Z"

    static let subpaths: [Path] = parse(rawData)

    private static func parse(_ d: String) -> [Path] {
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter || ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
                if ch.isLetter { tokens.append(String(ch)) }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var out: [Path] = []
        var path = Path()
        var index = 0
        func number() -> CGFloat {
            guard index < tokens.count else { return 0 }
            let v = CGFloat(Double(tokens[index]) ?? 0)
            index += 1
            return v
        }
        while index < tokens.count {
            switch tokens[index] {
            case "M":
                index += 1
                if !path.isEmpty { out.append(path); path = Path() }
                let x = number(), y = number()
                path.move(to: CGPoint(x: x, y: y))
            case "L":
                index += 1
                path.addLine(to: CGPoint(x: number(), y: number()))
            case "C":
                index += 1
                let c1x = number(), c1y = number(), c2x = number(), c2y = number(), x = number(), y = number()
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: c1y),
                    control2: CGPoint(x: c2x, y: c2y)
                )
            case "Z":
                index += 1
                path.closeSubpath()
            default:
                index += 1
            }
        }
        if !path.isEmpty { out.append(path) }
        return out
    }
}

/// 44×44 视窗的喜鹊图标，按 given size 画出；镂空用底色补出。
struct MagpieBirdView: View {
    var size: CGFloat
    var tint: Color
    var holeColor: Color

    var body: some View {
        Canvas { context, _ in
            let transform = CGAffineTransform(scaleX: size / 44, y: size / 44)
            guard let body = MagpieBird.subpaths.first else { return }
            context.fill(body.applying(transform), with: .color(tint))
            for hole in MagpieBird.subpaths.dropFirst() {
                context.fill(hole.applying(transform), with: .color(holeColor))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 飞行的喜鹊（叼着点的那只）

/// FLIER（client.js）：面朝右，点在喙尖；翅膀从肩头拍动。
private enum Flier {
    static let farWing: Path = path { $0.move(to: CGPoint(x: -14.5, y: -3.4)) }
        .curve(-16.5, -9.5, -14.2, -15, -8.6, -18.6)
        .curve(-9.4, -12.6, -9.6, -7.4, -9.2, -3.2)
        .close()
    static let tail: Path = path { $0.move(to: CGPoint(x: -31.5, y: 3.1)) }
        .line(-18.6, -1.8).line(-17.4, 1.2).line(-30.8, 4.6).close()
    static let beak: Path = path { $0.move(to: CGPoint(x: -2.3, y: -4.8)) }
        .line(1.4, -3.3).line(-2.3, -2.2).close()
    static let nearWing: Path = path { $0.move(to: CGPoint(x: -15.6, y: -3.2)) }
        .curve(-17.8, -10.2, -15.2, -16.4, -8.4, -20.4)
        .curve(-9.3, -13.6, -9.4, -7.8, -8.8, -2.8)
        .close()
    static let wingBar: Path = path { $0.move(to: CGPoint(x: -14.6, y: -5.6)) }
        .curve(-15.4, -10.4, -13.8, -14.4, -10.4, -17.2)

    private static func path(_ make: (inout Path) -> Void) -> Path {
        var p = Path()
        make(&p)
        return p
    }
}

private extension Path {
    func line(_ x: CGFloat, _ y: CGFloat) -> Path { var p = self; p.addLine(to: CGPoint(x: x, y: y)); return p }
    func curve(_ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat, _ x: CGFloat, _ y: CGFloat) -> Path {
        var p = self
        p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
        return p
    }
    func close() -> Path { var p = self; p.closeSubpath(); return p }
}

/// 翅膀的拍动：rtflap — 0%→scaleY(1)，55%→scaleY(-.62) skewX(-8°)，
/// 100%→回 1，每段按 cubic-bezier(.45,0,.3,1) 缓动。远翅慢 0.03s。
private func wingTransform(u: Double, origin: CGPoint) -> CGAffineTransform {
    let ease: Double
    let scaleY: Double
    let skewDeg: Double
    if u < 0.55 {
        ease = bezierEase(u / 0.55, x1: 0.45, y1: 0, x2: 0.3, y2: 1)
        scaleY = 1 + (-0.62 - 1) * ease
        skewDeg = -8 * ease
    } else {
        ease = bezierEase((u - 0.55) / 0.45, x1: 0.45, y1: 0, x2: 0.3, y2: 1)
        scaleY = -0.62 + 1.62 * ease
        skewDeg = -8 * (1 - ease)
    }
    let rad = CGFloat(skewDeg * .pi / 180)
    // 先移到原点、拍动、再移回去（transform-origin: 50% 100%）
    let toOrigin = CGAffineTransform(translationX: -origin.x, y: -origin.y)
    let flap = CGAffineTransform(a: 1, b: 0, c: tan(rad), d: CGFloat(scaleY), tx: 0, ty: 0)
    let back = CGAffineTransform(translationX: origin.x, y: origin.y)
    return toOrigin.concatenating(flap).concatenating(back)
}

/// 画出叼着点的喜鹊。调用方已把坐标原点放在飞行点上。
private func drawFlier(
    _ context: inout GraphicsContext,
    u: Double,
    body: Color,
    belly: Color,
    alpha: Double
) {
    // FLIER 组：scale(1.2) translate(-6.5 3.2) — 点落在喙尖。
    // 画布的 translate 在前、scale 在后，点先平移再放大，与 CSS 一致。
    context.translateBy(x: -6.5, y: 3.2)
    context.scaleBy(x: 1.2, y: 1.2)

    let nearOrigin = CGPoint(x: -13.1, y: -2.8)
    let farOrigin = CGPoint(x: -12.55, y: -3.2)
    let farU = (u + 0.03 / 0.42).truncatingRemainder(dividingBy: 1)

    func fill(_ p: Path, _ color: Color, _ a: Double, transform: CGAffineTransform = .identity) {
        context.fill(p.applying(transform), with: .color(color.opacity(a)))
    }

    // 远翅
    fill(Flier.farWing, body, alpha * 0.45, transform: wingTransform(u: farU, origin: farOrigin))
    // 尾、身、腹、头、喙
    fill(Flier.tail, body, alpha)
    context.fill(Path(ellipseIn: CGRect(x: -12.2 - 7.6, y: -1.4 - 3.9, width: 15.2, height: 7.8)), with: .color(body.opacity(alpha)))
    context.fill(Path(ellipseIn: CGRect(x: -12.8 - 4.3, y: 0.4 - 1.6, width: 8.6, height: 3.2)), with: .color(belly.opacity(alpha)))
    context.fill(Path(ellipseIn: CGRect(x: -4.9 - 3.1, y: -3.7 - 3.1, width: 6.2, height: 6.2)), with: .color(body.opacity(alpha)))
    fill(Flier.beak, body, alpha)
    // 近翅与翅上那道白
    let nearT = wingTransform(u: u, origin: nearOrigin)
    fill(Flier.nearWing, body, alpha, transform: nearT)
    context.stroke(
        Flier.wingBar.applying(nearT),
        with: .color(belly.opacity(alpha)),
        style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
    )
}

// MARK: - 舞台入口

struct RouteStageView: View {
    let route: RoutePresentation
    var compact = false

    var body: some View {
        if compact {
            MiniRouteStage(route: route)
        } else {
            FullRouteStage(route: route)
        }
    }
}

// MARK: - 大舞台（Routing 页的 rt-stage）

private struct FullRouteStage: View {
    let route: RoutePresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    // 尺度取自 routing.css 的桌面值，收紧以放进面板（不接收鼠标，不能滚动）
    private let nodeW: CGFloat = 118
    private let agentH: CGFloat = 48
    private let hubH: CGFloat = 56
    private let nodeRowH: CGFloat = 56
    private let colGap: CGFloat = 26
    private let lanePad: CGFloat = 22
    private let stackGap: CGFloat = 8
    private let rowH: CGFloat = 32
    private let rowGap: CGFloat = 5
    private let wideGap: CGFloat = 56

    // 一次请求的飞行节拍（play() 的时长）
    private let outDuration = 1.4
    private let holdDuration = 1.0
    private let backDuration = 1.4
    private let gapDuration = 0.3
    private var cycle: Double { outDuration + holdDuration + backDuration + gapDuration }

    private var rows: [RouteCandidateView] { Array(route.candidates.prefix(4)) }
    private var hue: Color { AgentHue.of(route.agentName) }

    var body: some View {
        stage
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let selected = route.candidates.first(where: \.isSelected)
        return "令牌流向：\(route.agentName) 经 magpie 路由到 \(selected?.providerName ?? "等待路由")；缓存 \(Fmt.compact(route.cacheTokens))，输入 \(Fmt.compact(route.inputTokens))，输出 \(Fmt.compact(route.outputTokens))"
    }

    private var stage: some View {
        let rowCount = max(1, rows.count)
        let rowsHeight = CGFloat(rowCount) * rowH + CGFloat(rowCount - 1) * rowGap
        let stageHeight = nodeRowH + stackGap + rowsHeight
        return TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            return GeometryReader { proxy in
                let size = proxy.size
                let wide = size.width >= 560
                let layout = makeLayout(width: size.width, height: stageHeight, wide: wide)

                ZStack {
                    // 线在最下（rt-wires）
                    WiresCanvas(
                        layout: layout,
                        rows: rows,
                        route: route,
                        hue: hue,
                        palette: palette,
                        elapsed: elapsed,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: size.width, height: size.height)

                    // 节点在上（rt-srcs / rt-hub / rt-accts）
                    agentNode
                        .frame(width: layout.agent.width, height: layout.agent.height)
                        .position(x: layout.agent.midX, y: layout.agent.midY)
                        .scaleEffect(tickScale(elapsed: elapsed))

                    hubNode
                        .frame(width: layout.hub.width, height: layout.hub.height)
                        .position(x: layout.hub.midX, y: layout.hub.midY)
                        .scaleEffect(tickScale(elapsed: elapsed))

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, candidate in
                        AccountRow(
                            candidate: candidate,
                            modelName: route.modelName,
                            isNow: candidate.isSelected && route.isLive,
                            width: layout.rowFrames[index].width
                        )
                        .position(x: layout.rowFrames[index].midX, y: layout.rowFrames[index].midY)
                    }

                    // 喜鹊在最上（rt-sky）
                    SkyCanvas(
                        layout: layout,
                        rows: rows,
                        route: route,
                        hue: hue,
                        palette: palette,
                        elapsed: elapsed,
                        reduceMotion: reduceMotion,
                        outDuration: outDuration,
                        holdDuration: holdDuration,
                        backDuration: backDuration,
                        cycle: cycle
                    )
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: stageHeight)
    }

    /// rttick：节点被点一下时轻轻放大。
    private func tickScale(elapsed: TimeInterval) -> CGFloat {
        guard !reduceMotion, route.isLive else { return 1 }
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        let d = min(phase.magnitude, (cycle - phase).magnitude)
        guard d < 0.4 else { return 1 }
        return 1 + 0.035 * CGFloat(sin(.pi * (1 - d / 0.4)))
    }

    // 布局，对应 layout() 的两次量测；尺寸都是自己定的，所以算得准
    private func makeLayout(width: CGFloat, height: CGFloat, wide: Bool) -> StageLayout {
        var layout = StageLayout()
        let rowsH = CGFloat(rows.count) * rowH + CGFloat(max(0, rows.count - 1)) * rowGap
        if wide {
            let cy = height / 2
            layout.agent = CGRect(x: 0, y: cy - agentH / 2, width: 124, height: agentH)
            layout.hub = CGRect(x: 124 + wideGap, y: cy - hubH / 2, width: 124, height: hubH)
            let rowsLeft: CGFloat = 124 + wideGap + 124 + wideGap
            let top = cy - rowsH / 2
            for i in 0..<rows.count {
                layout.rowFrames.append(CGRect(
                    x: rowsLeft,
                    y: top + CGFloat(i) * (rowH + rowGap),
                    width: max(60, width - rowsLeft),
                    height: rowH
                ))
            }
        } else {
            let cell = max(40, (width - colGap) / 2)
            let w = min(nodeW, cell)
            layout.agent = CGRect(x: (cell - w) / 2, y: (nodeRowH - agentH) / 2, width: w, height: agentH)
            layout.hub = CGRect(x: cell + colGap + (cell - w) / 2, y: 0, width: w, height: hubH)
            for i in 0..<rows.count {
                layout.rowFrames.append(CGRect(
                    x: lanePad,
                    y: nodeRowH + stackGap + CGFloat(i) * (rowH + rowGap),
                    width: max(60, width - lanePad),
                    height: rowH
                ))
            }
        }

        // agent → magpie 的线（两侧布局都用这条平缓的弧）
        let s = layout.agent, h = layout.hub
        let mx1 = (s.maxX + h.minX) / 2
        layout.agentWire = StageWire(segments: [
            .move(to: CGPoint(x: s.maxX, y: s.midY)),
            .cubic(c1: CGPoint(x: mx1, y: s.midY), c2: CGPoint(x: mx1, y: h.midY), to: CGPoint(x: h.minX, y: h.midY)),
        ])

        // magpie → 每一行
        for frame in layout.rowFrames {
            if wide, frame.minX > h.maxX {
                let mx = (h.maxX + frame.minX) / 2
                layout.rowWires.append(StageWire(segments: [
                    .move(to: CGPoint(x: h.maxX, y: h.midY)),
                    .cubic(c1: CGPoint(x: mx, y: h.midY), c2: CGPoint(x: mx, y: frame.midY), to: CGPoint(x: frame.minX, y: frame.midY)),
                ]))
            } else {
                // 窄布局：账号挂在 magpie 下面，一条左巷下来（fromHub）
                let x = frame.minX - 12
                let y = max(h.maxY, s.maxY - 8)
                layout.rowWires.append(StageWire(segments: [
                    .move(to: CGPoint(x: h.midX, y: h.maxY)),
                    .line(to: CGPoint(x: h.midX, y: y)),
                    .cubic(c1: CGPoint(x: h.midX, y: y + 22), c2: CGPoint(x: x, y: y + 2), to: CGPoint(x: x, y: y + 24)),
                    .line(to: CGPoint(x: x, y: frame.midY - 10)),
                    .quad(control: CGPoint(x: x, y: frame.midY), to: CGPoint(x: frame.minX, y: frame.midY)),
                ]))
            }
        }
        return layout
    }

    // rt-node rt-src
    private var agentNode: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(hue)
                    .frame(width: 6, height: 6)
                Text(route.agentName)
                    .font(.custom(WatchTheme.bodyFont, size: 11).weight(.semibold))
                    .foregroundStyle(palette.ice)
                    .lineLimit(1)
            }
            Text(route.agentDetail)
                .font(.custom(WatchTheme.displayCNFont, size: 8.5))
                .foregroundStyle(palette.mist)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.deep.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.hairline.opacity(0.9), lineWidth: 1)
        )
    }

    // rt-node rt-hub：描边是前景色，外圈是底色
    private var hubNode: some View {
        VStack(spacing: 1) {
            MagpieBirdView(size: 14, tint: palette.ice, holeColor: palette.deep)
            Text("magpie")
                .font(.custom(WatchTheme.bodyFont, size: 10).weight(.semibold))
                .foregroundStyle(palette.ice)
            Text(route.gatewayAddress)
                .font(.custom(WatchTheme.monoFont, size: 6.5))
                .foregroundStyle(palette.mist)
                .lineLimit(1)
            if rows.count > 1, let provider = rows.first(where: \.isSelected)?.providerName {
                Text(provider)
                    .font(.custom(WatchTheme.displayCNFont, size: 7.5).weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(palette.ice))
                    .foregroundStyle(palette.deep)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.panel.opacity(0.9))
                .padding(-4)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.deep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.ice.opacity(0.9), lineWidth: 1)
        )
        .padding(4)
    }
}

// MARK: - 布局与画布的数据

private struct StageLayout {
    var agent: CGRect = .zero
    var hub: CGRect = .zero
    var rowFrames: [CGRect] = []
    var agentWire = StageWire(segments: [.move(to: .zero), .line(to: .zero)])
    var rowWires: [StageWire] = []
}

/// rt-wires：线画在节点之下
private struct WiresCanvas: View {
    let layout: StageLayout
    let rows: [RouteCandidateView]
    let route: RoutePresentation
    let hue: Color
    let palette: WatchPalette
    let elapsed: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, _ in
            let flowing = route.isLive && !reduceMotion
            // agent 的线：请求飞行时流动（.live）
            strokeWire(
                &context, layout.agentWire,
                color: flowing ? hue : palette.hairline,
                lineWidth: 1.5,
                dash: flowing ? [3, 5] : nil,
                dashPhase: flowing ? -CGFloat(elapsed * 8 / 0.7) : 0,
                alpha: flowing ? 0.95 : 0.8
            )
            for (index, wire) in layout.rowWires.enumerated() {
                let candidate = rows[index]
                if candidate.isSelected {
                    // 走的这一条：流动或点亮（.live / .lit）
                    strokeWire(
                        &context, wire,
                        color: hue,
                        lineWidth: 1.5,
                        dash: flowing ? [3, 5] : nil,
                        dashPhase: flowing ? -CGFloat(elapsed * 8 / 0.7) : 0,
                        alpha: 0.95
                    )
                } else if candidate.tone == .coral {
                    // 休息中的账号：虚线（.rest）
                    strokeWire(&context, wire, color: palette.coral, lineWidth: 1.2, dash: [2, 6], dashPhase: 0, alpha: 0.4)
                } else {
                    strokeWire(&context, wire, color: palette.hairline, lineWidth: 1.5, dash: nil, dashPhase: 0, alpha: 0.8)
                }
            }
        }
    }

    private func strokeWire(
        _ context: inout GraphicsContext,
        _ wire: StageWire,
        color: Color,
        lineWidth: CGFloat,
        dash: [CGFloat]?,
        dashPhase: CGFloat,
        alpha: Double
    ) {
        guard wire.length > 1 else { return }
        context.stroke(
            wire.path,
            with: .color(color.opacity(alpha)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dash ?? [], dashPhase: dashPhase)
        )
    }
}

/// rt-sky：飞行的喜鹊和点画在节点之上
private struct SkyCanvas: View {
    let layout: StageLayout
    let rows: [RouteCandidateView]
    let route: RoutePresentation
    let hue: Color
    let palette: WatchPalette
    let elapsed: TimeInterval
    let reduceMotion: Bool
    let outDuration: Double
    let holdDuration: Double
    let backDuration: Double
    let cycle: Double

    var body: some View {
        Canvas { context, _ in
            guard !rows.isEmpty, !layout.rowWires.isEmpty else { return }
            let selectedIndex = max(0, rows.firstIndex(where: \.isSelected) ?? 0)
            guard selectedIndex < layout.rowWires.count else { return }
            let rowWire = layout.rowWires[selectedIndex]

            // 选中的一行有请求时，行首的点上有一圈涟漪（rtlive）
            if route.isLive, !reduceMotion {
                let phase = elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8
                let dotPoint = CGPoint(x: rowWire.startPoint.x, y: rowWire.startPoint.y)
                let radius = 4 + CGFloat(phase) * 7
                context.stroke(
                    Path(ellipseIn: CGRect(x: dotPoint.x - radius, y: dotPoint.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(palette.ice.opacity(0.35 * (1 - phase))),
                    lineWidth: 1.2
                )
            }

            guard route.isLive, !reduceMotion else { return }

            // 一次请求的飞行（play()）：去、等、回
            let wireToRow = FlightPath.Leg(wire: rowWire)
            let viaIn = viaWire(
                from: layout.agentWire.endPoint,
                fromTangent: layout.agentWire.tangent(layout.agentWire.length),
                to: rowWire.startPoint,
                toTangent: rowWire.tangent(0)
            )
            let viaBack = viaWire(
                from: rowWire.startPoint,
                fromTangent: CGPoint(x: -rowWire.tangent(0).x, y: -rowWire.tangent(0).y),
                to: layout.agentWire.endPoint,
                toTangent: CGPoint(x: -layout.agentWire.tangent(layout.agentWire.length).x, y: -layout.agentWire.tangent(layout.agentWire.length).y)
            )
            let outPath = FlightPath([
                FlightPath.Leg(wire: layout.agentWire),
                FlightPath.Leg(wire: viaIn),
                wireToRow,
            ])
            let backPath = FlightPath([
                FlightPath.Leg(wire: rowWire, reversed: true),
                FlightPath.Leg(wire: viaBack),
                FlightPath.Leg(wire: layout.agentWire, reversed: true),
            ])

            let t = elapsed.truncatingRemainder(dividingBy: cycle)

            if t < outDuration {
                // 去程：喜鹊叼着实心点飞向选中的账号
                let k = t / outDuration
                let d = glideEase(k) * outPath.length
                drawPacket(&context, at: outPath.point(d), filled: true, alpha: 1)
                drawTravellingFlier(&context, path: outPath, distance: d, u: elapsed / 0.42, spawnProgress: k)
            } else if t < outDuration + holdDuration {
                // 等待作答：点停在线头闪烁（.held），喜鹊松口飞走
                let into = t - outDuration
                let point = rowWire.endPoint
                let pulse = 1 - 0.55 * (0.5 - 0.5 * cos(2 * .pi * (elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2)))
                drawPacket(&context, at: point, filled: true, alpha: pulse)
                drawFlierAt(&context, at: point, u: elapsed / 0.42, body: palette.ice, belly: palette.deep, alpha: 1, away: min(1, into / 0.45))
            } else if t < outDuration + holdDuration + backDuration {
                // 回程：空心点由另一只喜鹊带回（.back）
                let k = (t - outDuration - holdDuration) / backDuration
                let d = glideEase(k) * backPath.length
                drawPacket(&context, at: backPath.point(d), filled: false, alpha: 1)
                drawTravellingFlier(&context, path: backPath, distance: d, u: elapsed / 0.42, spawnProgress: k)
            }
        }
    }

    /// 沿途的喜鹊：朝向飞行的方向，倾侧不超过一只鸟的程度；刚上路时
    /// 从左下落上来（rtcome），管倾斜的插值照 pose() 的来。
    private func drawTravellingFlier(
        _ context: inout GraphicsContext,
        path: FlightPath,
        distance: CGFloat,
        u: Double,
        spawnProgress: Double
    ) {
        let point = path.point(distance)
        let tangent = path.tangent(distance)
        var aim = atan2(tangent.y, abs(tangent.x)) * 180 / .pi
        aim = max(-24, min(24, aim))
        let flip = tangent.x < 0

        // pose() 的次序：平移到飞行点、掉头、再倾侧
        context.translateBy(x: point.x, y: point.y)
        if flip { context.scaleBy(x: -1, y: 1) }
        context.rotate(by: .radians(CGFloat(aim * .pi / 180)))
        var scale: CGFloat = 1
        var alpha = 1.0
        if spawnProgress < 0.3 / 1.4 {
            // rtcome：从 translate(-6,-10) scale(.85) 淡入
            let p = easeOutCubic(spawnProgress / (0.3 / 1.4))
            context.translateBy(x: -6 * CGFloat(1 - p), y: -10 * CGFloat(1 - p))
            scale = 0.85 + 0.15 * CGFloat(p)
            alpha = p
        }
        context.scaleBy(x: scale, y: scale)
        drawFlier(&context, u: u, body: palette.ice, belly: palette.deep, alpha: alpha)
    }

    /// 停在账号边上的喜鹊，松口后右上飘走（.away）。
    private func drawFlierAt(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        u: Double,
        body: Color,
        belly: Color,
        alpha: Double,
        away progress: Double
    ) {
        let p = easeOutCubic(progress)
        context.translateBy(x: point.x + 14 * CGFloat(p), y: point.y - 16 * CGFloat(p))
        let scale = 1 - 0.2 * CGFloat(p)
        context.scaleBy(x: scale, y: scale)
        context.rotate(by: .radians(CGFloat(-aimForAway * .pi / 180)))
        drawFlier(&context, u: u, body: body, belly: belly, alpha: alpha * (1 - p))
    }

    private let aimForAway: Double = 18

    private func drawPacket(_ context: inout GraphicsContext, at point: CGPoint, filled: Bool, alpha: Double) {
        let radius: CGFloat = filled ? 4.5 : 4
        // pkt 的 drop-shadow(0 0 3px)
        let glow = radius * 2.6
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [hue.opacity(0.45 * alpha), .clear]),
                center: point,
                startRadius: 0,
                endRadius: glow
            )
        )
        if filled {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(hue.opacity(alpha))
            )
        } else {
            // .pkt.back：底色填充、agent 色描边
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(palette.deep.opacity(alpha))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(hue.opacity(alpha)),
                lineWidth: 2.25
            )
        }
    }
}

// MARK: - 账号行（rt-accts li）

private struct AccountRow: View {
    let candidate: RouteCandidateView
    let modelName: String
    let isNow: Bool
    let width: CGFloat

    @Environment(\.watchPalette) private var palette

    private var resting: Bool { candidate.tone == .coral }

    var body: some View {
        HStack(spacing: 10) {
            // .dot：8px，选中即实心
            Circle()
                .fill(candidate.isSelected ? palette.ice : Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        candidate.isSelected ? palette.ice : palette.mist.opacity(0.8),
                        lineWidth: 1.5
                    )
                )
                .frame(width: 8, height: 8)

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Text(candidate.providerName)
                        .font(.custom(WatchTheme.bodyFont, size: 10.5).weight(.medium))
                        .foregroundStyle(candidate.isSelected ? palette.ice : palette.ice.opacity(0.82))
                        .lineLimit(1)
                    if !modelName.isEmpty {
                        Text(modelName)
                            .font(.custom(WatchTheme.monoFont, size: 7.5).weight(.medium))
                            .foregroundStyle(palette.mist)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(palette.panel.opacity(0.8))
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 4)
                    Text(candidate.stateText)
                        .font(.custom(WatchTheme.displayCNFont, size: 9))
                        .foregroundStyle(stateTint)
                        .lineLimit(1)
                }
                // .bar：3px 的用量条
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.panel.opacity(0.9))
                        Capsule()
                            .fill(candidate.isSelected ? palette.ice : palette.mist.opacity(0.75))
                            .frame(width: max(2, proxy.size.width * candidate.usedPercent / 100))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(width: width, height: 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.deep.opacity(resting ? 0.6 : 0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    candidate.isSelected ? palette.ice.opacity(0.9) : palette.hairline.opacity(0.8),
                    lineWidth: 1
                )
        )
        .opacity(resting ? 0.6 : 1)
    }

    private var stateTint: Color {
        if resting { return palette.coral.opacity(0.9) }
        return candidate.isSelected ? palette.ice : palette.mist
    }
}

// MARK: - 小舞台（托盘面板的 pr-stage）

private struct MiniRouteStage: View {
    let route: RoutePresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    private let hubSize: CGFloat = 26
    private let pillHeight: CGFloat = 16
    private let pillGap: CGFloat = 5
    private let sideGap: CGFloat = 14
    private let colGap: CGFloat = 12

    // pPlay 的节拍
    private let inDuration = 0.42
    private let outDuration = 0.46
    private let holdDuration = 0.6
    private let backDuration = 0.46
    private let gapDuration = 0.26
    private var cycle: Double { inDuration + outDuration + holdDuration + backDuration + gapDuration }

    private var hue: Color { AgentHue.of(route.agentName) }
    private var rows: [RouteCandidateView] {
        let picked = Array(route.candidates.prefix(2))
        if let selected = route.candidates.first(where: \.isSelected),
           !picked.contains(where: { $0.id == selected.id }) {
            return Array(([selected] + picked).prefix(2))
        }
        return picked
    }

    var body: some View {
        let shown = rows
        let columnHeight = CGFloat(max(1, shown.count)) * pillHeight + CGFloat(max(0, shown.count - 1)) * pillGap
        let stageHeight = max(hubSize, columnHeight) + 22
        return TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            return GeometryReader { proxy in
                let size = proxy.size
                let layout = makeLayout(width: size.width, height: stageHeight, rows: shown)

                ZStack {
                    // ps-wires
                    MiniWiresCanvas(layout: layout, shown: shown, route: route, hue: hue, palette: palette, elapsed: elapsed, reduceMotion: reduceMotion)
                        .frame(width: size.width, height: stageHeight)

                    // 左列：agent 药丸，右对齐（ps-col ps-from）
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hue)
                            .frame(width: 5, height: 5)
                        Text(route.agentName)
                            .font(.custom(WatchTheme.bodyFont, size: 8.5).weight(.semibold))
                            .foregroundStyle(palette.ice.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: pillHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.panel.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(palette.hairline.opacity(0.8), lineWidth: 1)
                    )
                    .frame(width: layout.fromWidth, alignment: .trailing)
                    .position(x: layout.fromWidth / 2, y: size.height / 2)

                    // ps-hub
                    MiniHub(size: hubSize, busy: route.isLive && !reduceMotion, palette: palette)
                        .position(x: layout.hub.midX, y: layout.hub.midY)

                    // 右列：目的药丸（ps-col ps-to）
                    VStack(spacing: pillGap) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { _, candidate in
                            MiniDestPill(candidate: candidate, flying: route.isLive && !reduceMotion, palette: palette)
                                .frame(width: layout.toWidth, alignment: .leading)
                        }
                    }
                    .frame(width: layout.toWidth)
                    .position(x: layout.toX + layout.toWidth / 2, y: size.height / 2)

                    // ps-sky
                    MiniSkyCanvas(layout: layout, shown: shown, route: route, hue: hue, palette: palette, elapsed: elapsed, reduceMotion: reduceMotion, inDuration: inDuration, outDuration: outDuration, holdDuration: holdDuration, backDuration: backDuration, cycle: cycle)
                        .frame(width: size.width, height: stageHeight)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: stageHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("令牌流向：\(route.agentName) 经 magpie 路由到 \(route.candidates.first(where: \.isSelected)?.providerName ?? "等待路由")")
    }

    private func makeLayout(width: CGFloat, height: CGFloat, rows: [RouteCandidateView]) -> MiniStageLayout {
        var layout = MiniStageLayout()
        let n = max(1, rows.count)
        let columnHeight = CGFloat(n) * pillHeight + CGFloat(n - 1) * pillGap
        let hubW = hubSize
        let side = max(40, (width - hubW - colGap * 2) / 2)
        layout.fromWidth = side
        layout.toWidth = side
        layout.toX = side + colGap + hubW + colGap
        layout.hub = CGRect(
            x: side + colGap,
            y: (height - hubW) / 2,
            width: hubW,
            height: hubW
        )
        layout.fromY = (height - columnHeight) / 2
        layout.toY = (height - columnHeight) / 2
        return layout
    }
}

private struct MiniStageLayout {
    var hub: CGRect = .zero
    var fromWidth: CGFloat = 40
    var toWidth: CGFloat = 40
    var toX: CGFloat = 0
    var fromY: CGFloat = 0
    var toY: CGFloat = 0
}

/// ps-hub：圆形 hub，请求飞行时有外扩的环
private struct MiniHub: View {
    let size: CGFloat
    let busy: Bool
    let palette: WatchPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.deep)
            Circle()
                .strokeBorder(palette.hairline.opacity(0.9), lineWidth: 1)
            MagpieBirdView(size: size * 0.62, tint: palette.ice, holeColor: palette.deep)
            if busy {
                psRing
            }
        }
        .frame(width: size, height: size)
    }

    private var psRing: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            let radius = size / 2 + CGFloat(phase) * 6
            Circle()
                .stroke(palette.ice.opacity(0.35 * (1 - phase)), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

/// ps-dst 的小药丸：状态点 + 名字
private struct MiniDestPill: View {
    let candidate: RouteCandidateView
    let flying: Bool
    let palette: WatchPalette

    private var dotColor: Color {
        if candidate.tone == .coral { return palette.coral }
        return palette.green
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .opacity(flying && candidate.isSelected ? 0.5 : 1)
            Text(candidate.providerName)
                .font(.custom(WatchTheme.bodyFont, size: 8.5).weight(.medium))
                .foregroundStyle(candidate.isSelected ? palette.ice : palette.ice.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    candidate.isSelected ? palette.ice.opacity(0.75) : palette.hairline.opacity(0.8),
                    lineWidth: 1
                )
        )
    }
}

/// ps-wires：小舞台的平缓弧线
private struct MiniWiresCanvas: View {
    let layout: MiniStageLayout
    let shown: [RouteCandidateView]
    let route: RoutePresentation
    let hue: Color
    let palette: WatchPalette
    let elapsed: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, _ in
            let flying = route.isLive && !reduceMotion
            let hy = layout.hub.midY
            // 进线
            let inY = layout.fromY + 8
            let x1 = layout.fromWidth - 2, x2 = layout.hub.minX - 1
            let mx = (x1 + x2) / 2
            let inWire = StageWire(segments: [
                .move(to: CGPoint(x: x1, y: inY)),
                .cubic(c1: CGPoint(x: mx, y: inY), c2: CGPoint(x: mx, y: hy), to: CGPoint(x: x2, y: hy)),
            ])
            stroke(&context, inWire, color: flying ? hue : palette.hairline, alpha: flying ? 0.6 : 0.8, phase: flying ? -elapsed * 8 / 0.7 : 0)
            // 出线
            for (index, _) in shown.enumerated() {
                let y = layout.toY + CGFloat(index) * (16 + 5) + 8
                let a = layout.hub.maxX + 1, b = layout.toX + 2
                let mx2 = (a + b) / 2
                let wire = StageWire(segments: [
                    .move(to: CGPoint(x: a, y: hy)),
                    .cubic(c1: CGPoint(x: mx2, y: hy), c2: CGPoint(x: mx2, y: y), to: CGPoint(x: b, y: y)),
                ])
                let selected = shown[index].isSelected
                stroke(
                    &context, wire,
                    color: selected ? (flying ? hue : hue.opacity(0.85)) : palette.hairline,
                    alpha: selected ? 0.75 : 0.55,
                    phase: selected && flying ? -elapsed * 8 / 0.7 : 0
                )
            }
        }
    }

    private func stroke(_ context: inout GraphicsContext, _ wire: StageWire, color: Color, alpha: Double, phase: CGFloat) {
        guard wire.length > 1 else { return }
        context.stroke(
            wire.path,
            with: .color(color.opacity(alpha)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: phase != 0 ? [3, 5] : [], dashPhase: phase)
        )
    }
}

/// ps-sky：沿线飞行的小点
private struct MiniSkyCanvas: View {
    let layout: MiniStageLayout
    let shown: [RouteCandidateView]
    let route: RoutePresentation
    let hue: Color
    let palette: WatchPalette
    let elapsed: TimeInterval
    let reduceMotion: Bool
    let inDuration: Double
    let outDuration: Double
    let holdDuration: Double
    let backDuration: Double
    let cycle: Double

    var body: some View {
        Canvas { context, _ in
            guard !shown.isEmpty, route.isLive, !reduceMotion else { return }
            let selectedIndex = max(0, shown.firstIndex(where: \.isSelected) ?? 0)
            let hy = layout.hub.midY
            let inY = layout.fromY + 8
            let x1 = layout.fromWidth - 2, x2 = layout.hub.minX - 1
            let mx = (x1 + x2) / 2
            let inWire = StageWire(segments: [
                .move(to: CGPoint(x: x1, y: inY)),
                .cubic(c1: CGPoint(x: mx, y: inY), c2: CGPoint(x: mx, y: hy), to: CGPoint(x: x2, y: hy)),
            ])
            let y = layout.toY + CGFloat(selectedIndex) * (16 + 5) + 8
            let a = layout.hub.maxX + 1, b = layout.toX + 2
            let mx2 = (a + b) / 2
            let outWire = StageWire(segments: [
                .move(to: CGPoint(x: a, y: hy)),
                .cubic(c1: CGPoint(x: mx2, y: hy), c2: CGPoint(x: mx2, y: y), to: CGPoint(x: b, y: y)),
            ])

            let t = elapsed.truncatingRemainder(dividingBy: cycle)
            if t < inDuration {
                let d = quadEase(t / inDuration) * inWire.length
                dot(&context, at: inWire.point(d), filled: true)
            } else if t < inDuration + outDuration {
                let d = quadEase((t - inDuration) / outDuration) * outWire.length
                dot(&context, at: outWire.point(d), filled: true)
            } else if t < inDuration + outDuration + holdDuration {
                let pulse = 1 - 0.55 * (0.5 - 0.5 * cos(2 * .pi * (elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2)))
                dot(&context, at: CGPoint(x: b, y: y), filled: true, alpha: pulse)
            } else if t < inDuration + outDuration + holdDuration + backDuration {
                let d = quadEase((t - inDuration - outDuration - holdDuration) / backDuration) * outWire.length
                dot(&context, at: outWire.point(outWire.length - d), filled: false)
            }
        }
    }

    private func dot(_ context: inout GraphicsContext, at point: CGPoint, filled: Bool, alpha: Double = 1) {
        let radius: CGFloat = 2.4
        let glow = radius * 2.4
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [hue.opacity(0.4 * alpha), .clear]),
                center: point,
                startRadius: 0,
                endRadius: glow
            )
        )
        if filled {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(hue.opacity(alpha))
            )
        } else {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(palette.deep.opacity(alpha))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(hue.opacity(alpha)),
                lineWidth: 1.4
            )
        }
    }
}
