import Foundation

/// 指数与黄金行情：菜单栏与壁纸共用的一份时刻表 + 拉取。
///
/// 同一时刻只看一组指数；每个品种只在自己开市时才发请求，休市时保留最后一笔。
/// 时段按各交易所自己的时区判定，美东夏令时 / 冬令时自动换算。
///
/// - 白天组「A股」：北京时间工作日 09:00–17:15 显示。
///   上证 / 创业板 / 科创50：09:30–11:30、13:00–15:00 刷新（腾讯 qt.gtimg.cn）。
/// - 夜间组「夜盘」：17:15 起至次日 09:00 显示（周五夜盘延续到周六上午）。
///   纳指 / 金龙 / 费半：美股常规时段 ET 09:30–16:00
///   （北京 21:30–04:00，冬令时 22:30–05:00）。
///   富时 A50 期货：新交所 T 盘 09:00–16:35，T+1 夜盘 17:15–次日 05:15。
/// - 黄金（伦敦金现货）两组都附带：ET 周日 18:00 至周五 17:00，每日 17:00–18:00 休市。
/// - 北京周六 09:00 后至周日全天：不显示。
/// 夜间组的数据统一走新浪 hq.sinajs.cn（要带 Referer），黄金同源。
actor MarketFeed {
    static let shared = MarketFeed()

    enum Group: String { case aShare = "A股", night = "夜盘", off = "" }

    struct Quote: Codable, Sendable {
        let code: String
        let label: String
        let price: Double
        let change: Double
        let live: Bool
    }

    struct Snapshot: Sendable {
        let group: Group
        let quotes: [Quote]
        var anyLive: Bool { quotes.contains { $0.live } }
        var stateText: String { group == .off ? "" : group.rawValue + (anyLive ? " · 实时" : " · 收盘") }
    }

    private enum Source { case tencent, sina }

    private struct Instrument {
        let code: String          // 上游代码，如 sh000001 / gb_$ixic / hf_XAU
        let label: String
        let source: Source
        let isOpen: (Date) -> Bool
    }

    private static let gold = Instrument(code: "hf_XAU", label: "黄金", source: .sina, isOpen: goldOpen)

    private static let dayGroup: [Instrument] = [
        Instrument(code: "sh000001", label: "上证", source: .tencent, isOpen: aShareOpen),
        Instrument(code: "sz399006", label: "创业板", source: .tencent, isOpen: aShareOpen),
        Instrument(code: "sh000688", label: "科创50", source: .tencent, isOpen: aShareOpen),
        gold
    ]

    private static let nightGroup: [Instrument] = [
        Instrument(code: "gb_$ixic", label: "纳指", source: .sina, isOpen: usOpen),
        Instrument(code: "gb_$hxc", label: "金龙", source: .sina, isOpen: usOpen),
        Instrument(code: "hf_CHA50CFD", label: "A50", source: .sina, isOpen: a50Open),
        Instrument(code: "gb_$sox", label: "费半", source: .sina, isOpen: usOpen),
        gold
    ]

    /// 设置里可勾选的品种（黄金在两组里共用一个开关）。
    static let options: [(code: String, label: String, group: Group)] =
        (dayGroup.dropLast().map { ($0.code, $0.label, Group.aShare) })
        + nightGroup.dropLast().map { ($0.code, $0.label, Group.night) }
        + [(gold.code, gold.label, Group.night)]

    /// 被用户关掉的品种代码；不显示，也不请求。
    static let hiddenKey = "magpie.market.hidden"

    private static let cacheKey = "magpie.market.last"
    private var last: [String: [Double]]   // code → [price, change%]
    private var lastFetch = Date.distantPast
    private var inflight: Task<Void, Never>?

    private init() {
        last = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: [Double]] ?? [:]
    }

    /// 当前该显示的一组；开市品种距上次拉取超过 1.5 秒才会真正请求上游。
    func snapshot(at now: Date = Date()) async -> Snapshot {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        var group = Self.group(at: now)
        let instruments = (group == .aShare ? Self.dayGroup : group == .night ? Self.nightGroup : [])
            .filter { !hidden.contains($0.code) }
        // 这一组全被关掉：和周末一样只留图标
        if instruments.isEmpty { group = .off }
        let open = instruments.filter { $0.isOpen(now) }
        if !open.isEmpty {
            if let inflight {
                await inflight.value
            } else if now.timeIntervalSince(lastFetch) > 1.5 {
                lastFetch = now
                let task = Task { await self.fetch(open) }
                inflight = task
                await task.value
                inflight = nil
            }
        }
        let quotes = instruments.compactMap { item -> Quote? in
            guard let value = last[item.code], value.count == 2 else { return nil }
            return Quote(code: item.code, label: item.label, price: value[0], change: value[1], live: item.isOpen(now))
        }
        return Snapshot(group: group, quotes: quotes)
    }

    // MARK: - 拉取

    private func fetch(_ items: [Instrument]) async {
        let tencent = items.filter { $0.source == .tencent }.map(\.code)
        let sina = items.filter { $0.source == .sina }.map(\.code)
        async let a = tencent.isEmpty ? [:] : Self.fetchTencent(tencent)
        async let b = sina.isEmpty ? [:] : Self.fetchSina(sina)
        let merged = (await a).merging(await b) { $1 }
        guard !merged.isEmpty else { return }
        last.merge(merged) { $1 }
        UserDefaults.standard.set(last, forKey: Self.cacheKey)
    }

    private static func get(_ url: URL, referer: String? = nil) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // 上游是 GBK；只取 ASCII 的代码与数字字段，不做编码转换。
        return String(decoding: data, as: UTF8.self)
    }

    /// 腾讯：v_sh000001="1~上证指数~000001~现价~…~涨跌幅(32)~…";
    private static func fetchTencent(_ codes: [String]) async -> [String: [Double]] {
        guard let url = URL(string: "https://qt.gtimg.cn/q=" + codes.joined(separator: ",")),
              let text = await get(url) else { return [:] }
        var out: [String: [Double]] = [:]
        for (code, body) in assignments(in: text, prefix: "v_") {
            let f = body.split(separator: "~", omittingEmptySubsequences: false)
            guard f.count > 32, let price = Double(f[3]), let change = Double(f[32]), price > 0 else { continue }
            out[code] = [price, change]
        }
        return out
    }

    /// 新浪：var hq_str_gb_$ixic="名称,现价,涨跌幅,…";  var hq_str_hf_XAU="现价,,买,卖,高,低,时间,昨收,…";
    private static func fetchSina(_ codes: [String]) async -> [String: [Double]] {
        let list = codes.joined(separator: ",")   // 新浪只认字面量 $，不能转义成 %24
        guard let url = URL(string: "https://hq.sinajs.cn/list=" + list),
              let text = await get(url, referer: "https://finance.sina.com.cn") else { return [:] }
        var out: [String: [Double]] = [:]
        for (code, body) in assignments(in: text, prefix: "hq_str_") {
            let f = body.split(separator: ",", omittingEmptySubsequences: false)
            if code.hasPrefix("gb_") {
                guard f.count > 2, let price = Double(f[1]), let change = Double(f[2]), price > 0 else { continue }
                out[code] = [price, change]
            } else if code.hasPrefix("hf_") {
                guard f.count > 7, let price = Double(f[0]), let prev = Double(f[7]), price > 0, prev > 0 else { continue }
                out[code] = [price, (price / prev - 1) * 100]
            }
        }
        return out
    }

    /// 把 `<prefix>CODE="BODY";` 逐条拆成 (CODE, BODY)。
    private static func assignments(in text: String, prefix: String) -> [(String, Substring)] {
        text.split(separator: ";").compactMap { line in
            guard let p = line.range(of: prefix), let eq = line.range(of: "=\"", range: p.upperBound..<line.endIndex) else { return nil }
            let code = String(line[p.upperBound..<eq.lowerBound])
            let body = line[eq.upperBound...].dropLast(line.hasSuffix("\"") ? 1 : 0)
            return body.isEmpty ? nil : (code, body)
        }
    }

    // MARK: - 时刻表

    /// (weekday 1=周日…7=周六, 当日分钟数)，按指定交易所时区。
    private static func clock(_ zone: String, _ date: Date) -> (weekday: Int, minutes: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return (c.weekday ?? 1, (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    static func group(at date: Date) -> Group {
        let (wd, m) = clock("Asia/Shanghai", date)
        if wd == 1 || (wd == 7 && m >= 540) { return .off }
        if (2...6).contains(wd) && m >= 540 && m < 1035 { return .aShare }
        return .night
    }

    static func aShareOpen(_ date: Date) -> Bool {
        let (wd, m) = clock("Asia/Shanghai", date)
        return (2...6).contains(wd) && ((570..<690).contains(m) || (780..<900).contains(m))
    }

    static func usOpen(_ date: Date) -> Bool {
        let (wd, m) = clock("America/New_York", date)
        return (2...6).contains(wd) && (570..<960).contains(m)
    }

    static func a50Open(_ date: Date) -> Bool {
        let (wd, m) = clock("Asia/Shanghai", date)
        let day = (2...6).contains(wd) && (540..<995).contains(m)
        let nightEvening = (2...6).contains(wd) && m >= 1035
        let nightMorning = (3...7).contains(wd) && m < 315
        return day || nightEvening || nightMorning
    }

    static func goldOpen(_ date: Date) -> Bool {
        let (wd, m) = clock("America/New_York", date)
        switch wd {
        case 1: return m >= 1080
        case 2...5: return !(1020..<1080).contains(m)
        case 6: return m < 1020
        default: return false
        }
    }
}
