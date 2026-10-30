import Foundation

struct ServiceInfo: Decodable {
    let name: String?
    let version: String?
    let pid: Int?
    let models: Int?
    let serves: String?
    let window: Bool?
}

struct UsageResponse: Decodable {
    let period: String?
    let calls: Int?
    let errors: Int?
    let retried: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let reasoning: Int?
    let cost: Double?
    let unpriced: Int?
    let credits: Double?
    let credited: Int?
    let timed: Int?
    let ttftMs: Int?
    let decodeMs: Int?
    let decodeOut: Int?
    let decodeN: Int?
    let bucket: String?
    let sessionCount: Int?
    let series: [UsagePoint]?
    let agents: [UsageAgent]?
    let models: [UsageModel]?
    let accounts: [UsageAccount]?
}

struct UsagePoint: Decodable {
    let label: String?
    let time: String?
    let calls: Int?
    let errors: Int?
    let retried: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let reasoning: Int?
    let cost: Double?
    let timed: Int?
}

struct UsageAgent: Decodable, Identifiable {
    let id: String?
    let name: String?
    let icon: String?
    let calls: Int?
    let errors: Int?
    let retried: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let cost: Double?
    let timed: Int?
    let ttftMs: Int?
    let decodeMs: Int?
    let decodeOut: Int?
}

struct UsageModel: Decodable, Identifiable {
    let id: String?
    let provider: String?
    let model: String?
    let host: String?
    let calls: Int?
    let errors: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let cost: Double?
    let timed: Int?
    let ttftMs: Int?
    let decodeMs: Int?
    let decodeOut: Int?
    let name: String?
    let sub: String?
    let icon: String?
}

struct UsageAccount: Decodable, Identifiable {
    let id: String?
    let provider: String?
    let account: String?
    let calls: Int?
    let errors: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cost: Double?
    let name: String?
    let sub: String?
    let icon: String?
}

struct QuotasResponse: Decodable {
    let data: [Quota]?
}

/// 设置里关掉监控的额度账号：壁纸（经 LocalOrigin 过滤）与应用内各视图都不显示。
enum QuotaWatch {
    static let hiddenKey = "magpie.quota.hidden"

    static func key(provider: String?, user: String?) -> String {
        "\(provider ?? "")|\(user ?? "")"
    }

    static var hidden: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
    }
}

struct Quota: Decodable, Identifiable {
    var id: String {
        [provider, name, user, plan].compactMap { $0 }.joined(separator: "|")
    }

    /// 设置里开关额度监控用的账号键：不含套餐，升降级后开关照旧。
    var watchKey: String { QuotaWatch.key(provider: provider, user: user) }

    let provider: String?
    let name: String?
    let kind: String?
    let plan: String?
    let user: String?
    let windows: [QuotaWindow]?
    let readAt: String?
    let until: String?
    let lastServedAt: String?
    let last: Bool?
}

struct QuotaWindow: Decodable, Identifiable {
    var id: String {
        [name, display, resetsAt].compactMap { $0 }.joined(separator: "|")
    }

    let name: String?
    let used: Double?
    let remaining: Double?
    let resetsAt: String?
    let display: String?
    let amount: Double?
    let limit: Double?
    let unit: String?
    let holdsWhy: String?
}

struct TraceResponse: Decodable {
    let seq: Int?
    let now: String?
    let routes: [TraceRoute]?
    let totals: TraceTotals?
}

struct TraceTotals: Decodable {
    let requests: Int?
    let rerouted: Int?
    let errors: Int?
}

/// 单次路由的分服务商 token 用量（trace.routes[].usage）。
struct RouteUsage: Decodable {
    let provider: String?
    let model: String?
    let input: Int?
    let out: Int?
    let cacheRead: Int?

    enum CodingKeys: String, CodingKey {
        case provider, model, out, cacheRead
        case input = "in"
    }
}

struct TraceRoute: Decodable, Identifiable {
    let seq: Int?
    let id: Int64?
    let time: String?
    let agent: String?
    let session: String?
    let model: String?
    let effort: String?
    let provider: String?
    let group: TraceGroup?
    let affinity: TraceAffinity?
    let order: [TraceCandidate]?
    let tries: [TraceTry]?
    let done: Bool?
    let status: Int?
    let ms: Int?
    let tokens: Int?
    let out: Int?
    let reasoning: Int?
    let ttft: Int?
    let flow: Int?
    let served: String?
    let usage: [RouteUsage]?
    let kind: String?
    let folder: String?
    let prompt: PromptBudget?
}

struct TraceGroup: Decodable {
    let id: String?
    let ref: String?
    let name: String?
    let routing: String?
    let affinity: String?
    let auto: Bool?
    let members: [String]?
}

struct TraceAffinity: Decodable {
    let mode: String?
    let turn: Int?
    let within: Bool?
    let last: String?
    let lastTurn: Int?
    let at: String?
    let cacheRead: Int?
    let kept: Bool?
    let why: String?
}

struct TraceCandidate: Decodable, Identifiable {
    let id: String?
    let provider: String?
    let name: String?
    let icon: String?
    let who: String?
    let kind: String?
    let agent: String?
    let plan: String?
    let model: String?
    let routing: String?
    let shared: Bool?
    let known: Bool?
    let used: Double?
    let renews: [String]?
    let pace: Double?
    let due: String?
    let rank: Int?
    let usedRenews: String?
    let amount: Double?
    let limit: Double?
    let unit: String?
}

struct TraceTry: Decodable, Identifiable {
    let id: String?
    let model: String?
    let effort: String?
    let start: String?
    let done: Bool?
    let status: Int?
    let ms: Int?
    let ttft: Int?
    let reasoningHidden: Bool?
    let flow: Int?
    let served: String?
    let tierServed: String?
    let net: TraceNet?
}

struct TraceNet: Decodable {
    let own: Double?
    let asks: Int?
    let pool: Double?
    let dns: Double?
    let connect: Double?
    let tls: Double?
    let send: Double?
    let wait: Double?
    let head: Double?
    let reused: Bool?
}

enum RouteTone: String {
    case teal
    case amber
    case blue
    case green
    case coral
    case neutral
}

struct RouteCandidateView: Identifiable {
    let id: String
    let providerName: String
    let account: String
    let plan: String?
    let usedPercent: Double
    let quotaDetail: String
    let stateText: String
    let isSelected: Bool
    let tone: RouteTone
}

struct RoutePresentation {
    let agentName: String
    let agentDetail: String
    let modelName: String
    let effort: String?
    let gatewayAddress: String
    let gatewayVersion: String?
    let isLive: Bool
    let isOnline: Bool
    let latency: String
    let selectedID: String?
    let candidates: [RouteCandidateView]
    let requests: Int
    let rerouted: Int
    let errors: Int
    // token 流量：优先取本次路由的 usage，无路由数据时回退到今日累计。
    var inputTokens: Int = 0
    var cacheTokens: Int = 0
    var outputTokens: Int = 0
    var tokensPerSec: Double = 0
    var tokenScopeText: String = ""
}

struct QuotaHighlight: Identifiable {
    let id: String
    let provider: String
    let account: String
    let windowName: String
    let usedPercent: Double
    let detail: String
    let resetText: String
    let isSelected: Bool
    let tone: RouteTone
}
