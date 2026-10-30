import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var service: ServiceInfo?
    @Published private(set) var usage: UsageResponse?
    /// 已按设置去掉关闭监控的账号；设置页的账号列表用 allQuotas。
    @Published private(set) var quotas: QuotasResponse?
    @Published private(set) var allQuotas: [Quota] = []
    @Published private(set) var trace: TraceResponse?
    @Published private(set) var isOnline = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var refreshGeneration = 0
    @Published private(set) var requests: UsageRequestsResponse?
    @Published private(set) var requestsUpdatedAt: Date?
    @Published private(set) var requestsError: String?
    @Published private(set) var isLoadingRequests = false
    @Published private(set) var traceUpdatedAt: Date?
    @Published private(set) var traceIsFresh = false
    @Published private(set) var usageIsFresh = false
    @Published private(set) var quotasIsFresh = false
    /// 30 天逐日用量，用来在本地按自然周、自然月汇总（接口只支持 today/7d/30d/all）。
    @Published private(set) var dailyUsage: UsageResponse?
    private var dailyUsageFetchedAt: Date?
    var isConsumptionVisible = false

    @Published var autoScreensaver: Bool {
        didSet { defaults.set(autoScreensaver, forKey: Keys.autoScreensaver) }
    }

    @Published var idleMinutes: Int {
        didSet { defaults.set(idleMinutes, forKey: Keys.idleMinutes) }
    }

    @Published var maskEmails: Bool {
        didSet { defaults.set(maskEmails, forKey: Keys.maskEmails) }
    }

    @Published var isWallpaperEnabled: Bool {
        didSet { defaults.set(isWallpaperEnabled, forKey: Keys.wallpaperEnabled) }
    }

    /// 桌面态右侧要让开的一列文件夹宽度（点）。全屏时归零，画面顶满两边。
    @Published var wallpaperRightInset: Int {
        didSet { defaults.set(wallpaperRightInset, forKey: Keys.wallpaperRightInset) }
    }

    @Published var marketBarEnabled: Bool {
        didSet { defaults.set(marketBarEnabled, forKey: Keys.marketBarEnabled) }
    }

    /// 行情里关掉的品种代码（MarketFeed 直接读同一个 defaults 键）。
    @Published var hiddenMarkets: Set<String> {
        didSet { defaults.set(Array(hiddenMarkets).sorted(), forKey: MarketFeed.hiddenKey) }
    }

    /// 关掉额度监控的账号（Quota.watchKey）。
    @Published var hiddenQuotas: Set<String> {
        didSet {
            defaults.set(Array(hiddenQuotas).sorted(), forKey: QuotaWatch.hiddenKey)
            applyQuotaFilter()
        }
    }

    @Published var isScreensaverActive = false

    private let api: MagpieAPI
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private let refreshInterval: UInt64 = 4_000_000_000

    init(
        api: MagpieAPI = MagpieAPI(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.defaults = defaults

        let savedAutoScreensaver = defaults.object(forKey: Keys.autoScreensaver) as? Bool
        let savedIdleMinutes = defaults.object(forKey: Keys.idleMinutes) as? Int
        let savedMaskEmails = defaults.object(forKey: Keys.maskEmails) as? Bool
        let savedWallpaper = defaults.object(forKey: Keys.wallpaperEnabled) as? Bool
        let savedRightInset = defaults.object(forKey: Keys.wallpaperRightInset) as? Int
        let savedMarketBar = defaults.object(forKey: Keys.marketBarEnabled) as? Bool

        autoScreensaver = savedAutoScreensaver ?? false
        idleMinutes = savedIdleMinutes ?? 5
        maskEmails = savedMaskEmails ?? true
        isWallpaperEnabled = savedWallpaper ?? true
        wallpaperRightInset = savedRightInset ?? 120
        marketBarEnabled = savedMarketBar ?? true
        hiddenMarkets = Set(defaults.stringArray(forKey: MarketFeed.hiddenKey) ?? [])
        hiddenQuotas = Set(defaults.stringArray(forKey: QuotaWatch.hiddenKey) ?? [])
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: self.refreshInterval)
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Magpie 更新/重启可能让并行请求跨越两个进程：先后各取一次服务身份，
        // 身份变化时丢弃这一批额度与用量，避免把旧额度写进新进程的状态。
        let beforeService = try? await api.service()
        async let usageTask = try? api.usage()
        async let quotasTask = try? api.quotas()
        async let traceTask = try? api.trace()

        let (newUsage, newQuotas, newTrace) = await (
            usageTask,
            quotasTask,
            traceTask
        )
        let afterService = try? await api.service()

        if let beforeService, let afterService,
           Self.gatewayIdentity(beforeService) != Self.gatewayIdentity(afterService) {
            service = afterService
            traceIsFresh = false
            usageIsFresh = false
            quotasIsFresh = false
            isOnline = true
            lastUpdated = Date()
            refreshGeneration &+= 1
            return
        }

        let newService = afterService ?? beforeService

        if let newService {
            service = newService
        }
        if let newUsage {
            usage = newUsage
        }
        if let newQuotas {
            allQuotas = newQuotas.data ?? []
            applyQuotaFilter()
        }
        if let newTrace {
            trace = newTrace
            traceUpdatedAt = Date()
        }
        traceIsFresh = newTrace != nil
        usageIsFresh = newUsage != nil
        quotasIsFresh = newQuotas != nil

        let connected = newService != nil || newUsage != nil || newQuotas != nil || newTrace != nil
        isOnline = connected
        if connected {
            lastUpdated = Date()
            lastError = nil
            refreshGeneration &+= 1
        } else {
            lastError = "无法连接 127.0.0.1:3425，请确认 Magpie 正在运行"
            refreshGeneration &+= 1
        }
        if isWallpaperEnabled || isConsumptionVisible { await refreshConsumption() }
        if connected, isWallpaperEnabled, Date().timeIntervalSince(dailyUsageFetchedAt ?? .distantPast) > 60 {
            if let daily = try? await api.usage(period: "30d") {
                dailyUsage = daily
                dailyUsageFetchedAt = Date()
            }
        }
    }

    private func applyQuotaFilter() {
        quotas = QuotasResponse(data: allQuotas.filter { !hiddenQuotas.contains($0.watchKey) })
    }

    private static func gatewayIdentity(_ service: ServiceInfo) -> String {
        "\(service.pid.map(String.init) ?? "?")|\(service.version ?? "?")"
    }

    func refreshConsumption() async {
        guard !isLoadingRequests else { return }
        isLoadingRequests = true
        defer { isLoadingRequests = false }
        do {
            requests = try await api.requests()
            requestsUpdatedAt = Date()
            requestsError = nil
        } catch {
            requestsError = "请求账本暂不可用，保留上次记录；仍可查看路由数据。"
        }
    }

    var consumptionRecords: [ConsumptionRecord] {
        ConsumptionRecord.merge(trace: trace, ledger: requests)
    }

    var latestRoute: TraceRoute? {
        trace?.routes?.max { lhs, rhs in
            (lhs.id ?? 0) < (rhs.id ?? 0)
        }
    }

    var todayCalls: Int {
        usage?.calls ?? trace?.totals?.requests ?? 0
    }

    var cacheHitRate: Double {
        let cache = Double(usage?.cacheRead ?? 0)
        let input = Double(usage?.input ?? 0)
        guard cache + input > 0 else { return 0 }
        return cache / (cache + input) * 100
    }

    var routePresentation: RoutePresentation {
        let route = latestRoute
        let selectedID = route?.tries?.last?.id ?? route?.order?.first?.id
        let routeTime = DateParser.parse(route?.time)
        let live = isOnline && (routeTime.map { Date().timeIntervalSince($0) < 120 } ?? false)

        if let route, let order = route.order, !order.isEmpty {
            let candidates = order.prefix(4).enumerated().map { index, candidate in
                let identifier = candidate.id ?? "candidate-\(index)"
                let used = candidateUsedPercent(candidate)
                let detail: String
                if let amount = candidate.amount, let limit = candidate.limit, limit > 0 {
                    detail = "\(Fmt.compact(amount)) / \(Fmt.compact(limit))"
                } else {
                detail = "已用 \(Fmt.percent(used))"
                }
                return RouteCandidateView(
                    id: identifier,
                    providerName: candidate.name ?? Fmt.providerName(candidate.provider),
                    account: Fmt.maskAccount(candidate.who, masked: maskEmails),
                    plan: candidate.plan,
                    usedPercent: used,
                    quotaDetail: detail,
                    stateText: identifier == selectedID
                        ? "当前路由"
                        : (used >= 99.9 ? "额度耗尽" : "候补"),
                    isSelected: identifier == selectedID,
                    tone: tone(for: candidate.provider)
                )
            }

            let selectedTry = route.tries?.last
            // token 流向优先绑定本次路由的真实用量，路由没有数据时回退今日累计。
            let routeUsages = route.usage ?? []
            let routeInput = routeUsages.reduce(0) { $0 + ($1.input ?? 0) }
            let routeCache = routeUsages.reduce(0) { $0 + ($1.cacheRead ?? 0) }
            let routeOutput = routeUsages.reduce(0) { $0 + ($1.out ?? 0) }
            let hasRouteUsage = routeUsages.contains {
                ($0.input ?? 0) + ($0.out ?? 0) + ($0.cacheRead ?? 0) > 0
            }
            return RoutePresentation(
                agentName: Fmt.agentName(route.agent),
                agentDetail: route.affinity?.kept == true ? "缓存亲和" : "智能路由",
                modelName: route.group?.name ?? Fmt.modelName(route.model),
                effort: route.effort,
                gatewayAddress: "127.0.0.1:3425",
                gatewayVersion: service?.version,
                isLive: live,
                isOnline: isOnline,
                latency: Fmt.latency(selectedTry?.ms ?? route.ms),
                selectedID: selectedID,
                candidates: candidates,
                requests: trace?.totals?.requests ?? todayCalls,
                rerouted: trace?.totals?.rerouted ?? usage?.retried ?? 0,
                errors: trace?.totals?.errors ?? usage?.errors ?? 0,
                inputTokens: hasRouteUsage ? routeInput : (usage?.input ?? 0),
                cacheTokens: hasRouteUsage ? routeCache : (usage?.cacheRead ?? 0),
                outputTokens: hasRouteUsage ? routeOutput : (usage?.output ?? 0),
                tokensPerSec: Fmt.tokensPerSec(usage?.decodeOut, decodeMilliseconds: usage?.decodeMs),
                tokenScopeText: hasRouteUsage ? "本次路由 · \(route.group?.name ?? Fmt.modelName(route.model))" : "今日累计"
            )
        }

        let candidates = quotaCandidates()
        return RoutePresentation(
            agentName: Fmt.agentName(usage?.agents?.first?.id),
            agentDetail: isOnline ? "等待下一次请求" : "网关离线",
            modelName: "智能路由",
            effort: nil,
            gatewayAddress: "127.0.0.1:3425",
            gatewayVersion: service?.version,
            isLive: false,
            isOnline: isOnline,
            latency: "—",
            selectedID: candidates.first?.id,
            candidates: candidates,
            requests: trace?.totals?.requests ?? todayCalls,
            rerouted: trace?.totals?.rerouted ?? usage?.retried ?? 0,
            errors: trace?.totals?.errors ?? usage?.errors ?? 0,
            inputTokens: usage?.input ?? 0,
            cacheTokens: usage?.cacheRead ?? 0,
            outputTokens: usage?.output ?? 0,
            tokensPerSec: Fmt.tokensPerSec(usage?.decodeOut, decodeMilliseconds: usage?.decodeMs),
            tokenScopeText: "今日累计"
        )
    }

    var quotaHighlights: [QuotaHighlight] {
        let selected = selectedQuota
        var all = (quotas?.data ?? []).compactMap { quota -> QuotaHighlight? in
            guard let window = strongestWindow(in: quota) else { return nil }
            let used = quotaWindowPercent(window)
            return QuotaHighlight(
                id: quota.id,
                provider: quota.name ?? Fmt.providerName(quota.provider),
                account: Fmt.maskAccount(quota.user, masked: maskEmails),
                windowName: window.name ?? "Quota",
                usedPercent: used,
                detail: Fmt.quotaDetail(window, maskedAccount: Fmt.maskAccount(quota.user, masked: maskEmails)),
                resetText: Fmt.resetText(window.resetsAt),
                isSelected: quota.id == selected?.id,
                tone: tone(for: quota.provider)
            )
        }

        all.sort {
            if $0.isSelected != $1.isSelected {
                return $0.isSelected
            }
            if $0.usedPercent != $1.usedPercent {
                return $0.usedPercent > $1.usedPercent
            }
            return $0.provider < $1.provider
        }
        return Array(all.prefix(2))
    }

    var selectedQuota: Quota? {
        let candidate = routePresentation.candidates.first(where: \.isSelected)
        if let candidate {
            let provider = providerID(from: candidate.providerName)
            let account = candidate.account
            if let match = quotas?.data?.first(where: {
                $0.provider == provider && Fmt.maskAccount($0.user, masked: maskEmails) == account
            }) {
                return match
            }
        }
        return quotas?.data?.first(where: { $0.last == true })
            ?? quotas?.data?.first(where: { $0.provider == "codex" })
            ?? quotas?.data?.first
    }

    var selectedAccountLine: String {
        guard let selected = selectedQuota else {
            return "等待账号额度"
        }
        let account = Fmt.maskAccount(selected.user, masked: maskEmails)
        return "\(selected.name ?? Fmt.providerName(selected.provider)) · \(account)"
    }

    private func quotaCandidates() -> [RouteCandidateView] {
        let values = (quotas?.data ?? []).prefix(4).enumerated().map { index, quota in
            let window = strongestWindow(in: quota)
            let used = quotaWindowPercent(window)
            return RouteCandidateView(
                id: quota.id,
                providerName: quota.name ?? Fmt.providerName(quota.provider),
                account: Fmt.maskAccount(quota.user, masked: maskEmails),
                plan: quota.plan,
                usedPercent: used,
                quotaDetail: Fmt.quotaDetail(
                    window,
                    maskedAccount: Fmt.maskAccount(quota.user, masked: maskEmails)
                ),
                stateText: index == 0 ? "最近使用" : (used >= 99.9 ? "额度耗尽" : "可用"),
                isSelected: index == 0,
                tone: tone(for: quota.provider)
            )
        }
        return Array(values)
    }

    private func strongestWindow(in quota: Quota) -> QuotaWindow? {
        quota.windows?.max {
            quotaWindowPercent($0) < quotaWindowPercent($1)
        } ?? quota.windows?.first
    }

    private func quotaWindowPercent(_ window: QuotaWindow?) -> Double {
        guard let window else { return 0 }
        if let amount = window.amount, let limit = window.limit, limit > 0 {
            return min(100, max(0, amount / limit * 100))
        }
        return min(100, max(0, window.used ?? 0))
    }

    private func candidateUsedPercent(_ candidate: TraceCandidate) -> Double {
        if let amount = candidate.amount, let limit = candidate.limit, limit > 0 {
            return min(100, max(0, amount / limit * 100))
        }
        return min(100, max(0, candidate.used ?? 0))
    }

    private func tone(for provider: String?) -> RouteTone {
        switch provider?.lowercased() {
        case "codex":
            return .teal
        case "workbuddy-ai", "workbuddy":
            return .amber
        case "cursor", "claude":
            return .blue
        case "zcode":
            return .green
        default:
            return .neutral
        }
    }

    private func providerID(from name: String) -> String? {
        switch name.lowercased() {
        case "codex":
            return "codex"
        case "workbuddy ai":
            return "workbuddy-ai"
        case "workbuddy":
            return "workbuddy"
        case "zcode":
            return "zcode"
        case "cursor":
            return "cursor"
        case "claude":
            return "claude"
        default:
            return nil
        }
    }
}

private enum Keys {
    static let autoScreensaver = "magpie.screensaver.auto"
    static let idleMinutes = "magpie.screensaver.idleMinutes"
    static let maskEmails = "magpie.privacy.maskEmails"
    static let wallpaperEnabled = "magpie.wallpaper.enabled"
    static let wallpaperRightInset = "magpie.wallpaper.rightInset"
    static let marketBarEnabled = "magpie.marketBar.enabled"
}
