import AppKit
import QuartzCore
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keep the frame we chose. The default pulls borderless windows under the menu bar,
    /// which hides a panel that is meant to sit in the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onClick: ((String) -> Void)?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        onClick?("view")
        super.mouseDown(with: event)
    }
}

final class NotchPanelController {
    private struct PanelFrames {
        var collapsed: NSRect
        var expanded: NSRect
        var obscuredTop: CGFloat
        var chin: CGFloat
        var hardware: Bool
    }

    private let model: AppModel
    private let panel: NotchPanel
    private var spring = SpringValue()
    private var springTimer: Timer?
    private var hoverTimer: Timer?
    private var peekWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var pointerInside = false
    private var outsideSince: TimeInterval?
    private var expandedAbove = false
    private var lastTick = CACurrentMediaTime()
    private var lastLoggedSize = NSSize.zero
    private var lastClickAt: TimeInterval = 0
    private let exitMargin: CGFloat = 12
    private let closeDelay: TimeInterval = 0.4

    init(model: AppModel) {
        self.model = model
        let initial = ScreenGeometry.placement()?.collapsedFrame
            ?? CGRect(x: 0, y: 800, width: 200, height: 54)
        let panel = NotchPanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = Self.notchLevel()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        let root = NotchRootView(
            panel: model.panel,
            settings: model.settings,
            nowPlaying: model.nowPlaying,
            calendar: model.calendar,
            shelf: model.shelf,
            battery: model.battery,
            mirror: model.mirror,
            actions: model.actions
        )
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        self.panel = panel
        host.onClick = { [weak self] source in self?.handleClick(source: source) }
        placeHostingView(reason: "init")
        wireActions()
        AppLog.panel.notice(
            "panel created level=\(panel.level.rawValue, privacy: .public) frame=\(Self.rectString(panel.frame), privacy: .public)"
        )
    }

    func start() {
        AppLog.lifecycle.notice("Notchling panel start")
        ScreenGeometry.logScreens()
        applyFrame(reason: "start")
        reveal()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.evaluateHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleClick(source: "global")
            }
        }
        AppLog.panel.notice(
            "hover source=position-timer clickMonitor=\(self.clickMonitor != nil, privacy: .public) ignoresMouse=\(self.panel.ignoresMouseEvents, privacy: .public)"
        )
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLog.screen.notice("screen parameters changed")
            ScreenGeometry.logScreens()
            self?.applyFrame(reason: "screen-change")
            self?.reveal()
        }
        NotificationCenter.default.addObserver(
            forName: .notchlingSettingsChanged,
            object: model.settings,
            queue: .main
        ) { [weak self] _ in
            self?.applyFrame(reason: "settings")
        }
        performLaunchPeek()
    }

    func open(pin: Bool) {
        AppLog.panel.notice("open pin=\(pin, privacy: .public) expansion=\(String(format: "%.3f", self.spring.value), privacy: .public)")
        if pin {
            model.panel.pinned = true
            peekWork?.cancel()
        }
        outsideSince = nil
        spring.target = 1
        reveal()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spring.snap()
            applyFrame(reason: "open-reduced")
            updateExpansionSideEffects()
            return
        }
        startSpring()
    }

    func togglePin() {
        if model.panel.pinned {
            model.panel.pinned = false
            AppLog.panel.notice("unpinned")
        } else {
            open(pin: true)
        }
    }

    private func close() {
        AppLog.panel.notice("close pinned=\(self.model.panel.pinned, privacy: .public)")
        model.panel.pinned = false
        pointerInside = false
        outsideSince = nil
        spring.target = 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spring.snap()
            applyFrame(reason: "close-reduced")
            updateExpansionSideEffects()
            return
        }
        startSpring()
    }

    private func wireActions() {
        model.actions.openPinned = { [weak self] in self?.open(pin: true) }
        model.actions.togglePin = { [weak self] in self?.togglePin() }
        model.actions.collapse = { [weak self] in self?.close() }
        model.actions.share = { [weak self] urls in self?.share(urls) }
        model.actions.airDrop = { [weak self] urls in self?.airDrop(urls) }
        model.mirror.onLayoutChange = { [weak self] in self?.applyFrame(reason: "mirror") }
    }

    private func performLaunchPeek() {
        AppLog.panel.notice("launch peek")
        open(pin: false)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if self.model.panel.pinned || self.pointerInside { return }
            if Self.containsClosed(mouse, self.stayRect()) { return }
            AppLog.panel.notice("launch peek end")
            self.close()
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    /// One timer. Screen coordinates. The open panel's hit rect is the fully expanded
    /// frame plus a margin, so the spring and the screen's top edge cannot flap the state.
    private func evaluateHover() {
        let mouse = NSEvent.mouseLocation
        let staying = Self.containsClosed(mouse, stayRect())
        if pointerInside {
            if staying || model.panel.pinned {
                outsideSince = nil
                return
            }
            let now = CACurrentMediaTime()
            if outsideSince == nil {
                outsideSince = now
                AppLog.panel.notice(
                    "hover outside mouse=\(Self.pointString(mouse), privacy: .public) stay=\(Self.rectString(self.stayRect()), privacy: .public) window=\(Self.rectString(self.panel.frame), privacy: .public)"
                )
                return
            }
            if now - (outsideSince ?? now) < closeDelay { return }
            pointerInside = false
            outsideSince = nil
            AppLog.panel.notice(
                "hover exit mouse=\(Self.pointString(mouse), privacy: .public) stay=\(Self.rectString(self.stayRect()), privacy: .public) window=\(Self.rectString(self.panel.frame), privacy: .public)"
            )
            close()
            return
        }

        let openish = spring.target > 0.5 || spring.value > 0.35
        let arm = openish ? stayRect() : armRect()
        guard Self.containsClosed(mouse, arm) else { return }
        pointerInside = true
        outsideSince = nil
        peekWork?.cancel()
        AppLog.panel.notice(
            "hover enter mouse=\(Self.pointString(mouse), privacy: .public) arm=\(Self.rectString(arm), privacy: .public) window=\(Self.rectString(self.panel.frame), privacy: .public)"
        )
        guard model.settings.hoverOpens || model.panel.pinned else {
            AppLog.panel.notice("hover ignored because hover-open is off")
            return
        }
        if spring.target < 1 {
            open(pin: model.panel.pinned)
        }
    }

    private func handleClick(source: String) {
        let now = CACurrentMediaTime()
        if now - lastClickAt < 0.08 { return }
        lastClickAt = now
        let mouse = NSEvent.mouseLocation
        let onPill = Self.containsClosed(mouse, armRect())
        let panelOpen = spring.value > 0.25 || spring.target > 0.5 || model.panel.pinned
        let onOpen = panelOpen && Self.containsClosed(mouse, stayRect())
        AppLog.panel.notice(
            "click source=\(source, privacy: .public) mouse=\(Self.pointString(mouse), privacy: .public) onPill=\(onPill, privacy: .public) onOpen=\(onOpen, privacy: .public) pinned=\(self.model.panel.pinned, privacy: .public) expansion=\(String(format: "%.3f", self.spring.value), privacy: .public) window=\(Self.rectString(self.panel.frame), privacy: .public)"
        )
        if onPill && spring.value < 0.45 {
            pointerInside = true
            outsideSince = nil
            open(pin: true)
            return
        }
        guard panelOpen, !onOpen else { return }
        AppLog.panel.notice("click outside, unpin")
        close()
    }

    private func reveal() {
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.level = Self.notchLevel()
        panel.orderFrontRegardless()
    }

    private func armRect() -> NSRect {
        padded(currentFrames()?.collapsed ?? panel.frame, 6)
    }

    private func stayRect() -> NSRect {
        padded(currentFrames()?.expanded ?? panel.frame, exitMargin)
    }

    private func padded(_ rect: NSRect, _ margin: CGFloat) -> NSRect {
        rect.insetBy(dx: -margin, dy: -margin)
    }

    /// Closed on every edge. `CGRect.contains` excludes maxX/maxY, so a cursor on the
    /// menu-bar edge (y == screen height) was counted as outside the open panel.
    private static func containsClosed(_ point: NSPoint, _ rect: NSRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private func startSpring() {
        guard springTimer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickSpring()
        }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }

    private func tickSpring() {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, max(1.0 / 120.0, now - lastTick))
        lastTick = now
        let settled = spring.step(dt: CGFloat(dt))
        applyFrame(reason: "spring")
        updateExpansionSideEffects()
        if settled {
            springTimer?.invalidate()
            springTimer = nil
            AppLog.panel.notice(
                "spring settled value=\(String(format: "%.3f", self.spring.value), privacy: .public) frame=\(Self.rectString(self.panel.frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public)"
            )
            placeHostingView(reason: "settled")
        }
    }

    private func applyFrame(reason: String) {
        guard let frames = currentFrames() else {
            AppLog.panel.error("applyFrame skipped, no screen reason=\(reason, privacy: .public)")
            return
        }
        let t = min(1, max(0, spring.value))
        var width = frames.collapsed.width + (frames.expanded.width - frames.collapsed.width) * t
        let height = frames.collapsed.height + (frames.expanded.height - frames.collapsed.height) * t
        width = min(width, frames.expanded.width)
        let requested = interpolated(frames: frames, width: width, height: height)
        panel.ignoresMouseEvents = false
        panel.setFrame(requested, display: true)
        placeHostingView(reason: reason)
        model.panel.expansion = t
        model.panel.notchHeight = frames.obscuredTop
        model.panel.chin = frames.chin
        model.panel.hasNotch = frames.hardware
        let actual = Self.rectString(panel.frame)
        let wanted = Self.rectString(requested)
        let sizeJump = abs(panel.frame.width - lastLoggedSize.width) >= 20
            || abs(panel.frame.height - lastLoggedSize.height) >= 12
        if reason != "spring" || sizeJump {
            lastLoggedSize = panel.frame.size
            AppLog.panel.notice(
                "frame reason=\(reason, privacy: .public) t=\(String(format: "%.3f", t), privacy: .public) requested=\(wanted, privacy: .public) actual=\(actual, privacy: .public) visible=\(self.panel.isVisible, privacy: .public) level=\(self.panel.level.rawValue, privacy: .public) mouse=\(Self.pointString(NSEvent.mouseLocation), privacy: .public)"
            )
            if panel.frame.integral != requested.integral {
                AppLog.panel.error(
                    "frame was adjusted requested=\(wanted, privacy: .public) actual=\(actual, privacy: .public)"
                )
            }
        }
    }

    private func placeHostingView(reason: String) {
        guard let host = panel.contentView else {
            AppLog.panel.error("SwiftUI host missing")
            return
        }
        let local = NSRect(origin: .zero, size: panel.frame.size)
        if host.frame != local {
            host.frame = local
        }
        host.layoutSubtreeIfNeeded()
        let origin = host.frame.origin
        let bounds = host.bounds.size
        let misplaced = abs(origin.x) > 0.5 || abs(origin.y) > 0.5
        let empty = bounds.width < 2 || bounds.height < 2
        let shouldLog = reason != "spring"
        guard shouldLog else { return }
        AppLog.panel.notice(
            "SwiftUI host reason=\(reason, privacy: .public) local=\(Self.rectString(host.frame), privacy: .public) bounds=\(String(format: "%.1fx%.1f", bounds.width, bounds.height), privacy: .public) hidden=\(host.isHidden, privacy: .public) alpha=\(String(format: "%.2f", self.panel.alphaValue), privacy: .public) expansion=\(String(format: "%.3f", self.spring.value), privacy: .public)"
        )
        if misplaced {
            AppLog.panel.error(
                "SwiftUI host origin is not in window coordinates local=\(Self.rectString(host.frame), privacy: .public)"
            )
        }
        if empty {
            AppLog.panel.error("SwiftUI host bounds are empty")
        }
    }

    private func currentFrames() -> PanelFrames? {
        guard let placement = ScreenGeometry.placement() else { return nil }
        let mirrorVisible = model.settings.mirrorEnabled && model.mirror.wantsPreview
        let expandedSize = PanelLayout.expandedSize(
            notchHeight: placement.obscuredTop,
            settings: model.settings,
            mirrorVisible: mirrorVisible
        )
        let collapsed = placement.collapsedFrame
        let width = min(max(expandedSize.width, collapsed.width), max(collapsed.width, placement.screen.frame.width - 16))
        let height = max(expandedSize.height, collapsed.height)
        let expanded = interpolated(
            frames: PanelFrames(
                collapsed: collapsed,
                expanded: collapsed,
                obscuredTop: placement.obscuredTop,
                chin: placement.chin,
                hardware: placement.isHardwareNotch
            ),
            width: width,
            height: height
        )
        return PanelFrames(
            collapsed: collapsed,
            expanded: expanded,
            obscuredTop: placement.obscuredTop,
            chin: placement.chin,
            hardware: placement.isHardwareNotch
        )
    }

    private func interpolated(frames: PanelFrames, width: CGFloat, height: CGFloat) -> NSRect {
        var x = frames.collapsed.midX - (width / 2)
        guard let screen = ScreenGeometry.placement()?.screen else {
            return NSRect(x: x, y: frames.collapsed.maxY - height, width: max(width, 1), height: max(height, 1))
        }
        let minX = screen.frame.minX + 8
        let maxX = screen.frame.maxX - width - 8
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: max(width, 1), height: max(height, 1))
    }

    private func updateExpansionSideEffects() {
        let open = spring.value > 0.45
        if open && !expandedAbove {
            expandedAbove = true
            model.calendar.refreshIfAuthorized()
            model.battery.refresh()
            model.mirror.panelDidExpand()
        } else if !open && expandedAbove {
            expandedAbove = false
            model.mirror.panelDidCollapse()
        }
    }

    private static func notchLevel() -> NSWindow.Level {
        let aboveMenu = NSWindow.Level.mainMenu.rawValue + 3
        let raw = max(NSWindow.Level.statusBar.rawValue, aboveMenu)
        return NSWindow.Level(rawValue: raw)
    }

    private static func rectString(_ rect: NSRect) -> String {
        String(format: "{{%.1f, %.1f}, {%.1f, %.1f}}", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private static func pointString(_ point: NSPoint) -> String {
        String(format: "{%.1f, %.1f}", point.x, point.y)
    }

    private func share(_ urls: [URL]) {
        guard let view = panel.contentView, !urls.isEmpty else { return }
        NSApp.activate()
        panel.makeKey()
        let picker = NSSharingServicePicker(items: urls)
        let rect = NSRect(x: view.bounds.midX, y: 28, width: 2, height: 2)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    private func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let airDrop = NSSharingService.Name(rawValue: "com.apple.share.AirDrop.send")
        if let service = NSSharingService(named: airDrop), service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
            return
        }
        share(urls)
    }
}
