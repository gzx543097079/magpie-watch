import AppKit
import SwiftUI

@MainActor
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WidgetWindowController {
    private(set) var panel: FloatingPanel
    private let model: AppModel
    private let onScreensaver: () -> Void
    private let onOpenMagpie: () -> Void

    init(
        model: AppModel,
        onScreensaver: @escaping () -> Void,
        onOpenMagpie: @escaping () -> Void
    ) {
        self.model = model
        self.onScreensaver = onScreensaver
        self.onOpenMagpie = onOpenMagpie

        let initialSize = model.widgetExpanded
            ? CGSize(width: 430, height: 640)
            : CGSize(width: 294, height: 196)
        let frame = Self.defaultFrame(for: initialSize)
        panel = FloatingPanel(contentRect: frame)
        panel.setFrame(frame, display: true)

        let root = WidgetView(
            model: model,
            onOpenScreensaver: onScreensaver,
            onOpenMagpie: onOpenMagpie,
            onClose: { [weak self] in
                self?.hide()
            }
        )
        panel.contentViewController = NSHostingController(rootView: root)
        panel.contentViewController?.view.window?.backgroundColor = .clear
        panel.ignoresMouseEvents = model.clickThrough
        panel.level = model.isPinned ? .floating : .normal
    }

    func show() {
        model.isWidgetVisible = true
        resizeIfNeeded()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        model.isWidgetVisible = false
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func syncSettings() {
        resizeIfNeeded()
        panel.ignoresMouseEvents = model.clickThrough
        panel.level = model.isPinned ? .floating : .normal
        if model.isWidgetVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func ensureOnScreen() {
        let screens = NSScreen.screens
        let visible = screens.contains { screen in
            screen.visibleFrame.intersects(panel.frame)
        }
        guard !visible else { return }
        resetPosition()
    }

    func resetPosition() {
        let size = panel.frame.size
        let frame = Self.defaultFrame(for: size)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func resizeIfNeeded() {
        let target = model.widgetExpanded
            ? CGSize(width: 430, height: 640)
            : CGSize(width: 294, height: 196)
        guard abs(panel.frame.width - target.width) > 1
                || abs(panel.frame.height - target.height) > 1 else {
            return
        }

        var frame = panel.frame
        frame.origin.y += frame.height - target.height
        frame.size = target

        if let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - target.width - 12)
            frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - target.height - 12)
        }

        panel.setFrame(frame, display: true, animate: true)
    }

    private static func defaultFrame(for size: CGSize) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.maxX - size.width - 34,
            y: screen.maxY - size.height - 34,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class WallpaperWindowController {
    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool {
        windows.contains { $0.isVisible }
    }

    func show() {
        rebuild()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuild()
                }
            }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// 屏幕集合变化时按需重建，保证每块屏幕都有一层壁纸。
    private func rebuild() {
        guard model.isWallpaperEnabled else { return }
        let screens = NSScreen.screens

        windows.removeAll { window in
            guard let screen = window.screen, screens.contains(screen) else {
                window.orderOut(nil)
                return true
            }
            window.setFrame(screen.frame, display: true)
            return false
        }

        for screen in screens where !windows.contains(where: { $0.screen == screen }) {
            windows.append(makeWindow(for: screen))
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // SDK 头文件定义：桌面壁纸层 = INT32_MIN + 25，桌面图标层 = INT32_MIN + 45。
        // 取中间值，让壁纸动效流动在系统壁纸之上、桌面图标之下。
        window.level = NSWindow.Level(rawValue: Int(Int32.min) + 35)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: WallpaperWebScene(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}

@MainActor
final class ScreensaverWindowController {
    private var windows: [NSWindow] = []
    private var activity: NSObjectProtocol?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var lastMouseLocation: NSPoint?
    private var isDismissing = false
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    var isVisible: Bool {
        windows.contains { $0.isVisible }
    }

    func show(model: AppModel) {
        guard windows.isEmpty else { return }
        model.isScreensaverActive = true

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.018, green: 0.07, blue: 0.09, alpha: 1)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.contentViewController = NSHostingController(
                rootView: ScreensaverView(model: model, onDismiss: onDismiss)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        lastMouseLocation = NSEvent.mouseLocation

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Magpie Watch screensaver"
        )

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.dismissOnce()
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissOnce()
            }
        }

        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, let previous = self.lastMouseLocation else { return event }
            let current = NSEvent.mouseLocation
            if hypot(current.x - previous.x, current.y - previous.y) > 18 {
                self.dismissOnce()
                return nil
            }
            return event
        }
    }

    private func dismissOnce() {
        guard !isDismissing else { return }
        isDismissing = true
        onDismiss()
    }

    func hide() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
            self.mouseMoveMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        lastMouseLocation = nil
        isDismissing = false
    }
}
