import AppKit
import SwiftUI

final class SettingsWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        let root = SettingsView(
            settings: model.settings,
            launch: model.launch,
            hud: model.hud,
            panel: model.panel
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Notchling Einstellungen"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 660))
        window.contentMinSize = NSSize(width: 500, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
