import AppKit
import SwiftUI
import WebKit

/// macOS 保留桌面图标下方的窗口；动态画面交给本地 WebGL 页面绘制。
struct WallpaperWebScene: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let page = Bundle.main.url(forResource: "starport", withExtension: "html", subdirectory: "Wallpaper") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            assertionFailure("缺少 Wallpaper/starport.html")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let board = model.wallpaperBoard
        let payload = Payload(
            agents: board.agents.map {
                .init(id: $0.id, name: $0.name, sub: "今日调用", calls: $0.calls)
            },
            models: board.destinations.map {
                .init(id: $0.id, name: $0.modelName, sub: $0.providerName, calls: $0.calls)
            },
            flows: board.flows.map {
                .init(
                    id: $0.id,
                    agentID: $0.agentID,
                    destinationID: $0.destinationID,
                    stage: $0.stage.rawValue,
                    outcome: $0.outcome.webValue,
                    statusCode: $0.statusCode
                )
            },
            online: board.isOnline,
            calls: model.todayCalls,
            errors: model.usage?.errors ?? 0,
            pet: model.isPetEnabled
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }
        context.coordinator.latestPayload = json
        context.coordinator.sendIfReady()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var ready = false
        var latestPayload: String?
        private var sentPayload: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            sendIfReady()
        }

        func sendIfReady() {
            guard ready, let webView, let latestPayload, latestPayload != sentPayload else { return }
            // JSON 由 Codable 生成，不拼接未经转义的外部文本。
            webView.evaluateJavaScript("window.setMagpieData(\(latestPayload))") { [weak self] _, error in
                if error == nil { self?.sentPayload = latestPayload }
            }
        }
    }
}

private extension WallpaperFlowOutcome {
    var webValue: String {
        switch self {
        case .ok: return "ok"
        case .rateLimited: return "rateLimited"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .timedOut: return "timedOut"
        }
    }
}

private struct Payload: Encodable {
    struct Node: Encodable {
        let id: String
        let name: String
        let sub: String
        let calls: Int
    }
    struct Flow: Encodable {
        let id: String
        let agentID: String
        let destinationID: String
        let stage: String
        let outcome: String
        let statusCode: Int?
    }
    let agents: [Node]
    let models: [Node]
    let flows: [Flow]
    let online: Bool
    let calls: Int
    let errors: Int
    let pet: Bool
}
