import AppKit
import SwiftUI
import WebKit

/// macOS 保留桌面图标下方的窗口；画面交给同源页面，字段直接读取 Magpie 原始 JSON。
struct WallpaperWebScene: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var fullscreen = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        LocalOrigin.shared.start()
        if let page = LocalOrigin.shared.pageURL {
            webView.load(URLRequest(url: page))
        } else {
            assertionFailure("本地页面服务未能启动")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.fullscreen = fullscreen
        context.coordinator.rightInset = model.wallpaperRightInset
        context.coordinator.sendConfig(maskEmails: model.maskEmails)
        context.coordinator.sendStatus(online: model.isOnline, updatedAt: model.lastUpdated)
        context.coordinator.sendLayout()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var ready = false
        var fullscreen = false
        var rightInset = 120
        private var sentConfig: String?
        private var sentStatus: String?
        private var sentLayout: String?
        private var layoutObserver: NSObjectProtocol?

        override init() {
            super.init()
            layoutObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.sendLayout()
            }
        }

        deinit {
            if let layoutObserver { NotificationCenter.default.removeObserver(layoutObserver) }
        }

        func sendLayout() {
            guard ready, let webView else { return }
            let screen = webView.window?.screen ?? NSScreen.main
            // 左侧只让开 Dock 本身：可见区域与屏幕左边之差 + 12pt 间隙，再扣掉页面自带的 36px 边距。
            // Dock 不在左侧或自动隐藏时差为 0，就只剩页面边距。右侧让开用户放文件夹的那一列。
            let dock = (screen?.visibleFrame.minX ?? 0) - (screen?.frame.minX ?? 0)
            let left = dock > 0 ? max(0, dock + 12 - 36) : 0
            let right = max(0, rightInset)
            let bottom = max(28, (screen?.visibleFrame.minY ?? 0) - (screen?.frame.minY ?? 0) + 12)
            let script = "window.setMagpieLayout({fullscreen:\(fullscreen),left:\(left),right:\(right),bottom:\(bottom)})"
            guard script != sentLayout else { return }
            sentLayout = script
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func sendConfig(maskEmails: Bool) {
            let json = "{\"mask\":\(maskEmails)}"
            guard json != sentConfig else { return }
            sentConfig = json
            guard ready, let webView else { return }
            webView.evaluateJavaScript("window.setMagpieConfig(\(json))", completionHandler: nil)
        }

        func sendStatus(online: Bool, updatedAt: Date?) {
            let stamp = updatedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "null"
            let json = "{\"online\":\(online),\"updatedAt\":\(stamp)}"
            guard json != sentStatus else { return }
            sentStatus = json
            guard ready, let webView else { return }
            webView.evaluateJavaScript("window.setMagpieStatus(\(json))", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            // 页面重载后布局脚本要重发一次，否则缓存的比较会把它挡掉。
            sentLayout = nil
            sendLayout()
            // 首帧补发一次，避免页面在 didFinish 之前错过配置。
            if let sentConfig {
                webView.evaluateJavaScript("window.setMagpieConfig(\(sentConfig))", completionHandler: nil)
            }
            if let sentStatus {
                webView.evaluateJavaScript("window.setMagpieStatus(\(sentStatus))", completionHandler: nil)
            }
        }
    }
}
