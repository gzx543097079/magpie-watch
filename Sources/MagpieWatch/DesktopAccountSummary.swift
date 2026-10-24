import Foundation

struct DesktopAccountSummary: Encodable {
    let name: String
    let account: String
    let balance: String
    let remainingPercent: Double?
    let current: Bool

    static func make(_ quota: Quota, masked: Bool) -> Self {
        let windows = quota.windows ?? []
        let lines = windows.map { window -> String in
            let name = (window.name ?? "额度").replacingOccurrences(of: "5 hours", with: "5 小时").replacingOccurrences(of: "7 days", with: "7 天")
            if let display = window.display, !display.isEmpty { return "\(name) \(display)" }
            if let remaining = window.remaining {
                let unit = window.unit ?? "%"
                return "\(name) 剩余 \(Fmt.compact(remaining))\(unit)"
            }
            if let used = window.used { return "\(name) 剩余 \(Fmt.compact(max(0, 100 - used)))%" }
            if let amount = window.amount { return "\(name) 已用 \(Fmt.compact(amount)) \(window.unit ?? "")" }
            return "\(name) 未提供"
        }
        let percentages = windows.compactMap { window -> Double? in
            guard window.unit == nil || window.unit == "%" else { return nil }
            return window.remaining ?? window.used.map { max(0, 100 - $0) }
        }
        let accountName = quota.name ?? Fmt.providerName(quota.provider)
        let displayName = accountName.contains("@") ? Fmt.maskAccount(accountName, masked: masked) : accountName
        return Self(name: [displayName, quota.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "),
                    account: Fmt.maskAccount(quota.user, masked: masked),
                    balance: lines.isEmpty ? "余额 / 额度未提供" : lines.joined(separator: " · "),
                    remainingPercent: percentages.min().map { min(100, max(0, $0)) }, current: quota.last == true)
    }
}
