import SwiftUI

@main
struct NotchlingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsSceneView()
        }
    }
}

private struct SettingsSceneView: View {
    var body: some View {
        if let model = AppDelegate.shared?.model {
            SettingsView(
                settings: model.settings,
                launch: model.launch,
                hud: model.hud,
                panel: model.panel
            )
        } else {
            ProgressView("Notchling")
                .frame(width: 320, height: 120)
        }
    }
}
