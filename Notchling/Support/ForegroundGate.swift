import AppKit

/// Calendar and camera prompts need a regular activation policy on macOS 26.
/// The app stays an accessory (no Dock icon) the rest of the time.
final class ForegroundGate {
    static let shared = ForegroundGate()
    private var depth = 0

    func begin() {
        depth += 1
        if depth == 1 {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    func end() {
        depth = max(0, depth - 1)
        if depth == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
