import SwiftUI

/// 壁纸 / 屏保的多 agent 路由舞台。
/// 左侧智能体，中央 Magpie，右侧模型。包只在真实 trace 处于
/// incoming / outbound / returning 时沿曲线移动；没有路由则节点等待、链路为虚线。
struct WallpaperRouteScene: View {
    let board: WallpaperFlowBoard
    var immersive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(spacing: CGFloat(immersive ? 12 : 8)) {
            directionCaption
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let active = board.flows.filter { $0.stage != .waiting }.count
        if board.agents.isEmpty {
            return "路由舞台：等待智能体。Magpie \(board.isOnline ? "在线" : "离线")"
        }
        let names = board.agents.map(\.name).joined(separator: "、")
        return "路由舞台：\(names) 经由 Magpie 网关。当前 \(active) 条真实路由在传输"
    }

    private var directionCaption: some View {
        HStack(spacing: CGFloat(immersive ? 14 : 10)) {
            captionChip("智能体", tint: palette.seaBright)
            Image(systemName: "arrow.right")
                .font(.system(size: CGFloat(immersive ? 11 : 9), weight: .bold))
                .foregroundStyle(palette.seaBright.opacity(0.8))
            captionChip("Magpie 网关", tint: palette.sea)
            Image(systemName: "arrow.right")
                .font(.system(size: CGFloat(immersive ? 11 : 9), weight: .bold))
                .foregroundStyle(palette.blue.opacity(0.85))
            captionChip("模型", tint: palette.blue)
            Image(systemName: "arrow.left")
                .font(.system(size: CGFloat(immersive ? 11 : 9), weight: .bold))
                .foregroundStyle(palette.amber.opacity(0.9))
            captionChip("响应回流", tint: palette.amber)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func captionChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.custom(WatchTheme.displayCNFont, size: CGFloat(immersive ? 12 : 10)).weight(.medium))
            .tracking(0.6)
            .foregroundStyle(tint)
    }

    private var stage: some View {
        GeometryReader { proxy in
            let layout = StageLayout(size: proxy.size, board: board, immersive: immersive)
            ZStack {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30, paused: reduceMotion)) { timeline in
                    Canvas { context, size in
                        drawStage(
                            context: &context,
                            layout: layout.fitted(to: size),
                            elapsed: timeline.date.timeIntervalSinceReferenceDate,
                            motion: !reduceMotion
                        )
                    }
                }
                nodeLayer(layout)
            }
        }
    }

    private func nodeLayer(_ layout: StageLayout) -> some View {
        ZStack {
            ForEach(board.agents) { agent in
                if let point = layout.agents[agent.id] {
                    FlowNodeCard(
                        symbol: agent.symbol,
                        title: agent.name,
                        detail: agent.calls > 0 ? "\(Fmt.compact(agent.calls)) 次" : "今日",
                        caption: agent.stage.label,
                        tint: palette.color(for: agent.stage),
                        live: agent.stage != .waiting,
                        immersive: immersive
                    )
                    .position(point)
                }
            }

            GatewayOrb(
                version: board.gatewayVersion,
                online: board.isOnline,
                live: board.flows.contains { $0.stage != .waiting },
                immersive: immersive
            )
            .position(layout.hub)

            ForEach(board.destinations) { destination in
                if let point = layout.destinations[destination.id] {
                    FlowNodeCard(
                        symbol: destination.symbol,
                        title: destination.modelName,
                        detail: destination.providerName,
                        caption: destination.stage.label,
                        tint: palette.color(for: destination.stage),
                        live: destination.stage != .waiting,
                        immersive: immersive
                    )
                    .position(point)
                }
            }

            if board.agents.isEmpty && board.destinations.isEmpty {
                Text(board.isOnline ? "等待智能体接入" : "网关离线，保留上一帧结构")
                    .font(.custom(WatchTheme.displayCNFont, size: CGFloat(immersive ? 16 : 13)))
                    .foregroundStyle(palette.mist)
                    .position(x: layout.hub.x, y: layout.hub.y + layout.hubRadius + CGFloat(78))
            }
        }
    }

    private func drawStage(
        context: inout GraphicsContext,
        layout: StageLayout,
        elapsed: TimeInterval,
        motion: Bool
    ) {
        let glowRadius = layout.hubRadius * CGFloat(immersive ? 3.4 : 2.8)
        context.fill(
            Path(ellipseIn: CGRect(
                x: layout.hub.x - glowRadius,
                y: layout.hub.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )),
            with: .radialGradient(
                Gradient(colors: [palette.sea.opacity(immersive ? 0.16 : 0.10), .clear]),
                center: layout.hub,
                startRadius: layout.hubRadius * 0.4,
                endRadius: glowRadius
            )
        )

        for agent in board.agents {
            guard let origin = layout.agents[agent.id] else { continue }
            let from = CGPoint(x: origin.x + layout.cardWidth * 0.46, y: origin.y)
            let to = CGPoint(x: layout.hub.x - layout.hubRadius * 0.78, y: layout.hub.y)
            let flow = board.flows.first { $0.agentID == agent.id }
            let stage = flow?.stage ?? .waiting
            let link = cubic(from: from, to: to, bend: (from.y - to.y) * 0.22)
            strokeLink(context: &context, link: link, stage: stage, dim: stage == .outbound || stage == .returning)
            if motion, stage == .incoming || stage == .returning {
                let tokens = stage == .returning ? (flow?.responseTokens ?? 0) : (flow?.requestTokens ?? 0)
                drawPackets(
                    context: &context,
                    link: link,
                    elapsed: elapsed,
                    color: palette.color(for: stage),
                    count: packetCount(tokens),
                    reverse: stage == .returning,
                    seed: seed(agent.id)
                )
            }
        }

        for destination in board.destinations {
            guard let origin = layout.destinations[destination.id] else { continue }
            let from = CGPoint(x: layout.hub.x + layout.hubRadius * 0.78, y: layout.hub.y)
            let to = CGPoint(x: origin.x - layout.cardWidth * 0.46, y: origin.y)
            let matching = board.flows.filter { $0.destinationID == destination.id }
            let stage = dominant(matching.map(\.stage))
            let link = cubic(from: from, to: to, bend: (to.y - from.y) * 0.2)
            strokeLink(context: &context, link: link, stage: stage, dim: stage == .incoming)
            if motion {
                for flow in matching where flow.stage == .outbound || flow.stage == .returning {
                    let tokens = flow.stage == .returning ? flow.responseTokens : flow.requestTokens
                    drawPackets(
                        context: &context,
                        link: link,
                        elapsed: elapsed,
                        color: palette.color(for: flow.stage),
                        count: packetCount(tokens),
                        reverse: flow.stage == .returning,
                        seed: seed(flow.id)
                    )
                }
            }
        }
    }

    private func strokeLink(
        context: inout GraphicsContext,
        link: CubicLink,
        stage: WallpaperHopStage,
        dim: Bool
    ) {
        let color = palette.color(for: stage)
        let active = stage != .waiting
        let glowWidth = CGFloat(immersive ? 14 : 9)
        let coreWidth = CGFloat(immersive ? 2.4 : 1.6)
        if active {
            context.stroke(
                link.path,
                with: .color(color.opacity(dim ? 0.10 : 0.20)),
                style: StrokeStyle(lineWidth: glowWidth, lineCap: .round)
            )
        }
        let dashes: [CGFloat] = active ? [] : [5, 7]
        context.stroke(
            link.path,
            with: .color(color.opacity(active ? (dim ? 0.45 : 0.92) : 0.28)),
            style: StrokeStyle(
                lineWidth: active ? coreWidth : 1.1,
                lineCap: .round,
                dash: dashes
            )
        )
    }

    private func drawPackets(
        context: inout GraphicsContext,
        link: CubicLink,
        elapsed: TimeInterval,
        color: Color,
        count: Int,
        reverse: Bool,
        seed: Double
    ) {
        let total = max(1, count)
        for index in 0..<total {
            let shift = Double(index) / Double(total)
            var progress = (elapsed / 2.4 + shift + seed.truncatingRemainder(dividingBy: 1))
                .truncatingRemainder(dividingBy: 1)
            if reverse {
                progress = 1 - progress
            }
            let fade = sin(progress * .pi)
            for step in 0...3 {
                let behind = reverse ? progress + Double(step) * 0.035 : progress - Double(step) * 0.035
                guard behind > 0.02, behind < 0.98 else { continue }
                let point = link.point(behind)
                let falloff = CGFloat(4 - step) / 4
                let radius = CGFloat(immersive ? 4.6 : 3.3) * falloff
                if step == 0 {
                    let bloom = radius * 3.2
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - bloom, y: point.y - bloom, width: bloom * 2, height: bloom * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.40 * fade), .clear]),
                            center: point,
                            startRadius: 0,
                            endRadius: bloom
                        )
                    )
                }
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity((0.35 + 0.65 * fade) * Double(falloff)))
                )
            }
        }
    }

    private func dominant(_ stages: [WallpaperHopStage]) -> WallpaperHopStage {
        if stages.contains(.returning) { return .returning }
        if stages.contains(.outbound) { return .outbound }
        if stages.contains(.incoming) { return .incoming }
        return .waiting
    }

    private func seed(_ raw: String) -> Double {
        var hash = 0
        for scalar in raw.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return Double(abs(hash % 97)) / 97
    }

    private func packetCount(_ tokens: Int) -> Int {
        guard tokens > 0 else { return 1 }
        let span = min(1, log10(1 + Double(tokens)) / 7)
        return max(1, min(3, Int((1 + 2 * span).rounded())))
    }

    private func cubic(from: CGPoint, to: CGPoint, bend: CGFloat) -> CubicLink {
        let distance = to.x - from.x
        return CubicLink(
            p0: from,
            p1: CGPoint(x: from.x + distance * 0.42, y: from.y + bend),
            p2: CGPoint(x: to.x - distance * 0.38, y: to.y - bend * 0.35),
            p3: to
        )
    }
}

private struct CubicLink {
    var p0: CGPoint
    var p1: CGPoint
    var p2: CGPoint
    var p3: CGPoint

    var path: Path {
        var path = Path()
        path.move(to: p0)
        path.addCurve(to: p3, control1: p1, control2: p2)
        return path
    }

    func point(_ progress: Double) -> CGPoint {
        let t = CGFloat(min(1, max(0, progress)))
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

private struct StageLayout {
    var size: CGSize
    var agents: [String: CGPoint]
    var destinations: [String: CGPoint]
    var hub: CGPoint
    var hubRadius: CGFloat
    var cardWidth: CGFloat

    init(size: CGSize, board: WallpaperFlowBoard, immersive: Bool) {
        self.size = size
        cardWidth = CGFloat(immersive ? 214 : 168)
        hubRadius = CGFloat(immersive ? 78 : 58)
        hub = CGPoint(x: size.width * 0.50, y: size.height * 0.50)
        let inset = max(cardWidth * 0.62, CGFloat(108))
        let agentX = min(max(size.width * 0.20, inset), size.width * 0.30)
        agents = Self.column(
            ids: board.agents.map(\.id),
            x: agentX,
            height: size.height
        )
        destinations = Self.column(
            ids: board.destinations.map(\.id),
            x: size.width - agentX,
            height: size.height
        )
    }

    func fitted(to size: CGSize) -> StageLayout {
        self
    }

    private static func column(ids: [String], x: CGFloat, height: CGFloat) -> [String: CGPoint] {
        guard !ids.isEmpty else { return [:] }
        if ids.count == 1 {
            return [ids[0]: CGPoint(x: x, y: height * 0.50)]
        }
        let top = height * 0.16
        let bottom = height * 0.84
        var points: [String: CGPoint] = [:]
        for (index, id) in ids.enumerated() {
            let t = CGFloat(index) / CGFloat(ids.count - 1)
            points[id] = CGPoint(x: x, y: top + (bottom - top) * t)
        }
        return points
    }
}

private struct FlowNodeCard: View {
    let symbol: String
    let title: String
    let detail: String
    let caption: String
    let tint: Color
    let live: Bool
    var immersive: Bool

    @Environment(\.watchPalette) private var palette

    var body: some View {
        HStack(spacing: CGFloat(immersive ? 12 : 9)) {
            ZStack {
                Circle()
                    .fill(tint.opacity(live ? 0.18 : 0.08))
                Image(systemName: symbol)
                    .font(.system(size: CGFloat(immersive ? 18 : 14), weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: CGFloat(immersive ? 42 : 34), height: CGFloat(immersive ? 42 : 34))

            VStack(alignment: .leading, spacing: CGFloat(immersive ? 3 : 2)) {
                Text(title)
                    .font(.custom(WatchTheme.displayCNFont, size: CGFloat(immersive ? 16 : 13)).weight(.semibold))
                    .foregroundStyle(palette.ice)
                    .lineLimit(1)
                Text(detail)
                    .font(.custom(WatchTheme.monoFont, size: CGFloat(immersive ? 11 : 9)))
                    .foregroundStyle(palette.mist)
                    .lineLimit(1)
                Text(caption)
                    .font(.custom(WatchTheme.displayCNFont, size: CGFloat(immersive ? 11 : 9)).weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CGFloat(immersive ? 14 : 11))
        .padding(.vertical, CGFloat(immersive ? 12 : 9))
        .frame(width: CGFloat(immersive ? 214 : 168), alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CGFloat(immersive ? 16 : 13), style: .continuous)
                .fill(palette.abyss.opacity(live ? 0.88 : 0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(immersive ? 16 : 13), style: .continuous)
                .strokeBorder(tint.opacity(live ? 0.85 : 0.28), lineWidth: CGFloat(live ? 1.2 : 0.7))
        }
        .shadow(color: live ? tint.opacity(0.18) : .clear, radius: 16, y: 4)
    }
}

private struct GatewayOrb: View {
    let version: String?
    let online: Bool
    let live: Bool
    var immersive: Bool

    @Environment(\.watchPalette) private var palette

    var body: some View {
        let diameter = CGFloat(immersive ? 156 : 118)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.deep, palette.abyss.opacity(0.96)],
                        center: .center,
                        startRadius: 4,
                        endRadius: diameter * 0.7
                    )
                )
            Circle()
                .strokeBorder(palette.seaBright.opacity(live ? 0.85 : 0.28), lineWidth: 1.2)
            Circle()
                .strokeBorder(palette.sea.opacity(0.16), lineWidth: CGFloat(immersive ? 16 : 12))
                .padding(CGFloat(immersive ? 10 : 8))
            VStack(spacing: CGFloat(immersive ? 6 : 4)) {
                BrandMark(size: CGFloat(immersive ? 36 : 26))
                Text("MAGPIE")
                    .font(.custom(WatchTheme.displayFont, size: CGFloat(immersive ? 26 : 20)).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.ice)
                Text(online ? "127.0.0.1:3425" : "网关离线")
                    .font(.custom(WatchTheme.monoFont, size: CGFloat(immersive ? 10 : 8)))
                    .foregroundStyle(online ? palette.seaBright : palette.coral)
                Text(live ? "路由传输中" : (version.map { "v\($0)" } ?? "本地网关"))
                    .font(.custom(WatchTheme.displayCNFont, size: CGFloat(immersive ? 11 : 9)).weight(.medium))
                    .foregroundStyle(live ? palette.seaBright : palette.mist)
                    .lineLimit(1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: palette.sea.opacity(live ? 0.22 : 0.06), radius: 28)
    }
}

// MARK: - 数据

enum WallpaperHopStage: String, Equatable {
    case waiting
    case incoming
    case outbound
    case returning

    var label: String {
        switch self {
        case .waiting: return "等待"
        case .incoming: return "请求进入"
        case .outbound: return "发往模型"
        case .returning: return "响应回流"
        }
    }
}

struct WallpaperAgentSlot: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let calls: Int
    let stage: WallpaperHopStage
}

struct WallpaperDestinationSlot: Identifiable, Equatable {
    let id: String
    let modelName: String
    let providerName: String
    let symbol: String
    let calls: Int
    let stage: WallpaperHopStage
}

struct WallpaperPacketFlow: Identifiable, Equatable {
    let id: String
    let agentID: String
    let destinationID: String
    let stage: WallpaperHopStage
    let requestTokens: Int
    let responseTokens: Int
}

struct WallpaperFlowBoard: Equatable {
    var agents: [WallpaperAgentSlot]
    var destinations: [WallpaperDestinationSlot]
    var flows: [WallpaperPacketFlow]
    var isOnline: Bool
    var gatewayVersion: String?

    static let empty = WallpaperFlowBoard(
        agents: [],
        destinations: [],
        flows: [],
        isOnline: false,
        gatewayVersion: nil
    )
}

enum WallpaperBoardBuilder {
    private static let agentLimit = 4
    private static let destinationLimit = 4
    private static let liveWindow: TimeInterval = 90
    private static let returnWindow: TimeInterval = 22

    static func make(
        usage: UsageResponse?,
        trace: TraceResponse?,
        service: ServiceInfo?,
        isOnline: Bool,
        now: Date = Date()
    ) -> WallpaperFlowBoard {
        var agentDrafts: [String: DraftAgent] = [:]
        for agent in usage?.agents ?? [] {
            let id = key(agent.id ?? agent.name)
            guard !id.isEmpty else { continue }
            agentDrafts[id] = DraftAgent(
                id: id,
                name: Fmt.agentName(agent.name ?? agent.id),
                symbol: symbolForAgent(agent.id ?? agent.name, hint: agent.icon),
                calls: agent.calls ?? 0,
                stage: .waiting,
                routeID: -1
            )
        }

        var destinationDrafts: [String: DraftDestination] = [:]
        var flows: [WallpaperPacketFlow] = []
        let routes = (trace?.routes ?? []).sorted { ($0.id ?? 0) > ($1.id ?? 0) }

        for route in routes {
            let stage = classify(route, now: now)
            guard stage != .waiting else { continue }
            let agentID = key(route.agent)
            let destinationID = destinationKey(provider: route.provider, model: route.model)
            guard !agentID.isEmpty, !destinationID.isEmpty else { continue }
            if agentDrafts[agentID]?.routeID ?? -1 >= (route.id ?? 0), agentDrafts[agentID]?.stage != .waiting {
                continue
            }
            if agentDrafts[agentID] == nil {
                agentDrafts[agentID] = DraftAgent(
                    id: agentID,
                    name: Fmt.agentName(route.agent),
                    symbol: symbolForAgent(route.agent, hint: nil),
                    calls: 0,
                    stage: stage,
                    routeID: route.id ?? 0
                )
            } else {
                agentDrafts[agentID]?.stage = stage
                agentDrafts[agentID]?.routeID = route.id ?? 0
            }

            let tokens = tokenCounts(route)
            let modelMatch = (usage?.models ?? []).first {
                key($0.model) == key(route.model) || key($0.name) == key(route.model)
            }
            let previous = destinationDrafts[destinationID]
            let routeID = route.id ?? 0
            if previous == nil || previous?.stage == .waiting || (previous?.routeID ?? -1) < routeID {
                destinationDrafts[destinationID] = DraftDestination(
                    id: destinationID,
                    modelName: Fmt.modelName(route.group?.name ?? route.model),
                    providerName: Fmt.providerName(route.provider ?? modelMatch?.provider),
                    symbol: symbolForProvider(route.provider ?? modelMatch?.provider, hint: modelMatch?.icon),
                    calls: max(previous?.calls ?? 0, modelMatch?.calls ?? 0),
                    stage: stage,
                    routeID: routeID
                )
            }
            flows.removeAll { $0.agentID == agentID }
            flows.append(
                WallpaperPacketFlow(
                    id: "route-\(route.id ?? 0)",
                    agentID: agentID,
                    destinationID: destinationID,
                    stage: stage,
                    requestTokens: tokens.request,
                    responseTokens: tokens.response
                )
            )
        }

        if destinationDrafts.count < destinationLimit {
            let rankedModels = (usage?.models ?? []).sorted { ($0.calls ?? 0) > ($1.calls ?? 0) }
            for model in rankedModels where destinationDrafts.count < destinationLimit {
                let id = destinationKey(provider: model.provider, model: model.model ?? model.name)
                guard !id.isEmpty, destinationDrafts[id] == nil else { continue }
                destinationDrafts[id] = DraftDestination(
                    id: id,
                    modelName: Fmt.modelName(model.name ?? model.model),
                    providerName: Fmt.providerName(model.provider),
                    symbol: symbolForProvider(model.provider, hint: model.icon),
                    calls: model.calls ?? 0,
                    stage: .waiting,
                    routeID: -1
                )
            }
        }

        if destinationDrafts.isEmpty, !agentDrafts.isEmpty {
            destinationDrafts["waiting|model"] = DraftDestination(
                id: "waiting|model",
                modelName: "等待模型",
                providerName: "尚未路由",
                symbol: "cpu",
                calls: 0,
                stage: .waiting,
                routeID: -1
            )
        }
        if agentDrafts.isEmpty, !destinationDrafts.isEmpty {
            agentDrafts["waiting|agent"] = DraftAgent(
                id: "waiting|agent",
                name: "等待智能体",
                symbol: "person.crop.circle",
                calls: 0,
                stage: .waiting,
                routeID: -1
            )
        }

        let agents = Array(agentDrafts.values)
            .sorted(by: newerFirst)
            .prefix(agentLimit)
        let keptAgentIDs = Set(agents.map(\.id))
        let destinations = Array(destinationDrafts.values)
            .sorted(by: newerDestination)
            .prefix(destinationLimit)
        let keptDestinationIDs = Set(destinations.map(\.id))
        let visibleFlows = flows.filter {
            keptAgentIDs.contains($0.agentID) && keptDestinationIDs.contains($0.destinationID)
        }
        let flowingAgents = Set(visibleFlows.map(\.agentID))
        var destinationStages: [String: WallpaperHopStage] = [:]
        for flow in visibleFlows {
            let current = destinationStages[flow.destinationID] ?? .waiting
            if rank(flow.stage) < rank(current) {
                destinationStages[flow.destinationID] = flow.stage
            }
        }

        return WallpaperFlowBoard(
            agents: agents.map { agent in
                WallpaperAgentSlot(
                    id: agent.id,
                    name: agent.name,
                    symbol: agent.symbol,
                    calls: agent.calls,
                    stage: flowingAgents.contains(agent.id) ? agent.stage : .waiting
                )
            },
            destinations: destinations.map { destination in
                WallpaperDestinationSlot(
                    id: destination.id,
                    modelName: destination.modelName,
                    providerName: destination.providerName,
                    symbol: destination.symbol,
                    calls: destination.calls,
                    stage: destinationStages[destination.id] ?? .waiting
                )
            },
            flows: visibleFlows,
            isOnline: isOnline,
            gatewayVersion: service?.version
        )
    }

    private struct DraftAgent {
        var id: String
        var name: String
        var symbol: String
        var calls: Int
        var stage: WallpaperHopStage
        var routeID: Int64
    }

    private struct DraftDestination {
        var id: String
        var modelName: String
        var providerName: String
        var symbol: String
        var calls: Int
        var stage: WallpaperHopStage
        var routeID: Int64
    }

    private static func newerFirst(_ lhs: DraftAgent, _ rhs: DraftAgent) -> Bool {
        let left = rank(lhs.stage)
        let right = rank(rhs.stage)
        if left != right { return left < right }
        if lhs.routeID != rhs.routeID { return lhs.routeID > rhs.routeID }
        return lhs.calls > rhs.calls
    }

    private static func newerDestination(_ lhs: DraftDestination, _ rhs: DraftDestination) -> Bool {
        let left = rank(lhs.stage)
        let right = rank(rhs.stage)
        if left != right { return left < right }
        if lhs.routeID != rhs.routeID { return lhs.routeID > rhs.routeID }
        return lhs.calls > rhs.calls
    }

    private static func rank(_ stage: WallpaperHopStage) -> Int {
        switch stage {
        case .returning: return 0
        case .outbound: return 1
        case .incoming: return 2
        case .waiting: return 3
        }
    }

    private static func classify(_ route: TraceRoute, now: Date) -> WallpaperHopStage {
        guard let started = DateParser.parse(route.time) else { return .waiting }
        let age = now.timeIntervalSince(started)
        guard age >= -2, age < liveWindow else { return .waiting }
        if route.done == true {
            let latency = Double(max(0, route.ms ?? 0)) / 1000
            let sinceDone = age - latency
            if sinceDone < returnWindow { return .returning }
            return .waiting
        }
        if age < 1.4 { return .incoming }
        return .outbound
    }

    private static func tokenCounts(_ route: TraceRoute) -> (request: Int, response: Int) {
        let usages = route.usage ?? []
        let request = usages.reduce(0) { $0 + ($1.input ?? 0) + ($1.cacheRead ?? 0) }
        var response = usages.reduce(0) { $0 + ($1.out ?? 0) }
        if response == 0 {
            response = route.out ?? 0
        }
        return (request, response)
    }

    private static func key(_ raw: String?) -> String {
        guard let raw else { return "" }
        let pieces = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0 == " " || $0 == "_" || $0 == "-" }
            .map(String.init)
        return pieces.joined(separator: "-")
    }

    private static func destinationKey(provider: String?, model: String?) -> String {
        let providerKey = key(provider)
        let modelKey = key(model)
        if providerKey.isEmpty && modelKey.isEmpty { return "" }
        return "\(providerKey)|\(modelKey)"
    }

    private static func symbolForAgent(_ raw: String?, hint: String?) -> String {
        if let symbol = symbolHint(hint) {
            return symbol
        }
        switch key(raw) {
        case "claude-desktop", "claude-code", "claude":
            return "sparkles"
        case "codex":
            return "chevron.left.forwardslash.chevron.right"
        case "cursor":
            return "cursorarrow.rays"
        case "zcode":
            return "z.square.fill"
        case "workbuddy", "workbuddy-ai":
            return "person.2.fill"
        default:
            return "person.crop.circle"
        }
    }

    private static func symbolForProvider(_ raw: String?, hint: String?) -> String {
        if let symbol = symbolHint(hint) {
            return symbol
        }
        switch key(raw) {
        case "codex":
            return "circle.hexagongrid.fill"
        case "zcode":
            return "z.square.fill"
        case "workbuddy", "workbuddy-ai":
            return "person.2.fill"
        case "claude":
            return "sparkles"
        case "cursor":
            return "cursorarrow.rays"
        default:
            return "cpu"
        }
    }

    /// 只接受看起来像 SF Symbol 的图标名。文件名（如 claude.png）留给名称映射。
    private static func symbolHint(_ hint: String?) -> String? {
        guard let hint else { return nil }
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let isFile = [".png", ".jpg", ".jpeg", ".svg", ".webp", ".gif"].contains { lower.hasSuffix($0) }
        guard !isFile, trimmed.contains("."), !trimmed.contains("/"), !trimmed.contains(" ") else { return nil }
        return trimmed
    }
}

private extension WatchPalette {
    func color(for stage: WallpaperHopStage) -> Color {
        switch stage {
        case .waiting: return mist
        case .incoming: return seaBright
        case .outbound: return blue
        case .returning: return amber
        }
    }
}
