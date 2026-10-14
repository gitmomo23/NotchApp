import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private weak var notch: NotchPanelController?
    private let item: NSStatusItem

    init(model: AppModel, notch: NotchPanelController) {
        self.model = model
        self.notch = notch
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.image = Self.menuImage()
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.button?.title = "NL"
        item.button?.toolTip = "Notchling"
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        AppLog.lifecycle.notice("status item visible=\(self.item.isVisible, privacy: .public)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "Panel öffnen", #selector(openNotch), "")
        add(menu, model.panel.pinned ? "Loslösen" : "Anheften", #selector(togglePin), "")
        menu.addItem(.separator())
        let settingsItem = add(menu, "Einstellungen…", #selector(showSettings), ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        add(menu, "Bildschirmgeometrie kopieren", #selector(copyGeometry), "")
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let about = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        add(menu, "Beenden", #selector(quit), "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func openNotch() {
        notch?.open(pin: true)
    }

    @objc private func togglePin() {
        notch?.togglePin()
    }

    @objc private func showSettings() {
        model.actions.showSettings()
    }

    @objc private func copyGeometry() {
        let text = ScreenGeometry.describe()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 6, width: 15, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
