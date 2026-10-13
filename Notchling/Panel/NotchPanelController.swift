import AppKit
import QuartzCore
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
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
    private var keyMonitor: Any?
    private var pointerInside = false
    private var expandedAbove = false
    private var lastTick = CACurrentMediaTime()

    init(model: AppModel) {
        self.model = model
        let initial = ScreenGeometry.placement()?.notchRect ?? CGRect(x: 0, y: 0, width: 200, height: 32)
        let panel = NotchPanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
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
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        self.panel = panel
        wireActions()
    }

    func start() {
        applyFrame()
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.evaluateHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyFrame()
        }
        NotificationCenter.default.addObserver(
            forName: .notchlingSettingsChanged,
            object: model.settings,
            queue: .main
        ) { [weak self] _ in
            self?.applyFrame()
        }
        AppLog.general.info("\(ScreenGeometry.describe(), privacy: .public)")
    }

    func open(pin: Bool) {
        if pin { model.panel.pinned = true }
        collapseWork?.cancel()
        spring.target = 1
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spring.snap()
            applyFrame()
            updateExpansionSideEffects()
            return
        }
        startSpring()
    }

    func togglePin() {
        if model.panel.pinned {
            model.panel.pinned = false
        } else {
            open(pin: true)
        }
    }

    private func close() {
        model.panel.pinned = false
        spring.target = 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            spring.snap()
            applyFrame()
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
        model.mirror.onLayoutChange = { [weak self] in self?.applyFrame() }
    }

    private func evaluateHover() {
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        if inside && !pointerInside {
            pointerInside = true
            hoverEntered()
        } else if !inside && pointerInside {
            pointerInside = false
            hoverExited()
        }
    }

    private func hoverEntered() {
        collapseWork?.cancel()
        guard model.settings.hoverOpens || model.panel.pinned else { return }
        if spring.target < 1 {
            open(pin: model.panel.pinned)
        }
    }

    private func hoverExited() {
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
        applyFrame()
        updateExpansionSideEffects()
        if settled {
            springTimer?.invalidate()
            springTimer = nil
        }
    }

    private func applyFrame() {
        guard let placement = ScreenGeometry.placement() else { return }
        let mirrorVisible = model.settings.mirrorEnabled && model.mirror.wantsPreview
        let expanded = PanelLayout.expandedSize(
            notchHeight: placement.notchRect.height,
            settings: model.settings,
            mirrorVisible: mirrorVisible
        )
        let collapsed = placement.notchRect
        let t = min(1, max(0, spring.value))
        var width = collapsed.width + (expanded.width - collapsed.width) * t
        let height = collapsed.height + (expanded.height - collapsed.height) * t
        let maxWidth = max(collapsed.width, placement.screen.frame.width - 16)
        width = min(width, maxWidth)
        var x = collapsed.midX - (width / 2)
        if t > 0.001 {
            let minX = placement.screen.frame.minX + 8
            let maxX = placement.screen.frame.maxX - width - 8
            if maxX >= minX {
                x = min(max(x, minX), maxX)
            }
        }
        let y = placement.screen.frame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: max(width, 1), height: max(height, 1)), display: true)
        model.panel.expansion = t
        model.panel.notchHeight = collapsed.height
        model.panel.hasNotch = placement.isHardwareNotch
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
