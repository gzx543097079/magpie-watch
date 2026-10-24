import Foundation

// Only structural labels and counts are decoded, never the request/response body.
struct PromptBudget: Decodable {
    let tokens: Int?
    let counted: Bool?
    let parts: [PromptPart]?
}

struct PromptPart: Decodable {
    let kind: String
    let tokens: Int?
    let items: [PromptItem]?

    var title: String {
        switch kind {
        case "system": return "系统指令"
        case "tools": return "工具定义"
        case "memory": return "记忆与项目规则"
        case "results": return "工具执行返回"
        case "files": return "文件与图片"
        case "chat": return "对话历史"
        default: return kind
        }
    }
}

struct PromptItem: Decodable {
    let name: String?
    let tag: String?
    let n: Int?
    let tokens: Int?
}

struct UsageRequestsResponse: Decodable {
    let rows: [UsageRequest]?
    let total: Int?
}

struct UsageRequest: Decodable {
    let routeId: Int64?
    let t: String?
    let agent: String?
    let model: String?
    let kind: String?
    let compaction: Bool?
    let input: Int?
    let out: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let reasoning: Int?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case routeId, t, agent, model, kind, compaction, out, cacheRead, cacheWrite, reasoning, status
        case input = "in"
    }
}

struct ConsumptionRecord: Identifiable {
    let id: String
    let time: String?
    let agent: String?
    let model: String?
    let kind: String?
    let compaction: Bool
    let done: Bool
    let status: Int?
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let reasoning: Int?
    let prompt: PromptBudget?
    let folder: String?

    var purpose: String {
        if compaction { return "上下文压缩" }
        switch kind {
        case "memory_consolidation": return "记忆整理"
        case "thread_title": return "标题生成"
        case "web_search": return "网页搜索"
        case .some(let value) where !value.isEmpty: return value
        default: return "模型调用"
        }
    }

    var statusText: String {
        if !done { return "进行中 · 待结算" }
        guard let status else { return "已结束 · 状态未知" }
        return (200..<300).contains(status) ? "已完成" : "异常 · \(status)"
    }

    var failed: Bool { status.map { !(200..<300).contains($0) } ?? false }

    static func merge(trace: TraceResponse?, ledger: UsageRequestsResponse?) -> [ConsumptionRecord] {
        let routes = trace?.routes ?? []
        let rows = ledger?.rows ?? []
        var groups: [String: [UsageRequest]] = [:]
        for (index, row) in rows.enumerated() {
            let key = row.routeId.map(String.init) ?? "ledger-\(row.t ?? "")-\(index)"
            groups[key, default: []].append(row)
        }
        var routeMap: [String: TraceRoute] = [:]
        for route in routes { if let id = route.id { routeMap[String(id)] = route } }
        let keys = Set(groups.keys).union(routeMap.keys)
        func sum(_ values: [Int?]) -> Int? {
            let known = values.compactMap { $0 }
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        return keys.map { key in
            let route = routeMap[key], usage = groups[key] ?? [], first = usage.first
            let scoped = route?.usage ?? []
            // Ledger entries are authoritative once available. Never add trace usage to them.
            let input = usage.isEmpty ? sum(scoped.map(\.input)) : sum(usage.map(\.input))
            let output = usage.isEmpty ? (sum(scoped.map(\.out)) ?? route?.out) : sum(usage.map(\.out))
            let cache = usage.isEmpty ? sum(scoped.map(\.cacheRead)) : sum(usage.map(\.cacheRead))
            return ConsumptionRecord(
                id: key, time: route?.time ?? first?.t, agent: route?.agent ?? first?.agent,
                model: first?.model ?? route?.model, kind: first?.kind ?? route?.kind,
                compaction: usage.contains { $0.compaction == true }, done: !usage.isEmpty || route?.done == true,
                status: first?.status ?? route?.status, input: input, output: output, cacheRead: cache,
                cacheWrite: sum(usage.map(\.cacheWrite)), reasoning: sum(usage.map(\.reasoning)) ?? route?.reasoning,
                prompt: route?.prompt, folder: route?.folder
            )
        }.sorted { ($0.time ?? "", $0.id) > ($1.time ?? "", $1.id) }
    }
}

/// A small desktop projection; never send conversation bodies or full file paths to the HUD.
struct DesktopConsumptionSummary: Encodable {
    let purpose: String
    let source: String
    let status: String
    let active: Bool
    let failed: Bool
    let input: Int?
    let cache: Int?
    let output: Int?
    let context: String

    static func make(_ record: ConsumptionRecord) -> Self {
        let part = record.prompt?.parts?.filter { ($0.tokens ?? 0) > 0 }.max { ($0.tokens ?? 0) < ($1.tokens ?? 0) }
        let item = part?.items?.max { ($0.tokens ?? 0) < ($1.tokens ?? 0) }
        let name = item?.name.map { URL(fileURLWithPath: $0).lastPathComponent }
        let detail = part.map {
            "上下文主项 · \($0.title) \(Fmt.compact(Double($0.tokens ?? 0))) tok" + (name.map { " · \($0)" } ?? "")
        } ?? "上下文拆分未提供"
        return Self(purpose: record.purpose,
                    source: "\(Fmt.agentName(record.agent)) → \(record.model ?? "模型未提供")",
                    status: record.statusText, active: !record.done, failed: record.failed,
                    input: record.input, cache: record.cacheRead, output: record.output, context: detail)
    }
}
