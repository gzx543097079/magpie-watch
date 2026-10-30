import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var widgetController: WidgetWindowController!
    private var screensaverController: ScreensaverWindowController!
    private var wallpaperController: WallpaperWindowController!
    private lazy var consumptionController = ConsumptionWindowController(model: model)
    private var preferencesWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var marketTimer: Timer?
    private var marketRequestInFlight = false
    private var marketQuotes: [MarketQuote] = []
    private var isStatusMenuTracking = false
    private var cancellables = Set<AnyCancellable>()
    private var idleTimer: Timer?
    private var consumptionShortcut: Any?
    private var lastScreensaverPresentation: Date?
    private var suppressAutoUntil = Date().addingTimeInterval(30)
    /// 本应用是常驻壁纸/屏保的观测台：窗口永远位于桌面层、从不成为前台，
    /// 系统会按「不可见应用」启动 App Nap，把 WKWebView 的 requestAnimationFrame
    /// 压到约 1 帧/秒——星球还在，token 光束却一帧跳完，等于看不见。
    /// 用 userInitiated 活动声明常驻运转，禁掉 App Nap 的节流。
    private var keepAliveActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "MagpieWatch 壁纸遥测动画常驻刷新"
        )

        widgetController = WidgetWindowController(
            model: model,
            onScreensaver: { [weak self] in
                self?.showScreensaver()
            },
            onOpenMagpie: {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/Applications/magpie.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        )
        screensaverController = ScreensaverWindowController { [weak self] in
            self?.dismissScreensaver()
        }
        wallpaperController = WallpaperWindowController(model: model)

        configureStatusItem()
        startMarketTicker()
        // NSStatusItem menu equivalents do not run when its menu is closed.
        consumptionShortcut = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "t" else { return event }
            self?.consumptionController.show()
            return nil
        }
        bindModel()
        model.start()

        if model.isWidgetVisible {
            widgetController.show()
            widgetController.ensureOnScreen()
        }
        if model.isWallpaperEnabled {
            wallpaperController.show()
        }

        startIdleMonitoring()
        applyLaunchArguments()
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleTimer?.invalidate()
        marketTimer?.invalidate()
        MagpieWeb.stopOwned()
        if let consumptionShortcut { NSEvent.removeMonitor(consumptionShortcut) }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.title = "A股"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            button.image = nil
            button.toolTip = "Magpie Watch · A股行情"
        }

        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildStatusMenu()
    }

    private struct MarketQuote: Codable {
        let label: String
        let price: Double
        let change: Double
    }

    private let marketCacheKey = "magpie.marketBar.lastQuotes"

    private var isChinaWeekday: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = calendar.component(.weekday, from: Date())
        return weekday >= 2 && weekday <= 6
    }

    private var isChinaMarketOpen: Bool {
        guard isChinaWeekday else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let minutes = hour * 60 + minute
        return (minutes >= 570 && minutes < 690) || (minutes >= 780 && minutes < 900)
    }

    private func startMarketTicker() {
        marketTimer?.invalidate()
        if let data = UserDefaults.standard.data(forKey: marketCacheKey),
           let cached = try? JSONDecoder().decode([MarketQuote].self, from: data) {
            marketQuotes = cached
            updateMarketButton()
        }
        marketTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMarketBar() }
        }
        refreshMarketBar()
    }

    private func refreshMarketBar() {
        guard model.marketBarEnabled, isChinaWeekday else {
            marketQuotes = []
            updateMarketButton()
            return
        }
        // A股休市时保留最后报价，但完全不发起接口请求。
        guard isChinaMarketOpen else {
            updateMarketButton()
            return
        }
        guard !marketRequestInFlight else { return }
        marketRequestInFlight = true
        guard let url = URL(string: "https://qt.gtimg.cn/q=sh000001,sz399006,sh000688") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let quotes: [MarketQuote] = {
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data else { return [] }
                let labels = ["上证", "创业板", "科创50"]
                return String(decoding: data, as: UTF8.self)
                    .split(separator: ";")
                    .compactMap { line -> MarketQuote? in
                        let fields = line.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
                        guard fields.count > 32, let price = Double(fields[3]), let change = Double(fields[32]) else { return nil }
                        let index = fields[2] == "399006" ? 1 : fields[2] == "000688" ? 2 : 0
                        return MarketQuote(label: labels[index], price: price, change: change)
                    }
                    .sorted { labels.firstIndex(of: $0.label)! < labels.firstIndex(of: $1.label)! }
            }()
            Task { @MainActor in
                guard let self else { return }
                self.marketRequestInFlight = false
                if !quotes.isEmpty {
                    self.marketQuotes = quotes
                    if let data = try? JSONEncoder().encode(quotes) {
                        UserDefaults.standard.set(data, forKey: self.marketCacheKey)
                    }
                }
                self.updateMarketButton()
            }
        }.resume()
    }

    private func updateMarketButton() {
        guard let button = statusItem?.button else { return }
        guard model.marketBarEnabled, isChinaWeekday else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Magpie Watch")
            button.image?.isTemplate = true
            return
        }
        button.image = nil
        if !isChinaMarketOpen && marketQuotes.isEmpty {
            button.attributedTitle = NSAttributedString(string: "A股休市", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
            button.title = "A股休市"
            return
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let text = NSMutableAttributedString()
        for (index, quote) in marketQuotes.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "  ")) }
            let tone: NSColor = quote.change > 0 ? .systemRed : quote.change < 0 ? .systemGreen : .systemOrange
            let segment = String(format: "%@ %.2f %@%.2f%%", quote.label, quote.price, quote.change > 0 ? "+" : "", quote.change)
            text.append(NSAttributedString(string: segment, attributes: [.font: font, .foregroundColor: tone]))
        }
        button.attributedTitle = text.length > 0 ? text : NSAttributedString(string: "A股行情连接中", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
    }

    private func rebuildStatusMenu() {
        guard let statusMenu, !isStatusMenuTracking else { return }
        statusMenu.removeAllItems()

        let heading = NSMenuItem(
            title: model.isOnline ? "Magpie Watch · 已连接" : "Magpie Watch · 离线",
            action: nil,
            keyEquivalent: ""
        )
        heading.isEnabled = false
        statusMenu.addItem(heading)

        let usage = NSMenuItem(
            title: "今日 \(model.todayCalls) 次请求 · \(Fmt.currency(model.usage?.cost))",
            action: nil,
            keyEquivalent: ""
        )
        usage.isEnabled = false
        statusMenu.addItem(usage)

        statusMenu.addItem(.separator())

        statusMenu.addItem(
            menuItem(
                title: model.isWidgetVisible ? "隐藏桌面小组件" : "显示桌面小组件",
                action: #selector(toggleWidget),
                key: "w"
            )
        )
        statusMenu.addItem(
            menuItem(
                title: "进入动态屏保",
                action: #selector(showScreensaver),
                key: "s"
            )
        )
        statusMenu.addItem(
            menuItem(
                title: model.isWallpaperEnabled ? "隐藏动态壁纸" : "显示动态壁纸",
                action: #selector(toggleWallpaper),
                key: "d"
            )
        )
        statusMenu.addItem(
            menuItem(
                title: "刷新数据",
                action: #selector(refreshData),
                key: "r"
            )
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            menuItem(
                title: "重置小组件位置",
                action: #selector(resetWidgetPosition),
                key: ""
            )
        )
        statusMenu.addItem(menuItem(title: "令牌消耗明细…", action: #selector(openConsumption), key: "t"))
        statusMenu.addItem(
            menuItem(
                title: "偏好设置…",
                action: #selector(showPreferences),
                key: ","
            )
        )
        statusMenu.addItem(
            menuItem(
                title: "打开 Magpie",
                action: #selector(openMagpie),
                key: ""
            )
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            menuItem(
                title: "退出 Magpie Watch",
                action: #selector(quit),
                key: "q"
            )
        )
    }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func bindModel() {
        model.$isWidgetVisible
            .combineLatest(model.$isPinned, model.$clickThrough, model.$widgetExpanded)
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.widgetController.syncSettings()
                self.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        model.$refreshGeneration
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        model.$isScreensaverActive
            .dropFirst()
            .sink { [weak self] active in
                if !active {
                    self?.startIdleMonitoring()
                }
            }
            .store(in: &cancellables)

        model.$isWallpaperEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.wallpaperController.show()
                } else {
                    self.wallpaperController.hide()
                }
                self.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        model.$marketBarEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshMarketBar()
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)
    }

    private func startIdleMonitoring() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }
    }

    @objc private func openConsumption() { consumptionController.show() }

    private func applyLaunchArguments() {
        let arguments = Set(ProcessInfo.processInfo.arguments.dropFirst())
        if arguments.contains("--compact") {
            model.widgetExpanded = false
        } else if arguments.contains("--expanded") {
            model.widgetExpanded = true
        }

        if arguments.contains("--screensaver") {
            DispatchQueue.main.async { [weak self] in
                self?.showScreensaver()
            }
        }

        if arguments.contains("--wallpaper") {
            model.isWallpaperEnabled = true
            wallpaperController.show()
        }

        if arguments.contains("--token-details") { consumptionController.show() }

        if arguments.contains("--preferences") {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences()
            }
        }
    }

    private func checkIdleState() {
        guard model.autoScreensaver, !screensaverController.isVisible else { return }
        guard Date() >= suppressAutoUntil else { return }
        guard let lastScreensaverPresentation else {
            if idleSeconds() >= Double(model.idleMinutes * 60) {
                showScreensaver()
            }
            return
        }
        guard Date().timeIntervalSince(lastScreensaverPresentation) > 5 else { return }
        if idleSeconds() >= Double(model.idleMinutes * 60) {
            showScreensaver()
        }
    }

    private func idleSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .keyDown
        ]
        return eventTypes
            .map {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState,
                    eventType: $0
                )
            }
            .min() ?? 0
    }

    @objc private func toggleWidget() {
        widgetController.toggle()
    }

    @objc private func showScreensaver() {
        guard !screensaverController.isVisible else { return }
        lastScreensaverPresentation = Date()
        screensaverController.show(model: model)
    }

    @objc private func dismissScreensaver() {
        guard screensaverController.isVisible else { return }
        screensaverController.hide()
        model.isScreensaverActive = false
        lastScreensaverPresentation = Date()
        suppressAutoUntil = Date().addingTimeInterval(5)
    }

    @objc private func toggleWallpaper() {
        model.isWallpaperEnabled.toggle()
    }

    @objc private func refreshData() {
        Task { await model.refresh() }
    }

    @objc private func resetWidgetPosition() {
        widgetController.resetPosition()
        widgetController.show()
    }

    @objc private func showPreferences() {
        if let preferencesWindow {
            NSApp.activate(ignoringOtherApps: true)
            preferencesWindow.orderFrontRegardless()
            preferencesWindow.makeKey()
            return
        }

        let controller = NSHostingController(rootView: PreferencesView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Magpie Watch 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.center()
        preferencesWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    @objc private func openMagpie() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/magpie.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu()
        isStatusMenuTracking = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isStatusMenuTracking = false
    }
}
