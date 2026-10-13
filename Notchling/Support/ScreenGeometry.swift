import AppKit

struct ScreenPlacement {
    var screen: NSScreen
    var notchRect: CGRect
    var isHardwareNotch: Bool
}

enum ScreenGeometry {
    static func placement() -> ScreenPlacement? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let notched = screens.map(metrics(for:)).first(where: \.isHardwareNotch) {
            return notched
        }
        let screen = NSScreen.main ?? screens[0]
        return metrics(for: screen)
    }

    static func metrics(for screen: NSScreen) -> ScreenPlacement {
        let left = normalized(screen.auxiliaryTopLeftArea ?? .zero, on: screen)
        let right = normalized(screen.auxiliaryTopRightArea ?? .zero, on: screen)
        let width = right.minX - left.maxX
        let height = max(left.height, max(right.height, screen.safeAreaInsets.top))
        if width > 80, width < 420, height > 12 {
            let rect = CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height)
            return ScreenPlacement(screen: screen, notchRect: rect, isHardwareNotch: true)
        }
        let size = CGSize(width: 200, height: max(32, screen.safeAreaInsets.top))
        let rect = CGRect(
            x: screen.frame.midX - (size.width / 2),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return ScreenPlacement(screen: screen, notchRect: rect, isHardwareNotch: false)
    }

    static func describe() -> String {
        NSScreen.screens.enumerated().map { index, screen in
            let placement = metrics(for: screen)
            return """
            Bildschirm \(index)
            frame=\(nsString(from: screen.frame))
            visible=\(nsString(from: screen.visibleFrame))
            safeTop=\(screen.safeAreaInsets.top)
            auxiliaryLeft=\(nsString(from: screen.auxiliaryTopLeftArea ?? .zero))
            auxiliaryRight=\(nsString(from: screen.auxiliaryTopRightArea ?? .zero))
            notch=\(nsString(from: placement.notchRect)) hardware=\(placement.isHardwareNotch)
            """
        }.joined(separator: "\n\n")
    }

    private static func normalized(_ area: CGRect, on screen: NSScreen) -> CGRect {
        if area.width <= 0 || area.height <= 0 { return area }
        if abs(area.maxY - screen.frame.maxY) < 4 { return area }
        if area.minY >= 0, area.minY < 80, area.height < 80, screen.frame.height > 200 {
            var flipped = area
            flipped.origin.y = screen.frame.maxY - area.maxY
            return flipped
        }
        return area
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
