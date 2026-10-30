import AppKit
import SwiftUI

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
            // 透明底 + 淡入：全屏不是「刷」地盖上来，而是从桌面里浮出来。
            window.isOpaque = false
            window.backgroundColor = .clear
            window.alphaValue = 0
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.contentViewController = NSHostingController(
                rootView: WallpaperWebScene(model: model, fullscreen: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // 画面先淡入到不透明，内容再自己从两侧展开（页面里的 dock 归零过渡）。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            windows.forEach { $0.animator().alphaValue = 1 }
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
        // 退出同样淡出，不做硬切；窗口在动画结束后才真正收起。
        let closing = windows
        windows.removeAll()
        lastMouseLocation = nil
        isDismissing = false
        guard !closing.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }
}
