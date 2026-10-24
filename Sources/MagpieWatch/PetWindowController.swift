import AppKit
import WebKit

enum PetSkin: String, CaseIterable, Identifiable {
    case whale, pajama, christmas, halloween, midAutumn, spring, valentine

    var id: String { rawValue }
    var title: String {
        switch self {
        case .whale: return "原版鲸鱼娘"
        case .pajama: return "软萌睡衣"
        case .christmas: return "圣诞装扮"
        case .halloween: return "万圣魔女"
        case .midAutumn: return "中秋月兔"
        case .spring: return "新春贺岁"
        case .valentine: return "情人节限定"
        }
    }
    var pose: String {
        switch self {
        case .whale: return "idle-cute"
        case .pajama: return "daily-pajama"
        case .christmas: return "festival-christmas"
        case .halloween: return "festival-halloween"
        case .midAutumn: return "festival-mid-autumn"
        case .spring: return "festival-spring"
        case .valentine: return "valentine"
        }
    }
    var subtitle: String { self == .whale ? "咖啡、伸懒腰与摇尾巴" : "待机装扮 · 工作时自动换姿态" }
}

// A completed trace can remain visible for 22 seconds. Emit its reaction once,
// and keep ongoing work visible when another concurrent request completes.
struct PetActivityTracker {
    private var seenCompletions = Set<String>()
    private var completionOrder: [String] = []

    mutating func next(online: Bool, flows: [WallpaperPacketFlow]) -> (state: String, eventID: String) {
        guard online else { return ("offline", "") }
        let completed = flows.filter { $0.stage == .returning }
        let fresh = completed.filter { !seenCompletions.contains("\($0.id):\($0.outcome)") }
        for flow in fresh {
            let key = "\(flow.id):\(flow.outcome)"
            seenCompletions.insert(key)
            completionOrder.append(key)
        }
        while completionOrder.count > 256 { seenCompletions.remove(completionOrder.removeFirst()) }
        let active = flows.filter { $0.stage != .returning }
        if active.contains(where: { $0.stage == .outbound }) { return ("tool", "") }
        if active.contains(where: { $0.stage == .incoming }) { return ("thinking", "") }
        if !active.isEmpty { return ("waiting", "") }
        if let failure = fresh.first(where: { $0.outcome != .ok }) { return ("failure", "\(failure.id):\(failure.outcome)") }
        if let success = fresh.first { return ("success", "\(success.id):ok") }
        return ("idle", "")
    }
}

@MainActor
final class PetWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private final class PetPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class DragSurface: NSView {
        var openDetails: (() -> Void)?
        var didDrag: (() -> Void)?
        var dragging: ((Bool, CGFloat) -> Void)?
        var interaction: ((CGFloat, CGFloat) -> Void)?
        var contextAction: ((NSEvent) -> Void)?
        private var downPoint = NSPoint.zero
        private var origin = NSPoint.zero
        private var isDragging = false
        private var previousX: CGFloat = 0

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            downPoint = NSEvent.mouseLocation
            origin = window?.frame.origin ?? .zero
            previousX = downPoint.x
            isDragging = false
        }
        override func mouseDragged(with event: NSEvent) {
            let point = NSEvent.mouseLocation
            let dx = point.x - downPoint.x, dy = point.y - downPoint.y
            guard isDragging || hypot(dx, dy) > 4 else { return }
            isDragging = true
            window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            dragging?(true, point.x - previousX)
            previousX = point.x
        }
        override func mouseUp(with event: NSEvent) {
            if isDragging {
                dragging?(false, 0)
                didDrag?()
            } else if event.clickCount >= 2 {
                openDetails?()
            } else {
                let point = window?.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
                let side = bounds.width - 16
                // Match the square image frame in pet.css (8px sides, 40px bottom).
                interaction?((point.x - 8) / side, 1 - (point.y - 40) / side)
            }
            isDragging = false
        }
        override func rightMouseDown(with event: NSEvent) { contextAction?(event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { "鲸鱼娘，单击摸头，双击打开工作台，拖动移动" }
        override func accessibilityPerformPress() -> Bool { interaction?(0.5, 0.3); return true }
    }

    private let model: AppModel
    private let defaults: UserDefaults
    private var panel: PetPanel?
    private var webView: WKWebView?
    private var screenObserver: NSObjectProtocol?
    private var ready = false
    private var appliedSkin: PetSkin?
    private var activityTracker = PetActivityTracker()
    private var lastState = ""
    private var lastEventID = ""
    private lazy var details: PetDetailWindowController = {
        let controller = PetDetailWindowController(model: model)
        controller.selectSkin = { [weak self] skin in self?.select(skin); self?.play("preview:idle") }
        controller.playAction = { [weak self] in self?.play($0) }
        return controller
    }()

    func showDetails(_ tab: PetDetailTab = .outfits) { details.show(tab) }

    private func play(_ action: String) {
        if !model.isPetEnabled { model.isPetEnabled = true }
        show()
        let preview = action.hasPrefix("preview:")
        let value = preview ? String(action.dropFirst(8)) : action
        guard (preview ? ["idle", "waiting", "thinking", "tool", "success", "failure"] : ["feed", "praise", "poke"]).contains(value) else { return }
        let function = preview ? "previewPetState" : "petInteract"
        webView?.evaluateJavaScript("window.\(function)('\(value)')", completionHandler: nil)
    }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ensureOnScreen() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        guard model.isPetEnabled else { return }
        if panel == nil { build() }
        guard let panel else { return }
        if !panel.isVisible {
            ensureOnScreen()
            panel.orderFrontRegardless()
            webView?.evaluateJavaScript("window.setPetPaused(false)", completionHandler: nil)
        }
        applySkin()
        updateState()
    }

    func hide() {
        webView?.evaluateJavaScript("window.setPetPaused(true)", completionHandler: nil)
        panel?.orderOut(nil)
    }

    func sync() {
        if model.isPetEnabled { show() } else { hide() }
    }

    func select(_ skin: PetSkin) {
        model.petSkin = skin
        applySkin()
    }

    private func build() {
        let frame = restoredFrame()
        let panel = PetPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        if let url = Bundle.main.url(forResource: "pet", withExtension: "html", subdirectory: "Pets") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.addSubview(webView)
        let drag = DragSurface(frame: NSRect(x: 0, y: 24, width: frame.width, height: frame.height - 24))
        drag.openDetails = { [weak self] in self?.showDetails() }
        drag.autoresizingMask = [.width, .height]
        drag.contextAction = { [weak self] event in self?.showMenu(event: event) }
        drag.didDrag = { [weak self] in self?.ensureOnScreen(); self?.saveFrame() }
        drag.dragging = { [weak self] active, delta in
            self?.webView?.evaluateJavaScript("window.setPetDrag(\(active), \(delta))", completionHandler: nil)
        }
        drag.interaction = { [weak self] x, y in
            self?.webView?.evaluateJavaScript("window.petInteract('pat', \(x), \(y))", completionHandler: nil)
        }
        container.addSubview(drag)
        let detailsButton = NSButton(title: "换装与动作 ›", target: self, action: #selector(openDetails))
        detailsButton.frame = NSRect(x: 10, y: 0, width: frame.width - 20, height: 24)
        detailsButton.isBordered = false
        detailsButton.font = .systemFont(ofSize: 11, weight: .medium)
        detailsButton.contentTintColor = NSColor(calibratedRed: 0.65, green: 0.91, blue: 1, alpha: 1)
        detailsButton.wantsLayer = true
        detailsButton.layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.18, alpha: 0.94).cgColor
        detailsButton.layer?.cornerRadius = 12
        detailsButton.autoresizingMask = [.width]
        container.addSubview(detailsButton)
        panel.contentView = container
        panel.delegate = self
        panel.setFrame(frame, display: true)
        self.panel = panel
        self.webView = webView
    }

    private func restoredFrame() -> NSRect {
        let size = NSSize(width: 246, height: 316)
        if let value = defaults.string(forKey: "magpie.pet.frame") {
            let frame = NSRectFromString(value)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: frame.midX, y: frame.midY)) }) {
                return NSRect(origin: frame.origin, size: size)
            }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.minX + 28, y: screen.minY + 30, width: size.width, height: size.height)
    }

    func ensureOnScreen() {
        guard let panel else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
            y: min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        ))
    }

    func resetPosition() {
        defaults.removeObject(forKey: "magpie.pet.frame")
        panel?.setFrame(restoredFrame(), display: true)
        saveFrame()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        appliedSkin = nil
        lastState = ""
        webView.evaluateJavaScript("window.setPetPaused(\(!model.isPetEnabled))", completionHandler: nil)
        applySkin()
        updateState()
    }

    private func saveFrame() {
        guard let panel else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: "magpie.pet.frame")
    }

    private func applySkin() {
        guard ready, appliedSkin != model.petSkin, let webView, let data = try? JSONEncoder().encode(model.petSkin.rawValue),
              let raw = String(data: data, encoding: .utf8) else { return }
        let skin = model.petSkin
        webView.evaluateJavaScript("window.setPetSkin(\(raw))") { [weak self] _, error in
            if error == nil { self?.appliedSkin = skin }
        }
    }

    private func updateState() {
        guard ready, let webView else { return }
        let activity = activityTracker.next(online: model.isOnline, flows: model.wallpaperBoard.flows)
        guard activity.state != lastState || activity.eventID != lastEventID else { return }
        lastState = activity.state
        lastEventID = activity.eventID
        guard let data = try? JSONEncoder().encode([activity.state, activity.eventID]),
              let arguments = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.setPetState(...\(arguments))", completionHandler: nil)
    }

    private func showMenu(event: NSEvent) {
        saveFrame()
        let menu = NSMenu()
        let heading = NSMenuItem(title: "鲸鱼娘 · 单击摸头 / 拖动移动", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for (title, action) in [("投喂小点心", "feed"), ("夸夸鲸鱼娘", "praise"), ("戳一下", "poke")] {
            let item = NSMenuItem(title: title, action: #selector(interact(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [("装扮页面…", #selector(openOutfits)), ("动作页面…", #selector(openActions))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let reset = NSMenuItem(title: "回到原位", action: #selector(resetPet), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏桌宠", action: #selector(hidePet), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())
        let wallpaper = NSMenuItem(title: model.isWallpaperEnabled ? "隐藏星潮壁纸" : "显示星潮壁纸", action: #selector(toggleWallpaper), keyEquivalent: "")
        wallpaper.target = self
        menu.addItem(wallpaper)
        let preview = NSMenuItem(title: "预览 Token 流向（演示）", action: #selector(togglePreview), keyEquivalent: "")
        preview.target = self
        preview.state = model.wallpaperPreview ? .on : .off
        menu.addItem(preview)
        NSMenu.popUpContextMenu(menu, with: event, for: panel?.contentView ?? NSView())
    }

    @objc private func openDetails() { DispatchQueue.main.async { [weak self] in self?.showDetails() } }
    @objc private func openOutfits() { DispatchQueue.main.async { [weak self] in self?.showDetails(.outfits) } }
    @objc private func openActions() { DispatchQueue.main.async { [weak self] in self?.showDetails(.actions) } }

    @objc private func interact(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String,
              ["feed", "praise", "poke"].contains(action) else { return }
        webView?.evaluateJavaScript("window.petInteract('\(action)')", completionHandler: nil)
    }

    @objc private func previewState(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String,
              ["tool", "thinking", "success", "failure"].contains(state) else { return }
        webView?.evaluateJavaScript("window.previewPetState('\(state)')", completionHandler: nil)
    }

    @objc private func resetPet() { resetPosition() }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let skin = PetSkin(rawValue: raw) else { return }
        select(skin)
    }

    @objc private func toggleWallpaper() { model.isWallpaperEnabled.toggle() }
    @objc private func togglePreview() {
        model.wallpaperPreview.toggle()
        if model.wallpaperPreview { model.isWallpaperEnabled = true }
    }

    @objc private func hidePet() {
        model.isPetEnabled = false
    }
}
