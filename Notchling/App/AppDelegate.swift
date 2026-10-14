import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    let model = AppModel()
    private var notch: NotchPanelController?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    override init() {
        super.init()
        AppDelegate.shared = self
        AppLog.lifecycle.notice("Notchling launched")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.lifecycle.notice("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        let notch = NotchPanelController(model: model)
        self.notch = notch
        notch.start()
        settingsWindow = SettingsWindowController(model: model)
        model.actions.showSettings = { [weak self] in
            self?.settingsWindow?.show()
        }
        statusItem = StatusItemController(model: model, notch: notch)
        model.nowPlaying.start()
        model.calendar.start()
        model.battery.start()
        model.shelf.load()
        model.hud.start()
        model.mirror.start()
        AppLog.lifecycle.notice("services started")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.mirror.stop()
    }
}
