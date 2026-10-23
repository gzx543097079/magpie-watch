import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var widgetController: WidgetWindowController!
    private var screensaverController: ScreensaverWindowController!
    private var wallpaperController: WallpaperWindowController!
    private var preferencesWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private var idleTimer: Timer?
    private var lastScreensaverPresentation: Date?
    private var suppressAutoUntil = Date().addingTimeInterval(30)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: "Magpie Watch"
            )
            button.image?.isTemplate = true
        }

        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusMenu else { return }
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
        statusMenu.addItem(themeMenuItem())
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

    private func themeMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        for theme in WatchThemeID.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.state = theme == model.theme ? .on : .off
            item.representedObject = theme.rawValue
            menu.addItem(item)
        }
        let parent = NSMenuItem(title: "视觉主题 · \(model.theme.title)", action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
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

        model.$theme
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        model.$isWallpaperEnabled
            .dropFirst()
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
    }

    private func startIdleMonitoring() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }
    }

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

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = WatchThemeID(rawValue: raw) else { return }
        model.theme = theme
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
    }
}
