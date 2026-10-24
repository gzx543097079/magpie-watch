import Foundation
import Network

/// 壁纸页面的同源服务：静态页面 + `/v1/magpie/*` 反向代理。
///
/// 页面与 Magpie 的 JSON 同源，因此不需要 CORS，也不需要把每个字段写进 Swift 结构体。
/// 只监听回环地址，只代理 GET，且只代理 `/v1/magpie/` 前缀。
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
                self.handle(head: head, on: connection)
                return
            }
            if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
                return
            }
            self.read(on: connection, buffer: buffer)
        }
    }

    private func handle(head: String, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return respond(connection, status: 400, body: Data()) }
        let method = String(parts[0])
        let target = String(parts[1])
        guard method == "GET" || method == "HEAD" else {
            return respond(connection, status: 405, body: Data())
        }
        guard let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) else {
            return respond(connection, status: 400, body: Data())
        }

        if path.hasPrefix("/v1/magpie/") {
            proxy(target: target, connection: connection, headOnly: method == "HEAD")
        } else {
            serveFile(path: path, connection: connection, headOnly: method == "HEAD")
        }
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

    private func proxy(target: String, connection: NWConnection, headOnly: Bool) {
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
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
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
        default: return "application/octet-stream"
        }
    }
}
