import AppKit
import ApplicationServices
import Combine
import SwiftUI

enum HUDKind {
    case volume
    case brightness

    var title: String {
        switch self {
        case .volume: return "Lautstärke"
        case .brightness: return "Helligkeit"
        }
    }

    func symbol(level: Double) -> String {
        switch self {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if level <= 0.001 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

final class HUDController: ObservableObject {
    @Published var kind: HUDKind = .volume
    @Published var level: Double = 0
    @Published var statusDetail = "Aus."

    private let settings: SettingsStore
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var panel: NSPanel?
    private var lastVolume: Float?
    private var lastBrightness: Float = -1
    private var primed = false
    private var savedVolume: Float = 0.25
    private var brightnessBlocked = false
    private var sawPrivateBrightness = false
    private var privateBrightnessUnavailable = false
    private let step: Float = 1.0 / 16.0
    private let probeKey = "nl.brightness.probe"
    private let crashedKey = "nl.brightness.crashed"

    init(settings: SettingsStore) {
        self.settings = settings
        if UserDefaults.standard.bool(forKey: probeKey) {
            UserDefaults.standard.set(true, forKey: crashedKey)
            UserDefaults.standard.set(false, forKey: probeKey)
            brightnessBlocked = true
            AppLog.general.error("Skipping private brightness API after a failed probe")
        } else if UserDefaults.standard.bool(forKey: crashedKey) {
            brightnessBlocked = true
        }
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: .notchlingSettingsChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            self?.apply(prompt: true)
        }
        apply(prompt: false)
    }

    func requestAccessibility() {
        _ = trusted(prompt: true)
        refreshStatus()
        if settings.hudEnabled {
            installTapIfTrusted()
        }
    }

    func preview() {
        let value = Double(VolumeControl.read() ?? 0.4)
        show(kind: .volume, level: value)
    }

    private func apply(prompt: Bool) {
        guard settings.hudEnabled else {
            stopTap()
            stopPolling()
            hide()
            statusDetail = "Aus. Die Systemanzeige bleibt unverändert."
            return
        }
        if prompt, !trusted(prompt: false) {
            _ = trusted(prompt: true)
        }
        if trusted(prompt: false) {
            installTapIfTrusted()
        } else {
            stopTap()
        }
        startPolling()
        refreshStatus()
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        primed = false
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        primed = false
    }

    private func poll() {
        guard settings.hudEnabled else { return }
        if trusted(prompt: false), eventTap == nil {
            installTapIfTrusted()
        }
        let volume = VolumeControl.read()
        let brightness = currentBrightness()
        if !primed {
            lastVolume = volume
            lastBrightness = brightness
            primed = true
            refreshStatus()
            return
        }
        if let volume, let lastVolume, abs(volume - lastVolume) > 0.02 {
            show(kind: .volume, level: Double(volume))
        }
        if brightness >= 0, lastBrightness >= 0, abs(brightness - lastBrightness) > 0.02 {
            show(kind: .brightness, level: Double(brightness))
        }
        lastVolume = volume
        if brightness >= 0 {
            lastBrightness = brightness
        }
        refreshStatus()
    }

    private func currentBrightness() -> Float {
        let ioValue = NLDisplayBridge.readIOBrightness()
        if ioValue >= 0 { return ioValue }
        guard !brightnessBlocked, !privateBrightnessUnavailable else { return -1 }
        beginProbe()
        let value = NLDisplayBridge.readPrivateBrightness()
        endProbe()
        if value >= 0 {
            sawPrivateBrightness = true
            return value
        }
        privateBrightnessUnavailable = true
        return -1
    }

    private func writeBrightness(_ value: Float) -> Bool {
        if NLDisplayBridge.setIOBrightness(value) { return true }
        guard !brightnessBlocked, sawPrivateBrightness else { return false }
        beginProbe()
        let ok = NLDisplayBridge.setPrivateBrightness(value)
        endProbe()
        return ok
    }

    private func beginProbe() {
        UserDefaults.standard.set(true, forKey: probeKey)
        UserDefaults.standard.synchronize()
    }

    private func endProbe() {
        UserDefaults.standard.set(false, forKey: probeKey)
    }

    private func installTapIfTrusted() {
        guard eventTap == nil, trusted(prompt: false) else { return }
        let mask = CGEventMask(1 << CGEventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hudEventTap,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            statusDetail = "Ereignisfilter nicht verfügbar. Bedienungshilfen prüfen."
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        refreshStatus()
    }

    private func stopTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard settings.hudEnabled else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int32(data1 & 0x0000FFFF)
        let state = (keyFlags & 0xFF00) >> 8
        guard state == 0x0A else {
            return Unmanaged.passUnretained(event)
        }
        return applyKey(keyCode) ? nil : Unmanaged.passUnretained(event)
    }

    private func applyKey(_ keyCode: Int32) -> Bool {
        switch keyCode {
        case 0:
            let next = min(1, (VolumeControl.read() ?? 0) + step)
            guard VolumeControl.setVolume(next) else { return false }
            remember(volume: next)
            show(kind: .volume, level: Double(next))
            return true
        case 1:
            let next = max(0, (VolumeControl.read() ?? 0) - step)
            guard VolumeControl.setVolume(next) else { return false }
            remember(volume: next)
            show(kind: .volume, level: Double(next))
            return true
        case 7:
            let current = VolumeControl.read() ?? 0
            if current > 0.001 {
                savedVolume = current
                guard VolumeControl.setMuted(true) else { return false }
                _ = VolumeControl.setVolume(0)
                remember(volume: 0)
                show(kind: .volume, level: 0)
            } else {
                let restore = savedVolume > 0.001 ? savedVolume : 0.25
                guard VolumeControl.setVolume(restore) else { return false }
                _ = VolumeControl.setMuted(false)
                remember(volume: restore)
                show(kind: .volume, level: Double(restore))
            }
            return true
        case 2:
            let current = currentBrightness()
            guard current >= 0 else { return false }
            let next = min(1, current + step)
            guard writeBrightness(next) else { return false }
            lastBrightness = next
            show(kind: .brightness, level: Double(next))
            return true
        case 3:
            let current = currentBrightness()
            guard current >= 0 else { return false }
            let next = max(0, current - step)
            guard writeBrightness(next) else { return false }
            lastBrightness = next
            show(kind: .brightness, level: Double(next))
            return true
        default:
            return false
        }
    }

    private func remember(volume: Float) {
        lastVolume = volume
        primed = true
    }

    private func show(kind: HUDKind, level: Double) {
        self.kind = kind
        self.level = min(1, max(0, level))
        let panel = ensurePanel()
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let rect = NSRect(x: 0, y: 0, width: 280, height: 84)
        let panel = NSPanel(
            contentRect: rect,
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
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        let host = NSHostingView(rootView: HUDView(model: self))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = ScreenGeometry.placement()?.screen ?? NSScreen.main
        guard let screen else { return }
        let size = NSSize(width: 280, height: 84)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    private func trusted(prompt: Bool) -> Bool {
        if !prompt { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func refreshStatus() {
        let next: String
        if !settings.hudEnabled {
            next = "Aus. Die Systemanzeige bleibt unverändert."
        } else {
            let trust = trusted(prompt: false)
            let brightnessOK = lastBrightness >= 0 || sawPrivateBrightness
            if brightnessBlocked {
                next = trust
                    ? "Lautstärke wird ersetzt. Die private Helligkeitsschnittstelle wurde nach einem Fehler deaktiviert."
                    : "Ohne Bedienungshilfen bleibt die Systemanzeige sichtbar. Notchling zeigt zusätzlich die Lautstärke an."
            } else if trust {
                next = brightnessOK
                    ? "Bedienungshilfen aktiv. Lautstärke wird ersetzt, Helligkeit soweit der Mac sie freigibt."
                    : "Bedienungshilfen aktiv. Lautstärke wird ersetzt. Helligkeit ist auf diesem Mac nicht lesbar, die Tasten bleiben beim System."
            } else {
                next = "Ohne Bedienungshilfen bleibt die Systemanzeige sichtbar. Notchling zeigt zusätzlich eine eigene Anzeige."
            }
        }
        if statusDetail != next {
            statusDetail = next
        }
    }
}

private func hudEventTap(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HUDController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(event: event, type: type)
}

struct HUDView: View {
    @ObservedObject var model: HUDController

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.kind.symbol(level: model.level))
                .font(.system(size: 26, weight: .medium))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int((model.level * 100).rounded())) %")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(4, geo.size.width * CGFloat(model.level)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
