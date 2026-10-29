import Foundation

/// magpie 自带的无头网页版（`magpie web`）：同一位 magpie 的完整页面 + 后端，
/// 官方设计就允许与 GUI 应用并存——读同一份设置与账号，不抢网关。
/// 壁纸的「实时路由」模块直接内嵌它（iframe），一行演出代码都不自己写。
///
/// 这里负责它的生命周期：挑一个空闲端口、用自己生成的密钥把它拉起、
/// 验活；页面经 `/live-config` 拿带密钥的地址。密钥只落在本应用的
/// defaults 里，不下发到任何能被其他页面读到的地方。
enum MagpieWeb {
    /// 依次尝试的端口：避开 3430（用户可能自己跑了一份 magpie web）。
    static let ports: [UInt16] = [3431, 3432, 3433, 3434]
    static let keyDefault = "magpie.web.key"
    static let portDefault = "magpie.web.port"

    private static var ensured = false
    private static var pending = false
    private static let pendingLock = NSLock()
    private static var ownedProcess: Process?
    private static var launchedBinary: String?
    private(set) static var generation = ""

    private static func beginEnsure() -> Bool {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        guard !pending else { return false }
        pending = true
        return true
    }

    private static func endEnsure() {
        pendingLock.lock()
        pending = false
        pendingLock.unlock()
    }

    /// 文件被自动更新替换后，旧进程仍映射旧可执行文件，必须重新启动。
    static func binaryFingerprint(path: String = "/Applications/magpie.app/Contents/MacOS/magpie") -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = attrs[.systemFileNumber], let device = attrs[.systemNumber],
              let size = attrs[.size], let date = attrs[.modificationDate] as? Date else { return nil }
        return "\(device):\(inode):\(size):\(date.timeIntervalSince1970)"
    }

    /// 只结束本进程启动的子进程，不碰用户自行启动的 magpie web。
    static func stopOwned() {
        if let process = ownedProcess, process.isRunning { process.terminate() }
        ownedProcess = nil
        launchedBinary = nil
        ensured = false
    }

    /// 密钥：16 字节随机数的十六进制（magpie 要求 32 位 hex）。
    static func key() -> String {
        let d = UserDefaults.standard
        if let k = d.string(forKey: keyDefault), k.count == 32 {
            return k
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let k = bytes.map { String(format: "%02x", $0) }.joined()
        d.set(k, forKey: keyDefault)
        return k
    }

    /// 记录可用的端口（验活成功过的那个），避免每次重启都换端口。
    static func preferredPort() -> UInt16? {
        let v = UserDefaults.standard.integer(forKey: portDefault)
        return v > 0 ? UInt16(v) : nil
    }

    static func setPreferredPort(_ p: UInt16) {
        UserDefaults.standard.set(Int(p), forKey: portDefault)
    }

    /// 探测某端口的 magpie web 是否带着我们的密钥活着：trace API 返回 JSON。
    static func alive(port: UInt16, timeout: TimeInterval = 2) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/gateway/trace?after=0&k=\(key())") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data.prefix(64), encoding: .utf8),
              text.contains("\"seq\"") else { return false }
        return true
    }

    /// 端口上是否有东西在听（不区分是谁）。
    static func listening(port: UInt16) -> Bool {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// 拉起 `magpie web --no-open`，等它开始监听并验活。
    @discardableResult
    static func spawn(port: UInt16) async -> Bool {
        let binary = "/Applications/magpie.app/Contents/MacOS/magpie"
        guard FileManager.default.isExecutableFile(atPath: binary), let fingerprint = binaryFingerprint(path: binary) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["web", "--no-open", "--addr", "127.0.0.1:\(port)"]
        var env = ProcessInfo.processInfo.environment
        env["MAGPIE_WEB_KEY"] = key()
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        ownedProcess = process
        launchedBinary = fingerprint
        generation = UUID().uuidString
        // 最多等 6 秒开始监听，再给 3 秒出 trace
        for _ in 0..<(6 * 10) {
            if listening(port: port) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for _ in 0..<15 {
            if await alive(port: port) {
                setPreferredPort(port)
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        stopOwned()
        return false
    }

    /// 幂等地确保有一份带我们密钥的 magpie web 可用；返回带密钥的页面地址。
    /// 已有别的实例在听但密钥对不上时，换下一个端口拉起自己的。
    static func ensure() async -> String? {
        guard beginEnsure() else { return nil }
        defer { endEnsure() }
        if ownedProcess != nil && (!ownedProcess!.isRunning || binaryFingerprint() != launchedBinary) {
            stopOwned()
        }
        if ensured, ownedProcess?.isRunning == true, let p = preferredPort(), await alive(port: p) {
            return pageURL(port: p)
        }
        // 验活失败时结束自己的失效进程；其他进程的端口一律不碰。
        stopOwned()
        var tried = Set<UInt16>()
        // 先试记下的端口，再扫其余端口：有实例但密钥不对就换端口
        for p in ([preferredPort()].compactMap { $0 } + ports) {
            guard !tried.contains(p) else { continue }
            tried.insert(p)
            if listening(port: p) {
                continue   // 被别的实例占了：不碰它
            }
            if await spawn(port: p) {
                ensured = true
                return pageURL(port: p)
            }
        }
        return nil
    }

    static func pageURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/?k=\(key())&view=routing&theme=dark"
    }
}
