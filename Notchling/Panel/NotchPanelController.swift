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
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onCollapsedClick: (() -> Void)?
    private var tracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        onCollapsedClick?()
        super.mouseDown(with: event)
    }
}

final class NotchPanelController {
    private let model: AppModel
    private let panel: NotchPanel
    private var spring = SpringValue()
    private var springTimer: Timer?
    private var hoverTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pointerInside = false
    private var expandedAbove = false
    private var lastTick = CACurrentMediaTime()
    private var lastLoggedFrame = ""
    private var lastLoggedSize = NSSize.zero

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
        panel.acceptsMouseMovedEvents = true
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
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        self.panel = panel
        host.onMouseEntered = { [weak self] in self?.pointerEntered(source: "tracking") }
        host.onMouseExited = { [weak self] in self?.pointerExited(source: "tracking") }
        host.onCollapsedClick = { [weak self] in self?.clickCollapsed() }
        host.updateTrackingAreas()
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
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.evaluateHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.evaluateHover()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.evaluateHover()
            }
        }
        AppLog.panel.notice(
            "hover monitors local=\(self.localMouseMonitor != nil, privacy: .public) global=\(self.globalMouseMonitor != nil, privacy: .public) ignoresMouse=\(self.panel.ignoresMouseEvents, privacy: .public)"
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
        collapseWork?.cancel()
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
        AppLog.panel.notice("close")
        model.panel.pinned = false
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
            if self.model.panel.pinned || self.pointerInside { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { return }
            AppLog.panel.notice("launch peek end")
            self.close()
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    private func clickCollapsed() {
        guard spring.value < 0.45 else { return }
        AppLog.panel.notice("collapsed click")
        open(pin: true)
    }

    private func reveal() {
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.level = Self.notchLevel()
        panel.orderFrontRegardless()
    }

    private func evaluateHover() {
        let mouse = NSEvent.mouseLocation
        let inside = panel.frame.contains(mouse)
        if inside && !pointerInside {
            pointerInside = true
            pointerEntered(source: "location")
        } else if !inside && pointerInside {
            pointerInside = false
            pointerExited(source: "location")
        }
    }

    private func pointerEntered(source: String) {
        pointerInside = true
        AppLog.panel.notice(
            "hover enter source=\(source, privacy: .public) mouse=\(Self.pointString(NSEvent.mouseLocation), privacy: .public) frame=\(Self.rectString(self.panel.frame), privacy: .public)"
        )
        collapseWork?.cancel()
        peekWork?.cancel()
        guard model.settings.hoverOpens || model.panel.pinned else {
            AppLog.panel.notice("hover ignored because hover-open is off")
            return
        }
        if spring.target < 1 {
            open(pin: model.panel.pinned)
        }
    }

    private func pointerExited(source: String) {
        pointerInside = false
        AppLog.panel.notice("hover exit source=\(source, privacy: .public)")
        guard !model.panel.pinned else { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { return }
            if self.model.panel.pinned { return }
            self.close()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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
        }
    }

    private func applyFrame(reason: String) {
        guard let placement = ScreenGeometry.placement() else {
            AppLog.panel.error("applyFrame skipped, no screen reason=\(reason, privacy: .public)")
            return
        }
        let mirrorVisible = model.settings.mirrorEnabled && model.mirror.wantsPreview
        let expanded = PanelLayout.expandedSize(
            notchHeight: placement.obscuredTop,
            settings: model.settings,
            mirrorVisible: mirrorVisible
        )
        let collapsed = placement.collapsedFrame
        let t = min(1, max(0, spring.value))
        let expandedWidth = max(expanded.width, collapsed.width)
        let expandedHeight = max(expanded.height, collapsed.height)
        var width = collapsed.width + (expandedWidth - collapsed.width) * t
        let height = collapsed.height + (expandedHeight - collapsed.height) * t
        let maxWidth = max(collapsed.width, placement.screen.frame.width - 16)
        width = min(width, maxWidth)
        var x = collapsed.midX - (width / 2)
        let minX = placement.screen.frame.minX + 8
        let maxX = placement.screen.frame.maxX - width - 8
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        let y = placement.screen.frame.maxY - height
        let requested = NSRect(x: x, y: y, width: max(width, 1), height: max(height, 1))
        panel.ignoresMouseEvents = false
        panel.setFrame(requested, display: true)
        if let host = panel.contentView {
            host.frame = panel.contentRect(forFrameRect: panel.frame)
            host.layoutSubtreeIfNeeded()
        }
        model.panel.expansion = t
        model.panel.notchHeight = placement.obscuredTop
        model.panel.chin = placement.chin
        model.panel.hasNotch = placement.isHardwareNotch
        let actual = Self.rectString(panel.frame)
        let wanted = Self.rectString(requested)
        let sizeJump = abs(panel.frame.width - lastLoggedSize.width) >= 20
            || abs(panel.frame.height - lastLoggedSize.height) >= 12
        if reason != "spring" || sizeJump {
            lastLoggedFrame = actual
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
