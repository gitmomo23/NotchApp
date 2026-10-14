import AppKit

struct ScreenPlacement {
    var screen: NSScreen
    var notchRect: CGRect
    var collapsedFrame: CGRect
    var obscuredTop: CGFloat
    var chin: CGFloat
    var isHardwareNotch: Bool
}

enum ScreenGeometry {
    /// Extra points drawn below the menu bar so the closed pill is on real pixels.
    static let chin: CGFloat = 22

    static func placement() -> ScreenPlacement? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let ranked = screens.map(metrics(for:))
        if let notched = ranked.first(where: \.isHardwareNotch) {
            return notched
        }
        if let builtIn = ranked.first(where: { isBuiltIn($0.screen) }) {
            return builtIn
        }
        if let main = NSScreen.main, let match = ranked.first(where: { $0.screen == main }) {
            return match
        }
        return ranked[0]
    }

    static func metrics(for screen: NSScreen) -> ScreenPlacement {
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let safeTop = max(0, screen.safeAreaInsets.top)
        let left = placed(screen.auxiliaryTopLeftArea ?? .zero, on: screen)
        let right = placed(screen.auxiliaryTopRightArea ?? .zero, on: screen)
        let gap = notchGap(left: left, right: right, screen: screen)
        let gapHeight = gap?.height ?? 0
        let obscured = max(menuBar, safeTop, gapHeight, 24)
        let height = max(obscured + chin, menuBar + chin, 46)
        let hardware = gap != nil
        let width: CGFloat
        let centerX: CGFloat
        if let gap {
            width = min(320, max(200, gap.width))
            centerX = gap.midX
        } else {
            width = 200
            centerX = screen.frame.midX
        }
        var x = centerX - (width / 2)
        let minX = screen.frame.minX + 4
        let maxX = screen.frame.maxX - width - 4
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        let collapsed = CGRect(x: x, y: screen.frame.maxY - height, width: width, height: height)
        let notchRect = gap ?? collapsed
        return ScreenPlacement(
            screen: screen,
            notchRect: notchRect,
            collapsedFrame: collapsed,
            obscuredTop: obscured,
            chin: height - obscured,
            isHardwareNotch: hardware
        )
    }

    static func logScreens() {
        let screens = NSScreen.screens
        AppLog.screen.notice("screen count=\(screens.count, privacy: .public)")
        if screens.isEmpty {
            AppLog.screen.error("NSScreen.screens is empty")
            return
        }
        for (index, screen) in screens.enumerated() {
            let rawLeft = screen.auxiliaryTopLeftArea ?? .zero
            let rawRight = screen.auxiliaryTopRightArea ?? .zero
            let placement = metrics(for: screen)
            AppLog.screen.notice(
                "screen[\(index, privacy: .public)] name=\(screen.localizedName, privacy: .public) scale=\(String(format: "%.2f", screen.backingScaleFactor), privacy: .public) frame=\(Self.nsString(from: screen.frame), privacy: .public) visible=\(Self.nsString(from: screen.visibleFrame), privacy: .public) safeTop=\(String(format: "%.1f", screen.safeAreaInsets.top), privacy: .public)"
            )
            AppLog.screen.notice(
                "screen[\(index, privacy: .public)] rawLeft=\(Self.nsString(from: rawLeft), privacy: .public) rawRight=\(Self.nsString(from: rawRight), privacy: .public) notch=\(Self.nsString(from: placement.notchRect), privacy: .public) collapsed=\(Self.nsString(from: placement.collapsedFrame), privacy: .public) hardware=\(placement.isHardwareNotch, privacy: .public) obscured=\(String(format: "%.1f", placement.obscuredTop), privacy: .public) chin=\(String(format: "%.1f", placement.chin), privacy: .public)"
            )
        }
        if let chosen = placement() {
            AppLog.screen.notice(
                "chosen name=\(chosen.screen.localizedName, privacy: .public) collapsed=\(Self.nsString(from: chosen.collapsedFrame), privacy: .public) hardware=\(chosen.isHardwareNotch, privacy: .public)"
            )
        }
    }

    static func describe() -> String {
        NSScreen.screens.enumerated().map { index, screen in
            let placement = metrics(for: screen)
            return """
            Bildschirm \(index) \(screen.localizedName)
            frame=\(nsString(from: screen.frame))
            visible=\(nsString(from: screen.visibleFrame))
            safeTop=\(screen.safeAreaInsets.top)
            auxiliaryLeft=\(nsString(from: screen.auxiliaryTopLeftArea ?? .zero))
            auxiliaryRight=\(nsString(from: screen.auxiliaryTopRightArea ?? .zero))
            notch=\(nsString(from: placement.notchRect)) hardware=\(placement.isHardwareNotch)
            collapsed=\(nsString(from: placement.collapsedFrame)) obscured=\(placement.obscuredTop) chin=\(placement.chin)
            """
        }.joined(separator: "\n\n")
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName.lowercased()
        return name.contains("built-in") || name.contains("eingebaut") || name.contains("liquid retina")
    }

    /// Map an auxiliary rect into the screen's top band. The SDK has reported these
    /// both in global coordinates and as a small rect whose y sits near the top edge.
    private static func placed(_ raw: CGRect, on screen: NSScreen) -> CGRect {
        guard raw.width > 1, raw.height > 1 else { return .zero }
        let local = CGRect(
            x: screen.frame.minX + raw.origin.x,
            y: screen.frame.minY + raw.origin.y,
            width: raw.width,
            height: raw.height
        )
        let flippedGlobal = CGRect(
            x: raw.origin.x,
            y: screen.frame.maxY - raw.maxY,
            width: raw.width,
            height: raw.height
        )
        let flippedLocal = CGRect(
            x: screen.frame.minX + raw.origin.x,
            y: screen.frame.maxY - raw.maxY,
            width: raw.width,
            height: raw.height
        )
        return [raw, local, flippedGlobal, flippedLocal].first { rect in
            let midY = rect.midY
            return midY <= screen.frame.maxY + 2
                && midY >= screen.frame.maxY - 120
                && rect.maxX > screen.frame.minX
                && rect.minX < screen.frame.maxX
        } ?? .zero
    }

    private static func notchGap(left: CGRect, right: CGRect, screen: NSScreen) -> CGRect? {
        guard left.width > 1, right.width > 1 else { return nil }
        let innerLeft = left.midX <= right.midX ? left.maxX : right.maxX
        let innerRight = left.midX <= right.midX ? right.minX : left.minX
        let width = innerRight - innerLeft
        guard width > 60, width < 640 else { return nil }
        let height = max(left.height, right.height, screen.safeAreaInsets.top)
        guard height > 8, height < 80 else { return nil }
        return CGRect(x: innerLeft, y: screen.frame.maxY - height, width: width, height: height)
    }

    private static func nsString(from rect: CGRect) -> String {
        String(format: "{{%.1f, %.1f}, {%.1f, %.1f}}", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}

enum PanelLayout {
    static func expandedSize(notchHeight: CGFloat, settings: SettingsStore, mirrorVisible: Bool) -> CGSize {
        var width: CGFloat = 36
        var sections = 0
        if settings.nowPlayingEnabled {
            width += 300
            sections += 1
        }
        if settings.calendarEnabled {
            width += 200
            sections += 1
        }
        if settings.shelfEnabled || settings.batteryEnabled || settings.mirrorEnabled {
            width += 216
            sections += 1
        }
        if sections == 0 {
            width = 320
        } else {
            width += CGFloat(max(0, sections - 1)) * 18
        }
        let height = notchHeight + (mirrorVisible ? 330 : 216)
        return CGSize(width: width, height: height)
    }
}
