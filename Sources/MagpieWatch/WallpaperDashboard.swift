import Foundation

/// 动态壁纸上的看板数据：今日/本周/本月 Token、效率、逐小时节奏与排行。
/// 全部来自本地 `/v1/magpie/usage`，缺数据时保留 nil，由页面显示“待计量”。
struct WallpaperDashboard: Encodable {
    struct Period: Encodable {
        let label: String
        let total: Int
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let cacheShare: Double?
        let calls: Int
        let cost: Double
    }

    struct Hour: Encodable {
        let label: String
        let calls: Int
        let errors: Int
        let input: Int
        let output: Int
    }

    struct Rank: Encodable {
        let name: String
        let sub: String
        let calls: Int
        let errors: Int
        let tokens: Int
        let cost: Double
        let share: Double
        let ttftMs: Int?
    }

    let periods: [Period?]
    let calls: Int
    let errors: Int
    let retried: Int
    let sessions: Int?
    let cost: Double?
    let reasoning: Int?
    let ttftMs: Int?
    let decodeRate: Double?
    let hours: [Hour]
    let agents: [Rank]
    let models: [Rank]

    static func make(today: UsageResponse?, daily: UsageResponse?, masked: Bool = true, now: Date = Date(),
                     calendar baseCalendar: Calendar = .current) -> Self {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let todayPeriod = today.map {
            period("今日", input: $0.input, output: $0.output, cacheRead: $0.cacheRead,
                   cacheWrite: $0.cacheWrite, calls: $0.calls, cost: $0.cost)
        }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let points = daily?.series ?? []
        let week = daily.map { _ in sum("本周", points, since: dayKey(weekStart, calendar)) }
        let month = daily.map { _ in sum("本月", points, since: dayKey(monthStart, calendar)) }

        let agentCalls = max(1, (today?.agents ?? []).reduce(0) { $0 + ($1.calls ?? 0) })
        let agents = (today?.agents ?? []).sorted { ($0.calls ?? 0) > ($1.calls ?? 0) }.prefix(5).map {
            Rank(name: Fmt.agentName($0.name ?? $0.id), sub: "智能体", calls: $0.calls ?? 0,
                 errors: $0.errors ?? 0, tokens: tokens($0.input, $0.output, $0.cacheRead, $0.cacheWrite),
                 cost: $0.cost ?? 0, share: Double($0.calls ?? 0) / Double(agentCalls),
                 ttftMs: average($0.ttftMs, $0.timed))
        }
        let modelCalls = max(1, (today?.models ?? []).reduce(0) { $0 + ($1.calls ?? 0) })
        let models = (today?.models ?? []).sorted { ($0.calls ?? 0) > ($1.calls ?? 0) }.prefix(6).map {
            Rank(name: Fmt.modelName($0.name ?? $0.model), sub: subtitle($0.sub, provider: $0.provider, masked: masked),
                 calls: $0.calls ?? 0, errors: $0.errors ?? 0,
                 tokens: tokens($0.input, $0.output, $0.cacheRead, $0.cacheWrite),
                 cost: $0.cost ?? 0, share: Double($0.calls ?? 0) / Double(modelCalls),
                 ttftMs: average($0.ttftMs, $0.timed))
        }
        let hours = (today?.series ?? []).map {
            Hour(label: $0.label ?? "", calls: $0.calls ?? 0, errors: $0.errors ?? 0,
                 input: ($0.input ?? 0) + ($0.cacheRead ?? 0), output: $0.output ?? 0)
        }
        let decodeRate: Double? = {
            guard let out = today?.decodeOut, let ms = today?.decodeMs, ms > 0 else { return nil }
            return Double(out) / (Double(ms) / 1000)
        }()

        // 模型副标题里的账号沿用被动视图的邮箱遮蔽设置。
        return Self(periods: [todayPeriod, week, month], calls: today?.calls ?? 0,
                    errors: today?.errors ?? 0, retried: today?.retried ?? 0,
                    sessions: today?.sessionCount, cost: today?.cost, reasoning: today?.reasoning,
                    ttftMs: average(today?.ttftMs, today?.timed), decodeRate: decodeRate,
                    hours: hours, agents: Array(agents), models: Array(models))
    }

    private static func period(_ label: String, input: Int?, output: Int?, cacheRead: Int?,
                               cacheWrite: Int?, calls: Int?, cost: Double?) -> Period {
        let fresh = input ?? 0, cache = cacheRead ?? 0
        return Period(label: label, total: tokens(input, output, cacheRead, cacheWrite),
                      input: fresh, output: output ?? 0, cacheRead: cache, cacheWrite: cacheWrite ?? 0,
                      cacheShare: fresh + cache > 0 ? Double(cache) / Double(fresh + cache) * 100 : nil,
                      calls: calls ?? 0, cost: cost ?? 0)
    }

    /// 逐日序列的 time 形如 2026-10-23T00:00:00-07:00，按日期前缀与本地自然周/月起点比较。
    private static func sum(_ label: String, _ points: [UsagePoint], since start: String) -> Period {
        let kept = points.filter { String(($0.time ?? "").prefix(10)) >= start }
        func total(_ value: (UsagePoint) -> Int?) -> Int { kept.reduce(0) { $0 + (value($1) ?? 0) } }
        return period(label, input: total(\.input), output: total(\.output), cacheRead: total(\.cacheRead),
                      cacheWrite: total(\.cacheWrite), calls: total(\.calls),
                      cost: kept.reduce(0) { $0 + ($1.cost ?? 0) })
    }

    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Magpie 的模型副标题形如 "Codex · someone@example.com"，邮箱部分逐段遮蔽。
    private static func subtitle(_ raw: String?, provider: String?, masked: Bool) -> String {
        guard let raw, !raw.isEmpty else { return Fmt.providerName(provider) }
        return raw.components(separatedBy: " · ")
            .map { $0.contains("@") ? Fmt.maskAccount($0, masked: masked) : $0 }
            .joined(separator: " · ")
    }

    private static func tokens(_ values: Int?...) -> Int { values.reduce(0) { $0 + ($1 ?? 0) } }

    private static func average(_ sum: Int?, _ count: Int?) -> Int? {
        guard let sum, let count, count > 0 else { return nil }
        return sum / count
    }
}
