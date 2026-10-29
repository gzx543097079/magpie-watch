import Foundation
import Network

/// 壁纸页面的同源服务：静态页面 + 三类转发。
///
/// 1. `/v1/magpie/*` → 网关（127.0.0.1:3425），只读 JSON。
/// 2. `/live-config` → 壁纸内嵌模块要用的 magpie web 页面地址。
/// 3. `/magpie/*` 与 `/api/*` → magpie web（MagpieWeb 拉起的无头网页版）：
///    前者是它的静态资产原样转发，后者是页面自己要调的后端接口（含
///    25 秒长轮询和 POST）。每个请求由服务端附上鉴权 Cookie，页面里
///    不落任何密钥。转发 `text/html` 时注入一行 skin.css —— 这就是
///    「原样代码 + 壁纸皮肤」的接缝：magpie 的 JS 一行不动。
///
/// 只监听回环地址。
final class LocalOrigin {
    static let shared = LocalOrigin()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "magpie.watch.origin")
    private let upstream = URL(string: "http://127.0.0.1:3425")!
    private let webRoot: URL

    private(set) var port: UInt16?

    var pageURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/dashboard.html")
    }

    private init() {
        webRoot = Bundle.main.url(forResource: "dashboard", withExtension: "html", subdirectory: "Wallpaper")?
            .deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// 依次尝试固定端口，全部被占用时退回系统分配的端口。
    func start() {
        guard listener == nil else { return }
        for candidate: UInt16 in [8766, 8767, 8768, 0] {
            if bind(port: candidate) { return }
        }
        NSLog("MagpieWatch: 本地页面服务启动失败")
    }

    private func bind(port: UInt16) -> Bool {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        guard let listener = try? NWListener(using: parameters, on: nwPort) else { return false }

        let ready = DispatchSemaphore(value: 0)
        var bound: UInt16?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                bound = listener.port?.rawValue
                ready.signal()
            case .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 1.5)
        guard let bound else {
            listener.cancel()
            return false
        }
        self.listener = listener
        self.port = bound
        return true
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        read(on: connection, buffer: Data())
    }

    private func read(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                let body = Data(buffer[headerEnd.upperBound...])
                let wanted = Self.contentLength(of: head)
                if body.count >= wanted {
                    self.handle(head: head, body: body.prefix(wanted), on: connection)
                } else {
                    self.readBody(on: connection, head: head, buffer: body, remaining: wanted - body.count)
                }
                return
            }
            if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
                return
            }
            self.read(on: connection, buffer: buffer)
        }
    }

    /// 请求头读完但正文（POST 的 JSON）还没到齐：按 Content-Length 续读。
    private func readBody(on connection: NWConnection, head: String, buffer: Data, remaining: Int) {
        connection.receive(minimumIncompleteLength: max(1, remaining), maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self, error == nil, !isComplete else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if buffer.count >= remaining {
                self.handle(head: head, body: buffer.prefix(remaining), on: connection)
            } else {
                self.readBody(on: connection, head: head, buffer: buffer, remaining: remaining - buffer.count)
            }
        }
    }

    private static func contentLength(of head: String) -> Int {
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length",
               let n = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return n
            }
        }
        return 0
    }

    private func handle(head: String, body: Data, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return respond(connection, status: 400, body: Data()) }
        let method = String(parts[0])
        let target = String(parts[1])
        guard method == "GET" || method == "HEAD" || method == "POST" else {
            return respond(connection, status: 405, body: Data())
        }
        guard let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) else {
            return respond(connection, status: 400, body: Data())
        }

        if path == "/live-config" {
            serveLiveConfig(connection)
        } else if path == "/magpie" || path.hasPrefix("/magpie/") {
            // magpie web 的页面与资产：原样转发，HTML 注入皮肤
            proxyMagpie(target: target, method: method, body: body, injectSkin: true, connection: connection)
        } else if path.hasPrefix("/api/") {
            // 页面自己要调的后端接口（长轮询在此，超时给足 25 秒余量）
            proxyMagpie(target: target, method: method, body: body, injectSkin: false, connection: connection)
        } else if path == "/gw" {
            // 顶栏在线灯：轻探网关铭牌
            legacyProxy(target: "/", connection: connection, headOnly: method == "HEAD")
        } else if path.hasPrefix("/v1/magpie/") {
            legacyProxy(target: target, connection: connection, headOnly: method == "HEAD")
        } else {
            serveFile(path: path, connection: connection, headOnly: method == "HEAD")
        }
    }

    /// 壁纸「实时路由」模块要内嵌的 magpie web 页面地址；magpie web 没就绪时 503，页面稍后重试。
    private func serveLiveConfig(_ connection: NWConnection) {
        Task.detached { [weak self] in
            guard let self else { return }
            if let href = await MagpieWeb.ensure() {
                let body = (try? JSONSerialization.data(withJSONObject: ["href": href, "generation": MagpieWeb.generation])) ?? Data()
                self.respond(connection, status: 200, body: body,
                             contentType: "application/json; charset=utf-8")
            } else {
                self.respond(connection, status: 503, body: Data(),
                             contentType: "application/json; charset=utf-8")
            }
        }
    }

    /// magpie web 反向代理：附鉴权 Cookie（密钥只在服务端这一侧），
    /// 缓冲整份响应再回（25 秒长轮询也在余量内），HTML 原地注入皮肤一行。
    private func proxyMagpie(target: String, method: String, body: Data, injectSkin: Bool, connection: NWConnection) {
        guard let port = MagpieWeb.preferredPort() else {
            return respond(connection, status: 503, body: Data(), contentType: "text/plain")
        }
        // /magpie/ 前缀摘掉，映射到 magpie web 的根；/api/ 原样
        let upstreamPath: String
        if target.hasPrefix("/magpie") {
            let rest = target.dropFirst("/magpie".count)
            upstreamPath = rest.isEmpty || rest.hasPrefix("/") ? String(rest) : "/" + rest
            if upstreamPath == "/" || upstreamPath.isEmpty {
                return respond(connection, status: 404, body: Data(), contentType: "text/plain")
            }
        } else {
            upstreamPath = target
        }
        // magpie/skin.css 是本地皮肤文件，不走转发
        if injectSkin, upstreamPath == "/skin.css" {
            return serveFile(path: "/skin.css", connection: connection, headOnly: method == "HEAD")
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)" + upstreamPath) else {
            return respond(connection, status: 400, body: Data(), contentType: "text/plain")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method == "HEAD" ? "GET" : method
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("magpie_web_\(port)=\(MagpieWeb.key())", forHTTPHeaderField: "Cookie")
        if !body.isEmpty {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 502
            var payload = data ?? Data()
            var contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            if injectSkin, status == 200, contentType.contains("text/html"),
               var text = String(data: payload, encoding: .utf8),
               let headEnd = text.range(of: "</head>", options: .caseInsensitive) {
                text.replaceSubrange(headEnd, with: "<link rel=\"stylesheet\" href=\"skin.css\"></head>")
                payload = Data(text.utf8)
            }
            self.respond(connection, status: status, body: method == "HEAD" ? Data() : payload,
                         contentType: contentType)
        }.resume()
    }

    /// 旧的只读网关代理（顶栏在线灯还在用）。
    private func legacyProxy(target: String, connection: NWConnection, headOnly: Bool) {
        guard let url = URL(string: upstream.absoluteString + target) else {
            return respond(connection, status: 400, body: Data())
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 502
            // 上游错误原样带状态码，页面据此显示「保留上次数据」。
            self.respond(connection, status: status,
                         body: headOnly ? Data() : (data ?? Data()),
                         contentType: "application/json; charset=utf-8")
        }.resume()
    }

    private func serveFile(path: String, connection: NWConnection, headOnly: Bool) {
        let name = path == "/" || path.isEmpty ? "dashboard.html" : String(path.dropFirst())
        guard !name.contains("..") else { return respond(connection, status: 403, body: Data()) }
        let file = webRoot.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file) else {
            return respond(connection, status: 404, body: Data())
        }
        respond(connection, status: 200, body: headOnly ? Data() : data,
                contentType: Self.mime(for: file.pathExtension))
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data,
                         contentType: String = "application/octet-stream") {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 303: return "See Other"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 503: return "Service Unavailable"
        default: return "Upstream"
        }
    }

    private static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "woff2": return "font/woff2"
        case "json": return "application/json; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
