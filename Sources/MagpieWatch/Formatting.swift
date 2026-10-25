import Foundation

enum Fmt {
    static func compact(_ value: Int?) -> String {
        compact(Double(value ?? 0))
    }

    static func compact(_ value: Double) -> String {
        let absolute = abs(value)
        switch absolute {
        case 1_000_000_000...:
            return trimmed(value / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return trimmed(value / 1_000_000, suffix: "M")
        case 1_000...:
            return trimmed(value / 1_000, suffix: "K")
        default:
            return String(Int(value.rounded()))
        }
    }

    static func currency(_ value: Double?) -> String {
        String(format: "$%.2f", value ?? 0)
    }

    static func credits(_ value: Double?) -> String {
        String(format: "%.1f", value ?? 0)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 99.95 {
            return "100%"
        }
        if value < 0.1 {
            return "<0.1%"
        }
        return String(format: "%.1f%%", value)
    }

    static func latency(_ milliseconds: Int?) -> String {
        guard let milliseconds else { return "—" }
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
    }

    static func rate(_ output: Int?, decodeMilliseconds: Int?) -> String {
        guard let output, let decodeMilliseconds, decodeMilliseconds > 0 else {
            return "—"
        }
        let value = Double(output) / (Double(decodeMilliseconds) / 1_000)
        return "\(Int(value.rounded())) 字/秒"
    }

    /// 数值版生成速率，供 token 流向动画使用。
    static func tokensPerSec(_ output: Int?, decodeMilliseconds: Int?) -> Double {
        guard let output, let decodeMilliseconds, decodeMilliseconds > 0 else {
            return 0
        }
        return Double(output) / (Double(decodeMilliseconds) / 1_000)
    }

    static func maskAccount(_ account: String?, masked: Bool = true) -> String {
        guard let account, !account.isEmpty else { return "未知账号" }
        guard masked else { return account }
        if account.contains("@") {
            let parts = account.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return account }
            let local = parts[0]
            let visiblePrefix = String(local.prefix(min(2, local.count)))
            let visibleSuffix = String(local.suffix(min(4, local.count)))
            return "\(visiblePrefix)•••\(visibleSuffix)@\(parts[1])"
        }
        if account.count <= 2 {
            return String(account.prefix(1)) + "•••"
        }
        return String(account.prefix(1)) + "•••" + String(account.suffix(1))
    }

    static func agentName(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "codex":
            return "Codex"
        case "claude-desktop":
            return "Claude Desktop"
        case "claude-code":
            return "Claude Code"
        case "cursor":
            return "Cursor"
        default:
            guard let raw, !raw.isEmpty else { return "智能体" }
            return raw
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    static func providerName(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "codex":
            return "Codex"
        case "workbuddy-ai":
            return "WorkBuddy AI"
        case "workbuddy":
            return "WorkBuddy"
        case "claude":
            return "Claude"
        case "cursor":
            return "Cursor"
        case "zcode":
            return "ZCode"
        default:
            guard let raw, !raw.isEmpty else { return "服务商" }
            return raw
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    static func modelName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "智能路由" }
        let withoutPrefix = raw
            .replacingOccurrences(of: "group/auto-", with: "")
            .replacingOccurrences(of: "group/", with: "")
            .replacingOccurrences(of: "auto/", with: "")
        return withoutPrefix
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "尚未更新" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0...2:
            return "刚刚更新"
        case 3...59:
            return "\(seconds) 秒前更新"
        case 60...3_599:
            return "\(seconds / 60) 分钟前更新"
        default:
            return "\(seconds / 3_600) 小时前更新"
        }
    }

    static func resetText(_ raw: String?, now: Date = Date()) -> String {
        guard let date = DateParser.parse(raw) else { return "额度窗口" }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "等待刷新" }
        if seconds < 3_600 {
            return "\(max(1, seconds / 60)) 分钟后重置"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600) 小时后重置"
        }
        return "\(seconds / 86_400) 天后重置"
    }

    static func clock(_ date: Date = Date(), seconds: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date).uppercased()
    }

    static func quotaDetail(_ window: QuotaWindow?, maskedAccount: String) -> String {
        guard let window else { return maskedAccount }
        if let display = window.display, !display.isEmpty {
            if let unit = window.unit, !unit.isEmpty {
                return "\(display) \(unit)"
            }
            return display
        }
        if let used = window.used {
            return "已用 \(percent(used))"
        }
        return maskedAccount
    }

    private static func trimmed(_ value: Double, suffix: String) -> String {
        if value >= 100 || value.rounded() == value {
            return String(format: "%.0f%@", value, suffix)
        }
        return String(format: "%.1f%@", value, suffix)
    }
}

enum DateParser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return fractional.date(from: raw) ?? standard.date(from: raw)
    }
}
