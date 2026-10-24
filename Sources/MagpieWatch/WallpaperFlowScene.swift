import SwiftUI

/// 壁纸主舞台（3D 版）：智能体 → Magpie 网关 → 模型，再沿原路回流。
///
/// 相对旧版 `WallpaperRouteScene` 的区别：
/// - 真透视投影：节点沿纵深排成弧形，镜头缓慢摆动，底部有透视地面网格。
/// - 节点半径随调用量变化，流量大的一眼可见。
/// - 失败 / 超时 / 限流各有独立动画：炸裂、倒计时环、原路灰色回传。
/// - 活跃链路呼吸发光 + 流光扫描；空闲链路只留一条暗虚线。
struct WallpaperFlowScene: View {
    let board: WallpaperFlowBoard
    var showsPet: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette
    @State private var sim = FlowSim()

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                sim.advance(to: now, board: board, reduceMotion: reduceMotion)
                var renderer = FlowRenderer(
                    sim: sim,
                    board: board,
                    palette: palette,
                    size: size,
                    time: now,
                    reduceMotion: reduceMotion,
                    showsPet: showsPet
                )
                renderer.draw(into: &context)
            }
        }
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 阶段与时间线

/// 一次请求在舞台上会经过的分段。正常请求走 up→route→send→gen→back1→back2，
/// 异常请求在中途断掉，然后沿来路退回。
enum FlowLeg: Equatable {
    case up          // 智能体 → 网关
    case route       // 网关选路
    case send        // 网关 → 模型
    case gen         // 模型生成中
    case back1       // 模型 → 网关
    case back2       // 网关 → 智能体
    case bounce      // 在网关被限流弹回
    case rupture     // 炸裂：连接中断 / 上游错误
    case waiting     // 等待响应（超时倒计时）
    case expire      // 超时判定
    case ret1        // 异常回传：模型侧 → 网关
    case ret         // 异常回传：网关 → 智能体

    var isFault: Bool { self == .bounce || self == .rupture || self == .expire }
    var isReturn: Bool { self == .ret || self == .ret1 }
}

private enum LegCurve { case up, down }
private enum LegAnchor { case gateway, model, onDownCurve }

private struct LegStep {
    var leg: FlowLeg
    var duration: Double
    var curve: LegCurve?
    var direction: Double = 1
    var u0: Double = 0
    var u1: Double = 1
    var anchor: LegAnchor?
    var anchorU: Double = 0
}

/// 舞台上一条正在跑的请求。board 每 4 秒刷新一次且只给出粗粒度 stage，
/// 所以这里按 flow.id 自建连续时间线，刷新之间照样动。
private struct LivePacket {
    let id: String
    let agentID: String
    let modelID: String
    var outcome: WallpaperFlowOutcome
    var statusCode: Int
    let requestTokens: Int
    var responseTokens: Int
    var start: Double
    var steps: [LegStep]
    var total: Double
    var lastLeg: FlowLeg?
    var completed: Bool

    func locate(at elapsed: Double) -> (step: LegStep, progress: Double)? {
        if !completed, let generation = steps.first(where: { $0.leg == .gen }) {
            let before = steps.prefix(while: { $0.leg != .gen }).reduce(0) { $0 + $1.duration }
            if elapsed >= before { return (generation, min(0.8, (elapsed - before) / generation.duration)) }
        }
        var acc = 0.0
        for step in steps {
            if elapsed < acc + step.duration {
                return (step, (elapsed - acc) / max(step.duration, 0.0001))
            }
            acc += step.duration
        }
        return nil
    }
}

private struct Spark {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Double
    var decay: Double
    var color: Color
    var size: CGFloat
}

private struct Shockwave {
    var x: CGFloat
    var y: CGFloat
    var age: Double
    var duration: Double
    var reach: CGFloat
    var color: Color
}

/// 节点的位置插值状态：节点增删时平滑滑到新的均分位置，并做淡入淡出。
private struct NodeAnim {
    var y: CGFloat = 0
    var z: CGFloat = 0
    var targetY: CGFloat = 0
    var targetZ: CGFloat = 0
    var appear: Double = 0
    var placed = false
    var spin: Double = Double.random(in: 0..<6.28)
}

// MARK: - 模拟状态

/// 引用类型：直接在 Canvas 的绘制闭包里推进，避免 30fps 触发 SwiftUI 重新布局。
private final class FlowSim {
    var packets: [LivePacket] = []
    var known: Set<String> = []
    var activity: [String: Double] = [:]      // 链路活跃度，驱动呼吸
    var faultActivity: [String: Double] = [:] // 链路异常度，驱动染红
    var sparks: [Spark] = []
    var waves: [Shockwave] = []
    var nodes: [String: NodeAnim] = [:]
    var pet = PetState()
    var lastTime: Double = 0
    var dt: Double = 0

    func advance(to now: Double, board: WallpaperFlowBoard, reduceMotion: Bool) {
        if lastTime == 0 { lastTime = now }
        dt = min(0.08, max(0, now - lastTime))
        lastTime = now

        sync(board: board, now: now)

        let fade = exp(-dt * 1.5)
        for (k, v) in activity {
            let next = v * fade
            if next < 0.004 { activity.removeValue(forKey: k) } else { activity[k] = next }
        }
        let faultFade = exp(-dt * 1.1)
        for (k, v) in faultActivity {
            let next = v * faultFade
            if next < 0.004 { faultActivity.removeValue(forKey: k) } else { faultActivity[k] = next }
        }

        packets.removeAll { now - $0.start >= $0.total && $0.completed }
        for index in sparks.indices {
            sparks[index].life -= dt * sparks[index].decay
            sparks[index].x += sparks[index].vx * dt
            sparks[index].y += sparks[index].vy * dt
            sparks[index].vx *= 0.955
            sparks[index].vy = sparks[index].vy * 0.955 + 22 * dt
        }
        sparks.removeAll { $0.life <= 0 }
        for index in waves.indices { waves[index].age += dt }
        waves.removeAll { $0.age >= $0.duration }
    }

    /// 新出现的 flow 开一条动画；board 里消失的旧 flow 让它自己跑完。
    private func sync(board: WallpaperFlowBoard, now: Double) {
        let current = Set(board.flows.map(\.id))
        for flow in board.flows {
            if !known.contains(flow.id) {
                known.insert(flow.id)
                packets.append(makePacket(flow: flow, now: now))
            } else if let index = packets.firstIndex(where: { $0.id == flow.id }) {
                // 请求完成通常要等下一轮轮询才知道；此时从当前阶段接着向后走，
                // 避免成功或失败结果被误画成预言式的返程。
                if flow.stage == .returning && !packets[index].completed {
                    let replacement = makePacket(flow: flow, now: now)
                    packets[index].outcome = flow.outcome
                    packets[index].statusCode = flow.statusCode ?? 500
                    packets[index].responseTokens = flow.responseTokens
                    packets[index].steps = replacement.steps
                    packets[index].total = replacement.total
                    packets[index].completed = true
                    packets[index].start = now - revealOffset(in: replacement.steps, outcome: flow.outcome)
                }
            }
        }
        for index in packets.indices where !packets[index].completed && now - packets[index].start > 90 {
            packets[index].completed = true
            packets[index].total = 0
        }
        // 今日 trace 可能短暂漏掉旧请求；ID 始终保留，避免下一轮又播放一遍。
        // 上限防止长期运行时无限累积。
        if known.count > 10_000 { known = current.union(Set(packets.map(\.id))) }
    }

    private func revealOffset(in steps: [LegStep], outcome: WallpaperFlowOutcome) -> Double {
        let reveal: FlowLeg
        switch outcome {
        case .ok: reveal = .back1
        case .rateLimited: reveal = .bounce
        case .failed, .disconnected: reveal = .rupture
        case .timedOut: reveal = .expire
        }
        guard let index = steps.firstIndex(where: { $0.leg == reveal }) else { return 0 }
        return steps.prefix(index).reduce(0) { $0 + $1.duration }
    }

    private func makePacket(flow: WallpaperPacketFlow, now: Double) -> LivePacket {
        // 用稳定的 UTF-8 散列派生时长，刷新/重启后同一请求不会跳动。
        var seed: UInt64 = 14_695_981_039_346_656_037
        for byte in flow.id.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let up = 1.5 + rnd() * 0.7
        let send = 1.5 + rnd() * 0.7
        let gen = 1.2 + rnd() * 2.2
        let previewOutcome: WallpaperFlowOutcome = flow.stage == .returning ? flow.outcome : .ok
        var steps: [LegStep] = []

        switch previewOutcome {
        case .rateLimited:
            steps = [
                LegStep(leg: .up, duration: up, curve: .up, anchor: nil),
                LegStep(leg: .bounce, duration: 0.5, curve: nil, anchor: .gateway),
                LegStep(leg: .ret, duration: up * 0.85, curve: .up, direction: -1, anchor: nil)
            ]
        case .disconnected:
            let cut = 0.32 + rnd() * 0.4
            steps = [
                LegStep(leg: .up, duration: up, curve: .up, anchor: nil),
                LegStep(leg: .route, duration: 0.4, curve: nil, anchor: .gateway),
                LegStep(leg: .send, duration: send * cut, curve: .down, u0: 0, u1: cut, anchor: nil),
                LegStep(leg: .rupture, duration: 0.45, curve: nil, anchor: .onDownCurve, anchorU: cut),
                LegStep(leg: .ret1, duration: send * cut * 0.9, curve: .down, direction: -1, u0: 0, u1: cut, anchor: nil),
                LegStep(leg: .ret, duration: up * 0.85, curve: .up, direction: -1, anchor: nil)
            ]
        case .failed:
            steps = [
                LegStep(leg: .up, duration: up, curve: .up, anchor: nil),
                LegStep(leg: .route, duration: 0.4, curve: nil, anchor: .gateway),
                LegStep(leg: .send, duration: send, curve: .down, anchor: nil),
                LegStep(leg: .gen, duration: gen * 0.55, curve: nil, anchor: .model),
                LegStep(leg: .rupture, duration: 0.5, curve: nil, anchor: .model),
                LegStep(leg: .ret1, duration: send * 0.9, curve: .down, direction: -1, anchor: nil),
                LegStep(leg: .ret, duration: up * 0.85, curve: .up, direction: -1, anchor: nil)
            ]
        case .timedOut:
            steps = [
                LegStep(leg: .up, duration: up, curve: .up, anchor: nil),
                LegStep(leg: .route, duration: 0.4, curve: nil, anchor: .gateway),
                LegStep(leg: .send, duration: send, curve: .down, anchor: nil),
                LegStep(leg: .waiting, duration: 3.6, curve: nil, anchor: .model),
                LegStep(leg: .expire, duration: 0.6, curve: nil, anchor: .model),
                LegStep(leg: .ret1, duration: send * 1.15, curve: .down, direction: -1, anchor: nil),
                LegStep(leg: .ret, duration: up * 1.05, curve: .up, direction: -1, anchor: nil)
            ]
        case .ok:
            steps = [
                LegStep(leg: .up, duration: up, curve: .up, anchor: nil),
                LegStep(leg: .route, duration: 0.4, curve: nil, anchor: .gateway),
                LegStep(leg: .send, duration: send, curve: .down, anchor: nil),
                LegStep(leg: .gen, duration: gen, curve: nil, anchor: .model),
                LegStep(leg: .back1, duration: send * 0.9, curve: .down, direction: -1, anchor: nil),
                LegStep(leg: .back2, duration: up * 0.85, curve: .up, direction: -1, anchor: nil)
            ]
        }

        let elapsed: Double
        switch flow.stage {
        case .incoming: elapsed = 0
        case .outbound: elapsed = up + 0.4
        case .returning: elapsed = revealOffset(in: steps, outcome: previewOutcome)
        case .waiting: elapsed = 0
        }
        return LivePacket(
            id: flow.id,
            agentID: flow.agentID,
            modelID: flow.destinationID,
            outcome: previewOutcome,
            statusCode: flow.statusCode ?? 500,
            requestTokens: flow.requestTokens,
            responseTokens: flow.responseTokens,
            start: now - elapsed,
            steps: steps,
            total: steps.reduce(0) { $0 + $1.duration },
            lastLeg: nil,
            completed: flow.stage == .returning
        )
    }

    func spark(at point: CGPoint, color: Color, count: Int, power: CGFloat) {
        for _ in 0..<count {
            let angle = Double.random(in: 0..<6.2832)
            let speed = CGFloat(0.4 + Double.random(in: 0...1)) * power
            sparks.append(
                Spark(
                    x: point.x, y: point.y,
                    vx: CGFloat(cos(angle)) * speed, vy: CGFloat(sin(angle)) * speed,
                    life: 1, decay: 1.4 + Double.random(in: 0...1.6),
                    color: color, size: CGFloat(0.8 + Double.random(in: 0...1.6))
                )
            )
        }
        if sparks.count > 420 { sparks.removeFirst(sparks.count - 420) }
    }

    func wave(at point: CGPoint, color: Color, reach: CGFloat, duration: Double = 1.5) {
        waves.append(Shockwave(x: point.x, y: point.y, age: 0, duration: duration, reach: reach, color: color))
        if waves.count > 14 { waves.removeFirst() }
    }

    func node(_ id: String) -> NodeAnim {
        nodes[id] ?? NodeAnim()
    }
}

// MARK: - 3D 投影

private struct Projector {
    var center: CGPoint
    var focal: CGFloat
    var yaw: Double
    var pitch: Double

    /// 返回屏幕坐标与深度系数（近 1 以上、远小于 1），深度系数用于缩放笔宽与字号。
    func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> (point: CGPoint, depth: CGFloat) {
        let cy = CGFloat(cos(yaw)), sy = CGFloat(sin(yaw))
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy
        let cp = CGFloat(cos(pitch)), sp = CGFloat(sin(pitch))
        let y1 = y * cp - z1 * sp
        let z2 = y * sp + z1 * cp
        let k = focal / max(focal + z2, 1)
        return (CGPoint(x: center.x + x1 * k, y: center.y + y1 * k), k)
    }
}

private struct Vec3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
}

/// S 形链路：取两端中点作为两个控制点，让曲线先平出去再折向目标。
private func controlPoints(from a: Vec3, to b: Vec3, bulge: CGFloat) -> [Vec3] {
    let mx = (a.x + b.x) / 2
    let mz = (a.z + b.z) / 2 - bulge
    return [a, Vec3(x: mx, y: a.y, z: mz), Vec3(x: mx, y: b.y, z: mz), b]
}

private func cubic(_ p: [Vec3], _ t: CGFloat) -> Vec3 {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return Vec3(
        x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
        y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y,
        z: a * p[0].z + b * p[1].z + c * p[2].z + d * p[3].z
    )
}

// MARK: - 渲染

private struct FlowRenderer {
    let sim: FlowSim
    let board: WallpaperFlowBoard
    let palette: WatchPalette
    let size: CGSize
    let time: Double
    let reduceMotion: Bool
    let showsPet: Bool

    private var scale: CGFloat { min(size.width, size.height * 2.4) / 1600 }
    private let samples = 24

    mutating func draw(into context: inout GraphicsContext) {
        let w = size.width, h = size.height
        guard w > 40, h > 40 else { return }
        let s = scale

        let yaw = reduceMotion ? 0 : sin(time * 0.085) * 0.19 + sin(time * 0.031) * 0.05
        let pitch = reduceMotion ? 0.18 : 0.18 + sin(time * 0.057) * 0.05
        let cam = Projector(
            center: CGPoint(x: w * 0.5, y: h * 0.52),
            focal: w * 0.62,
            yaw: yaw,
            pitch: pitch
        )

        drawGrid(&context, cam: cam, s: s)

        let agents = board.agents
        let models = board.destinations
        layout(ids: agents.map(\.id), side: -1, cam: cam)
        layout(ids: models.map(\.id), side: 1, cam: cam)
        let visibleIDs = Set(agents.map(\.id) + models.map(\.id))
        sim.nodes = sim.nodes.filter { visibleIDs.contains($0.key) }

        var agentPos: [String: (CGPoint, CGFloat)] = [:]
        var modelPos: [String: (CGPoint, CGFloat)] = [:]
        var agentVec: [String: Vec3] = [:]
        var modelVec: [String: Vec3] = [:]
        for slot in agents {
            let n = sim.node(slot.id)
            let v = nodeVector(side: -1, node: n)
            agentVec[slot.id] = v
            agentPos[slot.id] = cam.project(v.x, v.y, v.z)
        }
        for slot in models {
            let n = sim.node(slot.id)
            let v = nodeVector(side: 1, node: n)
            modelVec[slot.id] = v
            modelPos[slot.id] = cam.project(v.x, v.y, v.z)
        }
        let hubVec = Vec3(x: 0, y: 0, z: -w * 0.07)
        let hub = cam.project(hubVec.x, hubVec.y, hubVec.z)

        // 先从本帧的位置计算活跃度，再画链路，发光会与粒子同步。
        for packet in sim.packets where !reduceMotion {
            guard let state = packet.locate(at: time - packet.start) else { continue }
            if state.step.curve == .up {
                let key = "a|" + packet.agentID
                sim.activity[key] = 1
                if packet.outcome != .ok && state.step.leg.isReturn { sim.faultActivity[key] = 1 }
            } else if state.step.curve == .down {
                let key = "m|" + packet.modelID
                sim.activity[key] = 1
                if packet.outcome != .ok && state.step.leg.isReturn { sim.faultActivity[key] = 1 }
            }
        }

        // --- 链路：采样一次，呼吸与包共用 ---
        var upCurves: [String: [Vec3]] = [:]
        var downCurves: [String: [Vec3]] = [:]
        for (index, slot) in agents.enumerated() {
            guard let v = agentVec[slot.id] else { continue }
            let ctrl = controlPoints(from: v, to: hubVec, bulge: w * 0.12)
            upCurves[slot.id] = ctrl
            drawLink(
                &context, control: ctrl, cam: cam,
                tint: palette.seaBright, alpha: sim.node(slot.id).appear,
                key: "a|" + slot.id, phase: Double(index) * 1.3, s: s
            )
        }
        for (index, slot) in models.enumerated() {
            guard let v = modelVec[slot.id] else { continue }
            let ctrl = controlPoints(from: hubVec, to: v, bulge: w * 0.12)
            downCurves[slot.id] = ctrl
            drawLink(
                &context, control: ctrl, cam: cam,
                tint: palette.blue, alpha: sim.node(slot.id).appear,
                key: "m|" + slot.id, phase: Double(index) * 0.9, s: s
            )
        }

        if !reduceMotion { drawWaves(&context, s: s) }

        // --- 请求推进 ---
        var agentHeat: [String: Double] = [:]
        var modelHeat: [String: Double] = [:]
        var modelRing: [String: Double] = [:]
        var modelWait: [String: Double] = [:]
        var hubFlash: Double = 0
        var hubFault = false
        var faultLive = false
        var legsOnStage: Set<FlowLeg> = []

        for index in sim.packets.indices {
            let packet = sim.packets[index]
            guard
                let upCtrl = upCurves[packet.agentID],
                let downCtrl = downCurves[packet.modelID],
                let located = packet.locate(at: time - packet.start)
            else { continue }
            if reduceMotion { continue }
            let step = located.step
            let progress = located.progress
            let leg = step.leg
            legsOnStage.insert(leg)
            if leg.isFault { faultLive = true }

            let tint = legColor(leg, packet: packet)

            var point = hub.point
            var depthK = hub.depth
            var onCurve: [Vec3]?
            var curveT: CGFloat = 0

            if let curve = step.curve {
                let ctrl = curve == .up ? upCtrl : downCtrl
                onCurve = ctrl
                let eased = CGFloat(easeInOut(progress))
                curveT = step.direction > 0
                    ? CGFloat(step.u0) + (CGFloat(step.u1) - CGFloat(step.u0)) * eased
                    : CGFloat(step.u1) + (CGFloat(step.u0) - CGFloat(step.u1)) * eased
                let v = cubic(ctrl, curveT)
                let projected = cam.project(v.x, v.y, v.z)
                point = projected.point
                depthK = projected.depth
                if curve == .up { agentHeat[packet.agentID] = 1 } else { modelHeat[packet.modelID] = 1 }
            } else if let anchor = step.anchor {
                switch anchor {
                case .gateway:
                    point = hub.point
                    depthK = hub.depth
                    hubFlash = max(hubFlash, 1 - progress)
                    if leg == .bounce { hubFault = true }
                case .model:
                    if let pos = modelPos[packet.modelID] { point = pos.0; depthK = pos.1 }
                    modelHeat[packet.modelID] = 1
                    if leg == .gen { modelRing[packet.modelID] = max(modelRing[packet.modelID] ?? 0, progress) }
                    if leg == .waiting { modelWait[packet.modelID] = max(modelWait[packet.modelID] ?? 0, progress) }
                case .onDownCurve:
                    let v = cubic(downCtrl, CGFloat(step.anchorU))
                    let projected = cam.project(v.x, v.y, v.z)
                    point = projected.point
                    depthK = projected.depth
                    modelHeat[packet.modelID] = 1
                }
            }

            // 阶段切换事件：冲击波 + 火花，只触发一次。
            if sim.packets[index].lastLeg != leg {
                sim.packets[index].lastLeg = leg
                switch leg {
                case .route:
                    sim.wave(at: hub.point, color: palette.seaBright, reach: w * 0.22)
                    sim.spark(at: hub.point, color: palette.seaBright, count: 8, power: 110 * s)
                case .gen:
                    sim.wave(at: point, color: tint, reach: w * 0.08)
                    sim.spark(at: point, color: tint, count: 12, power: 150 * s)
                case .back1:
                    sim.wave(at: point, color: palette.amber, reach: w * 0.07)
                    sim.pet.react(mood: .happy, text: "响应回来啦～", at: time)
                case .bounce, .rupture:
                    sim.wave(at: point, color: palette.coral, reach: w * 0.17, duration: 1.1)
                    sim.spark(at: point, color: palette.coral, count: 24, power: 200 * s)
                    sim.pet.react(mood: .sad, text: leg == .bounce ? "被限流了！429" : faultText(packet), at: time)
                case .expire:
                    sim.wave(at: point, color: palette.mist, reach: w * 0.13, duration: 1.3)
                    sim.spark(at: point, color: palette.mist, count: 16, power: 120 * s)
                    sim.pet.react(mood: .sad, text: "等太久了…超时啦", at: time)
                default:
                    break
                }
            }

            drawPacket(
                &context, point: point, depth: depthK, tint: tint, leg: leg,
                packet: packet, curve: onCurve, curveT: curveT,
                direction: step.direction, cam: cam, s: s, progress: progress
            )
        }

        if !reduceMotion { drawSparks(&context, s: s) }

        // --- 节点：半径随调用量，远处先画 ---
        let agentMax = max(agents.map(\.calls).max() ?? 1, 1)
        let modelTotal = max(models.reduce(0) { $0 + $1.calls }, 1)
        let modelCount = max(models.count, 1)
        var ordered: [(id: String, title: String, sub: String, tint: Color, pos: (CGPoint, CGFloat), radius: CGFloat, right: Bool, heat: Double, ring: Double, wait: Double)] = []
        for slot in agents {
            guard let pos = agentPos[slot.id] else { continue }
            let weight = Double(slot.calls) / Double(agentMax)
            ordered.append((
                slot.id, slot.name, "\(slot.calls) 次", palette.seaBright, pos,
                3.4 + CGFloat(min(1, weight)) * 7.6, true,
                agentHeat[slot.id] ?? 0, 0, 0
            ))
        }
        for slot in models {
            guard let pos = modelPos[slot.id] else { continue }
            let weight = Double(slot.calls) / Double(modelTotal) * Double(modelCount)
            ordered.append((
                slot.id, slot.modelName, slot.providerName, palette.blue, pos,
                3.4 + CGFloat(min(1, weight)) * 7.6, false,
                modelHeat[slot.id] ?? 0, modelRing[slot.id] ?? 0, modelWait[slot.id] ?? 0
            ))
        }
        ordered.sort { $0.pos.1 < $1.pos.1 }
        for item in ordered {
            drawNode(
                &context, at: item.pos.0, depth: item.pos.1, radius: item.radius,
                tint: item.tint, title: item.title, sub: item.sub,
                alignRight: item.right, heat: item.heat, ring: item.ring,
                wait: item.wait, appear: sim.node(item.id).appear,
                spin: sim.node(item.id).spin, s: s
            )
        }

        drawHub(&context, at: hub.point, depth: hub.depth, flash: hubFlash, fault: hubFault, s: s)
        drawCaption(&context, legs: legsOnStage, faulty: faultLive, s: s)

        if showsPet {
            if !reduceMotion { sim.pet.advance(dt: sim.dt, busy: sim.packets.count, now: time) }
            drawPet(&context, s: s)
        }
    }

    // MARK: 布局

    private func nodeVector(side: CGFloat, node: NodeAnim) -> Vec3 {
        let w = size.width
        let fraction: CGFloat = side < 0 ? 0.30 + node.z / w * 0.08 : 0.18 + node.z / w * 0.04
        return Vec3(x: side * w * fraction, y: node.y, z: node.z)
    }

    private func layout(ids: [String], side: CGFloat, cam: Projector) {
        let count = ids.count
        let w = size.width, h = size.height
        let cp = CGFloat(cos(cam.pitch)), sp = CGFloat(sin(cam.pitch))
        for (index, id) in ids.enumerated() {
            var anim = sim.node(id)
            let v: CGFloat = count <= 1 ? 0 : (CGFloat(index) - CGFloat(count - 1) / 2) / (CGFloat(count - 1) / 2)
            let z = (v * v - 0.40) * w * 0.60
            let x = side * w * (side < 0 ? 0.30 + z / w * 0.08 : 0.18 + z / w * 0.04)
            let zRot = -x * CGFloat(sin(cam.yaw)) + z * CGFloat(cos(cam.yaw))
            let desiredY = h * (count == 1 ? 0.5 : 0.20 + 0.55 * CGFloat(index) / CGFloat(count - 1))
            let dy = desiredY - cam.center.y
            anim.targetY = (dy * (cam.focal + zRot * cp) + cam.focal * zRot * sp)
                / (cam.focal * cp - dy * sp)
            anim.targetZ = z
            if !anim.placed {
                anim.y = anim.targetY
                anim.z = anim.targetZ
                anim.placed = true
            } else {
                let k = CGFloat(min(1, sim.dt * 4))
                anim.y += (anim.targetY - anim.y) * k
                anim.z += (anim.targetZ - anim.z) * k
            }
            anim.appear = min(1, anim.appear + sim.dt / 0.85)
            anim.spin += sim.dt * 0.55
            sim.nodes[id] = anim
        }
    }

    // MARK: 元素

    private func drawGrid(_ context: inout GraphicsContext, cam: Projector, s: CGFloat) {
        let w = size.width, h = size.height
        let groundY = h * 0.42, halfX = w * 0.80
        let z0 = -w * 0.42, z1 = w * 1.5
        for i in 0...14 {
            let x = -halfX + CGFloat(i) * halfX * 2 / 14
            var previous = cam.project(x, groundY, z0)
            for q in 1...12 {
                let next = cam.project(x, groundY, z0 + (z1 - z0) * CGFloat(q) / 12)
                let depth = max(0.2, min(2, (previous.depth + next.depth) / 2))
                var path = Path()
                path.move(to: previous.point)
                path.addLine(to: next.point)
                context.stroke(path, with: .color(palette.sea.opacity(0.055 * pow(Double(depth), 1.8))), lineWidth: 0.9 * depth * s)
                previous = next
            }
        }
        for j in 0...16 {
            let u = CGFloat(j) / 16
            let z = z0 + (z1 - z0) * u * u
            let a = cam.project(-halfX, groundY, z)
            let b = cam.project(halfX, groundY, z)
            let depth = max(0.2, min(2, a.depth))
            var path = Path()
            path.move(to: a.point)
            path.addLine(to: b.point)
            context.stroke(path, with: .color(palette.sea.opacity(0.085 * pow(Double(depth), 1.6))), lineWidth: 0.9 * depth * s)
        }
    }

    private func drawLink(
        _ context: inout GraphicsContext,
        control: [Vec3],
        cam: Projector,
        tint: Color,
        alpha: Double,
        key: String,
        phase: Double,
        s: CGFloat
    ) {
        var points: [(point: CGPoint, depth: CGFloat)] = []
        points.reserveCapacity(samples + 1)
        for i in 0...samples {
            let v = cubic(control, CGFloat(i) / CGFloat(samples))
            points.append(cam.project(v.x, v.y, v.z))
        }
        let heat = sim.activity[key] ?? 0
        let fault = sim.faultActivity[key] ?? 0
        let color = fault > 0.01 ? palette.coral : tint
        let breathe = 0.5 + 0.5 * sin(time * 3.1 + phase)
        let amp = max(heat, fault) * alpha
        let head = (time * 0.55 + phase * 0.17).truncatingRemainder(dividingBy: 1)
        var additive = context
        additive.blendMode = .plusLighter
        for i in 0..<samples {
            let near = max(0.2, min(2.1, (points[i].depth + points[i + 1].depth) / 2))
            let light = pow(Double(near), 1.7)
            var seg = Path()
            seg.move(to: points[i].point)
            seg.addLine(to: points[i + 1].point)
            context.stroke(seg, with: .color(color.opacity(min(1, (0.05 + fault * 0.09) * alpha * light))), lineWidth: 1.4 * near * s)
            guard heat > 0.012 || fault > 0.012 else { continue }
            additive.stroke(seg, with: .color(color.opacity(min(1, (0.07 + 0.22 * breathe) * amp * light))), lineWidth: (1.1 + 2.1 * breathe) * near * s)
            additive.stroke(seg, with: .color(color.opacity(min(1, 0.05 * amp * breathe * light))), lineWidth: (4 + 4 * breathe) * near * s)
            let u = (Double(i) + 0.5) / Double(samples)
            let d = abs(u - head)
            let f = pow(max(0, 1 - min(d, 1 - d) / 0.17), 2.2)
            guard f > 0.04 else { continue }
            additive.stroke(seg, with: .color(.white.opacity(min(1, f * amp * 0.45 * Double(near)))), style: StrokeStyle(lineWidth: (0.8 + 2.4 * f) * near * s, lineCap: .round))
            additive.stroke(seg, with: .color(color.opacity(min(1, f * amp * 0.7 * Double(near)))), style: StrokeStyle(lineWidth: (1.6 + 4.2 * f) * near * s, lineCap: .round))
        }
    }

    private func drawPacket(
        _ context: inout GraphicsContext,
        point: CGPoint,
        depth: CGFloat,
        tint: Color,
        leg: FlowLeg,
        packet: LivePacket,
        curve: [Vec3]?,
        curveT: CGFloat,
        direction: Double,
        cam: Projector,
        s: CGFloat,
        progress: Double
    ) {
        var additive = context
        additive.blendMode = .plusLighter

        // 彗尾
        if let ctrl = curve {
            for q in 1...10 {
                let t2 = max(0, min(1, curveT - CGFloat(direction) * CGFloat(q) * 0.016))
                let v = cubic(ctrl, t2)
                let p = cam.project(v.x, v.y, v.z).point
                let f = 1 - Double(q) / 10
                halo(&additive, at: p, color: tint, radius: (13 - CGFloat(q) * 0.7) * s * depth, alpha: 0.16 * f * f)
            }
        }

        let dead = leg == .expire || (packet.outcome != .ok && leg.isReturn)
        halo(&additive, at: point, color: tint, radius: 22 * s * depth, alpha: dead ? 0.4 : 0.8)
        if !dead { halo(&additive, at: point, color: .white, radius: 8 * s * depth, alpha: 0.85) }

        let core = (leg.isFault ? 4.6 : 3.4) * s * depth
        let rect = CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)
        context.fill(Path(ellipseIn: rect), with: .color(dead ? tint.opacity(0.8) : palette.ice.opacity(0.97)))
        if dead {
            let r = core + 3 * s * depth
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                with: .color(tint.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.1 * s * depth, dash: [3 * s, 3 * s])
            )
        }

        // 标签：异常与等待强制显示，正常请求只在行程中段露出。
        let label = legLabel(leg, packet: packet, progress: progress)
        guard !label.isEmpty else { return }
        let mid = curve == nil ? 1 : 1 - abs(Double(curveT) - 0.5) * 2
        let forced = leg.isFault || leg == .waiting
        guard forced || mid > 0.45 else { return }
        let alpha = forced ? 1 : min(1, (mid - 0.45) * 5)
        let text = Text(label)
            .font(.custom(WatchTheme.monoFont, size: (forced ? 9.4 : 8.6) * s * depth).weight(forced ? .semibold : .regular))
            .foregroundStyle(tint.opacity(0.88 * alpha))
        let offset = (leg == .gen || leg == .waiting) ? 34.0 : 15.0
        context.draw(context.resolve(text), at: CGPoint(x: point.x, y: point.y - offset * s * depth), anchor: .center)
    }

    private func drawNode(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        depth: CGFloat,
        radius: CGFloat,
        tint: Color,
        title: String,
        sub: String,
        alignRight: Bool,
        heat: Double,
        ring: Double,
        wait: Double,
        appear: Double,
        spin: Double,
        s: CGFloat
    ) {
        guard appear > 0.01 else { return }
        let ss = s * depth
        let r = radius * ss
        var additive = context
        additive.blendMode = .plusLighter
        halo(&additive, at: point, color: tint, radius: r * 4.4 + CGFloat(heat) * r * 4.6, alpha: (0.28 + heat * 0.5) * appear)
        if ring > 0 {
            halo(&additive, at: point, color: tint, radius: r * 2.4 + CGFloat(ring) * r * 8, alpha: 0.3 * (1 - ring) * appear)
            let rr = r + CGFloat(ring) * 32 * ss
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - rr, y: point.y - rr, width: rr * 2, height: rr * 2)),
                with: .color(tint.opacity(0.5 * (1 - ring) * appear)),
                lineWidth: 1.8 * ss
            )
        }

        let halo1 = r + 5 * ss
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - halo1, y: point.y - halo1, width: halo1 * 2, height: halo1 * 2)),
            with: .color(tint.opacity((0.18 + heat * 0.38) * appear)),
            lineWidth: ss
        )
        // 旋转短弧
        let arcR = r + 10 * ss
        for i in 0..<3 {
            var p = Path()
            p.addArc(
                center: point, radius: arcR,
                startAngle: .radians(spin + Double(i) * 2.09),
                endAngle: .radians(spin + Double(i) * 2.09 + 0.85),
                clockwise: false
            )
            context.stroke(p, with: .color(tint.opacity((0.10 + heat * 0.40) * appear)), lineWidth: 1.3 * ss)
        }
        // 超时倒计时环
        if wait > 0 {
            let wr = r + 15 * ss
            var p = Path()
            p.addArc(center: point, radius: wr, startAngle: .radians(-1.5708), endAngle: .radians(-1.5708 + 6.2832 * wait), clockwise: false)
            context.stroke(p, with: .color(palette.amber.opacity(0.75)), lineWidth: 2.2 * ss)
        }

        context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(tint.opacity(0.95 * appear)))
        let inner = r * 0.4
        context.fill(Path(ellipseIn: CGRect(x: point.x - inner, y: point.y - inner, width: inner * 2, height: inner * 2)), with: .color(palette.ice.opacity(0.95 * appear)))

        let dx = (alignRight ? -1 : 1) * (r + 12 * ss)
        let titleText = Text(title)
            .font(.custom(WatchTheme.displayCNFont, size: (11.5 + radius * 0.28) * ss).weight(.medium))
            .foregroundStyle(palette.ice.opacity((0.68 + heat * 0.30) * appear))
        context.draw(context.resolve(titleText), at: CGPoint(x: point.x + dx, y: point.y), anchor: alignRight ? .trailing : .leading)
        let subText = Text(sub)
            .font(.custom(WatchTheme.monoFont, size: 8.6 * ss))
            .foregroundStyle(tint.opacity((0.50 + heat * 0.32) * appear))
        context.draw(context.resolve(subText), at: CGPoint(x: point.x + dx, y: point.y + 13 * ss), anchor: alignRight ? .trailing : .leading)
    }

    private func drawHub(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        depth: CGFloat,
        flash: Double,
        fault: Bool,
        s: CGFloat
    ) {
        let ss = s * depth
        let load = min(1.0, Double(sim.packets.count) / 6)
        var additive = context
        additive.blendMode = .plusLighter
        halo(&additive, at: point, color: palette.sea, radius: CGFloat(100 + load * 40) * ss, alpha: 0.24 + load * 0.2, soft: true)
        halo(&additive, at: point, color: palette.seaBright, radius: CGFloat(30 + load * 16) * ss, alpha: 0.5)
        if flash > 0 {
            halo(&additive, at: point, color: fault ? palette.coral : .white, radius: CGFloat(26 + flash * 80) * ss, alpha: 0.4 * (1 - flash))
            let r = CGFloat(20 + flash * 62) * ss
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                with: .color((fault ? palette.coral : palette.seaBright).opacity(0.6 * (1 - flash))),
                lineWidth: 2.4 * ss
            )
        }

        let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(time * 2.1)
        for i in 0..<2 {
            let r = CGFloat(24 + Double(i) * 10 + pulse * 6) * ss
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                with: .color(palette.sea.opacity((0.30 - Double(i) * 0.11) * (1 - pulse * 0.3))),
                lineWidth: 1.1 * ss
            )
        }
        // 双向旋转刻度环
        for (dir, r0, r1, count, alpha) in [(1.0, 40.0, 48.0, 24, 0.30), (-0.62, 56.0, 62.0, 36, 0.17)] {
            let rot = reduceMotion ? 0 : time * 0.35 * dir
            for i in 0..<count {
                let a = Double(i) / Double(count) * 6.2832 + rot
                let outer = (i % 6 == 0 ? r1 + 4 : r1)
                var p = Path()
                p.move(to: CGPoint(x: point.x + CGFloat(cos(a) * r0) * ss, y: point.y + CGFloat(sin(a) * r0) * ss))
                p.addLine(to: CGPoint(x: point.x + CGFloat(cos(a) * outer) * ss, y: point.y + CGFloat(sin(a) * outer) * ss))
                context.stroke(p, with: .color(palette.sea.opacity(i % 6 == 0 ? alpha + 0.14 : alpha)), lineWidth: ss)
            }
        }
        // 核心四芒星
        for i in 0..<4 {
            let a = (reduceMotion ? 0 : time * 0.9) + Double(i) * 1.5708
            var p = Path()
            p.move(to: point)
            p.addLine(to: CGPoint(x: point.x + CGFloat(cos(a)) * CGFloat(28 + load * 16) * ss, y: point.y + CGFloat(sin(a)) * CGFloat(28 + load * 16) * ss))
            additive.stroke(p, with: .color(palette.seaBright.opacity(0.16 + load * 0.2)), lineWidth: 1.6 * ss)
        }

        let outer = 13 * ss, core = 8.5 * ss
        context.fill(Path(ellipseIn: CGRect(x: point.x - outer, y: point.y - outer, width: outer * 2, height: outer * 2)), with: .color(palette.sea.opacity(0.24)))
        context.fill(Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)), with: .color(palette.ice.opacity(0.97)))

        let name = Text("MAGPIE 网关")
            .font(.custom(WatchTheme.displayCNFont, size: 12 * ss).weight(.semibold))
            .foregroundStyle(palette.ice.opacity(0.92))
        context.draw(context.resolve(name), at: CGPoint(x: point.x, y: point.y - 60 * ss), anchor: .center)
        let addr = Text(board.isOnline ? "127.0.0.1:3425 · 在线" : "127.0.0.1:3425 · 离线")
            .font(.custom(WatchTheme.monoFont, size: 9 * ss))
            .foregroundStyle((board.isOnline ? palette.seaBright : palette.coral).opacity(0.65))
        context.draw(context.resolve(addr), at: CGPoint(x: point.x, y: point.y - 46 * ss), anchor: .center)
    }

    private func drawWaves(_ context: inout GraphicsContext, s: CGFloat) {
        var additive = context
        additive.blendMode = .plusLighter
        for wave in sim.waves {
            let u = wave.age / wave.duration
            let r = CGFloat(u) * wave.reach
            guard r > 1 else { continue }
            additive.stroke(
                Path(ellipseIn: CGRect(x: wave.x - r, y: wave.y - r, width: r * 2, height: r * 2)),
                with: .color(wave.color.opacity(0.3 * (1 - u) * (1 - u))),
                lineWidth: (2.6 - CGFloat(u) * 2) * s
            )
        }
    }

    private func drawSparks(_ context: inout GraphicsContext, s: CGFloat) {
        var additive = context
        additive.blendMode = .plusLighter
        for spark in sim.sparks {
            halo(&additive, at: CGPoint(x: spark.x, y: spark.y), color: spark.color,
                 radius: spark.size * 6 * s * CGFloat(spark.life), alpha: spark.life * 0.55)
        }
    }

    private func drawCaption(_ context: inout GraphicsContext, legs: Set<FlowLeg>, faulty: Bool, s: CGFloat) {
        let groups: [(String, Set<FlowLeg>, Color)] = [
            ("多智能体", [.up], palette.seaBright),
            ("网关选路", [.route, .bounce], palette.sea),
            ("多模型", [.send, .gen, .waiting], palette.blue),
            (faulty ? "异常回流" : "原路回流", [.back1, .back2, .ret, .ret1, .rupture, .expire], faulty ? palette.coral : palette.amber)
        ]
        var widths: [CGFloat] = []
        var resolved: [GraphicsContext.ResolvedText] = []
        for (label, keys, tint) in groups {
            let lit = !keys.isDisjoint(with: legs)
            let text = Text(label)
                .font(.custom(WatchTheme.displayCNFont, size: 12.5 * s).weight(.medium))
                .foregroundStyle(lit ? tint.opacity(0.98) : palette.mist.opacity(0.38))
            let r = context.resolve(text)
            resolved.append(r)
            widths.append(r.measure(in: size).width)
        }
        let gap = 40 * s
        let total = widths.reduce(0, +) + gap * 3
        var x = size.width / 2 - total / 2
        let y = size.height * 0.055
        for (index, r) in resolved.enumerated() {
            context.draw(r, at: CGPoint(x: x, y: y), anchor: .leading)
            let lit = !groups[index].1.isDisjoint(with: legs)
            if lit {
                var p = Path()
                p.move(to: CGPoint(x: x, y: y + 9 * s))
                p.addLine(to: CGPoint(x: x + widths[index], y: y + 9 * s))
                context.stroke(p, with: .color(groups[index].2.opacity(0.6)), lineWidth: 1.4 * s)
            }
            x += widths[index]
            if index < 3 {
                let arrow = Text(index == 2 ? "◀" : "▶")
                    .font(.system(size: 9 * s))
                    .foregroundStyle(palette.mist.opacity(0.42))
                context.draw(context.resolve(arrow), at: CGPoint(x: x + gap / 2, y: y), anchor: .center)
                x += gap
            }
        }
    }

    // MARK: 工具

    private func halo(_ context: inout GraphicsContext, at point: CGPoint, color: Color, radius: CGFloat, alpha: Double, soft: Bool = false) {
        guard alpha > 0.004, radius > 0.5 else { return }
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let stops: [Gradient.Stop] = soft
            ? [.init(color: color.opacity(alpha * 0.55), location: 0),
               .init(color: color.opacity(alpha * 0.14), location: 0.35),
               .init(color: .clear, location: 1)]
            : [.init(color: .white.opacity(alpha * 0.9), location: 0),
               .init(color: color.opacity(alpha * 0.8), location: 0.14),
               .init(color: color.opacity(alpha * 0.17), location: 0.44),
               .init(color: .clear, location: 1)]
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(stops: stops), center: point, startRadius: 0, endRadius: radius)
        )
    }

    private func legColor(_ leg: FlowLeg, packet: LivePacket) -> Color {
        switch leg {
        case .up: return palette.seaBright
        case .route: return palette.sea
        case .send: return palette.blue
        case .gen: return palette.violet
        case .back1, .back2: return palette.amber
        case .bounce, .rupture: return palette.coral
        case .waiting: return palette.amber
        case .expire: return palette.mist
        case .ret, .ret1: return packet.outcome == .timedOut ? palette.mist : palette.coral
        }
    }

    private func faultText(_ packet: LivePacket) -> String {
        packet.outcome == .disconnected ? "连接中断了…" : "上游 \(packet.statusCode)，不是我们的锅"
    }

    private func legLabel(_ leg: FlowLeg, packet: LivePacket, progress: Double) -> String {
        switch leg {
        case .up:
            return packet.requestTokens > 0 ? "↑ \(Fmt.compact(packet.requestTokens))" : "↑ 请求"
        case .send: return "→ 模型"
        case .gen: return "生成中…"
        case .back1, .back2:
            return packet.responseTokens > 0 ? "↓ \(Fmt.compact(packet.responseTokens))" : "↓ 响应"
        case .bounce: return "⚠ 429 限流"
        case .rupture: return packet.outcome == .disconnected ? "✕ 连接中断" : "✕ \(packet.statusCode) 上游错误"
        case .waiting: return "⏱ 等待响应 \(Int(progress * 30))s"
        case .expire: return "⏱ 超时"
        case .ret, .ret1: return packet.outcome == .timedOut ? "⏱ 超时回传" : "✕ 失败回传"
        case .route: return ""
        }
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: 桌面小宠物

    private func drawPet(_ context: inout GraphicsContext, s: CGFloat) {
        let pet = sim.pet
        let scale = s * 1.0
        let px = 148 * s
        let py = size.height - 125 * s
        let bob = reduceMotion ? 0 : CGFloat(sin(time * 1.7) * 5) * s - CGFloat(pet.hop) * 16 * s
        let sleeping = pet.mood == .asleep

        var additive = context
        additive.blendMode = .plusLighter
        halo(&additive, at: CGPoint(x: px, y: py + bob), color: pet.mood == .sad ? palette.coral : palette.sea,
             radius: 76 * scale, alpha: 0.22, soft: true)

        var body = context
        body.translateBy(x: px, y: py + bob)
        body.rotate(by: .radians(reduceMotion ? 0 : sin(time * 0.9) * 0.05))
        body.scaleBy(x: scale, y: scale)

        // 尾鳍
        var tail = body
        tail.translateBy(x: 36, y: 4)
        tail.rotate(by: .radians(reduceMotion ? 0 : sin(time * (sleeping ? 1.1 : 2.6)) * 0.3))
        var tailPath = Path()
        tailPath.move(to: .zero)
        tailPath.addQuadCurve(to: CGPoint(x: 30, y: -14), control: CGPoint(x: 18, y: -20))
        tailPath.addQuadCurve(to: CGPoint(x: 30, y: 12), control: CGPoint(x: 20, y: -2))
        tailPath.addQuadCurve(to: CGPoint(x: 0, y: 4), control: CGPoint(x: 16, y: 16))
        tailPath.closeSubpath()
        tail.fill(tailPath, with: .color(palette.sea.opacity(0.88)))

        // 身体
        body.fill(
            Path(ellipseIn: CGRect(x: -42, y: -34, width: 84, height: 68)),
            with: .linearGradient(
                Gradient(colors: [palette.seaBright, palette.sea]),
                startPoint: CGPoint(x: -40, y: -34), endPoint: CGPoint(x: 40, y: 34)
            )
        )
        body.stroke(Path(ellipseIn: CGRect(x: -42, y: -34, width: 84, height: 68)), with: .color(palette.ice.opacity(0.3)), lineWidth: 1.3)
        // 肚皮
        body.fill(Path(ellipseIn: CGRect(x: -32, y: -5, width: 60, height: 34)), with: .color(palette.ice.opacity(0.92)))
        // 侧鳍
        var fin = body
        fin.translateBy(x: -6, y: 16)
        fin.rotate(by: .radians(0.5 + (reduceMotion ? 0 : sin(time * 2.2) * 0.18)))
        fin.fill(Path(ellipseIn: CGRect(x: -14, y: -6, width: 28, height: 12)), with: .color(palette.sea.opacity(0.95)))
        // 头顶喜鹊尾羽
        var hair = body
        hair.translateBy(x: -6, y: -33)
        hair.rotate(by: .radians(-0.35 + (reduceMotion ? 0 : sin(time * 1.9) * 0.14)))
        var hairPath = Path()
        hairPath.move(to: .zero)
        hairPath.addQuadCurve(to: CGPoint(x: 4, y: -22), control: CGPoint(x: -4, y: -16))
        hair.stroke(hairPath, with: .color(palette.ice.opacity(0.8)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        hair.fill(Path(ellipseIn: CGRect(x: 0.8, y: -26.2, width: 6.4, height: 6.4)), with: .color(palette.amber))
        // 腮红
        body.fill(Path(ellipseIn: CGRect(x: -29, y: 2, width: 14, height: 8.4)), with: .color(palette.coral.opacity(0.38)))
        body.fill(Path(ellipseIn: CGRect(x: -3, y: 2, width: 14, height: 8.4)), with: .color(palette.coral.opacity(0.38)))
        // 眼睛
        let ink = Color(red: 0.08, green: 0.14, blue: 0.18)
        for ex in [CGFloat(-20), CGFloat(2)] {
            if pet.mood == .happy && !sleeping {
                var p = Path()
                p.addArc(center: CGPoint(x: ex, y: -4), radius: 6, startAngle: .radians(3.5), endAngle: .radians(6.0), clockwise: false)
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            } else if sleeping || pet.blink > 0 {
                var p = Path()
                p.move(to: CGPoint(x: ex - 6, y: -6))
                p.addLine(to: CGPoint(x: ex + 6, y: -6))
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            } else {
                body.fill(Path(ellipseIn: CGRect(x: ex - 5.6, y: -13.2, width: 11.2, height: 14.4)), with: .color(ink))
                body.fill(Path(ellipseIn: CGRect(x: ex - 4.1, y: -10.7, width: 4.2, height: 4.2)), with: .color(.white.opacity(0.95)))
                if pet.mood == .sad {
                    body.fill(
                        Path(ellipseIn: CGRect(x: ex - 2.3, y: 3 + CGFloat(sin(time * 4) * 1.5), width: 4.6, height: 4.6)),
                        with: .color(palette.seaBright.opacity(0.85))
                    )
                }
            }
        }
        // 嘴
        var mouth = Path()
        switch pet.mood {
        case .happy: mouth.addArc(center: CGPoint(x: -9, y: 4), radius: 5, startAngle: .radians(0.4), endAngle: .radians(2.74), clockwise: false)
        case .sad: mouth.addArc(center: CGPoint(x: -9, y: 11), radius: 5, startAngle: .radians(3.6), endAngle: .radians(5.8), clockwise: false)
        default: mouth.addArc(center: CGPoint(x: -9, y: 4), radius: 3.6, startAngle: .radians(0.6), endAngle: .radians(2.54), clockwise: false)
        }
        body.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        // 对话气泡
        let age = time - pet.sayAt
        guard let line = pet.line, age < 4.2 else { return }
        let fade = min(1, age / 0.22) * min(1, (4.2 - age) / 0.5)
        let text = Text(line)
            .font(.custom(WatchTheme.displayCNFont, size: 11 * s).weight(.medium))
            .foregroundStyle(palette.ice.opacity(0.92 * fade))
        let resolved = context.resolve(text)
        let tw = resolved.measure(in: size).width
        let bw = tw + 24 * s, bh = 28 * s
        let bx = px - bw / 2 + 6 * s, by = py + bob - 66 * s - bh
        let bubble = Path(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: 12 * s)
        context.fill(bubble, with: .color(palette.abyss.opacity(0.84 * fade)))
        context.stroke(bubble, with: .color((pet.mood == .sad ? palette.coral : palette.sea).opacity(0.5 * fade)), lineWidth: 1.1 * s)
        context.draw(resolved, at: CGPoint(x: bx + bw / 2, y: by + bh / 2), anchor: .center)
    }
}

// MARK: - 小宠物状态

enum PetMood { case calm, happy, alert, sad, asleep }

/// 「喜鹊鲸」：纯矢量绘制、零素材依赖，表情与台词跟着真实流量走。
final class PetState {
    var mood: PetMood = .calm
    var moodAt: Double = -9
    var line: String?
    var sayAt: Double = -9
    var blink: Double = 0
    var nextBlink: Double = 2
    var hop: Double = 0
    var idle: Double = 0

    private static let busyLines = ["流量有点大哦～", "全都走本机网关，安心", "呼…忙起来了！", "缓存命中率不错嘛"]
    private static let calmLines = ["一切正常～", "今天也好好记账", "安安静静的", "要不要摸摸我"]
    private static let sleepLines = ["zzz…", "好安静，我先睡会儿"]

    func react(mood: PetMood, text: String, at now: Double) {
        self.mood = mood
        moodAt = now
        line = text
        sayAt = now
        if mood == .happy { hop = 1 }
    }

    func advance(dt: Double, busy: Int, now: Double) {
        idle = busy > 0 ? 0 : idle + dt
        hop = max(0, hop - dt * 1.8)
        if now - moodAt > 2.6 {
            mood = idle > 7 ? .asleep : (busy >= 4 ? .happy : .calm)
        }
        if now - sayAt > 4.2 {
            if Double.random(in: 0...1) < dt * 0.22 {
                let pool = mood == .asleep ? Self.sleepLines : (busy >= 4 ? Self.busyLines : Self.calmLines)
                line = pool.randomElement()
                sayAt = now
            } else {
                line = nil
            }
        }
        nextBlink -= dt
        if nextBlink <= 0 {
            blink = 0.16
            nextBlink = 1.8 + Double.random(in: 0...3.4)
        }
        blink = max(0, blink - dt)
    }
}
