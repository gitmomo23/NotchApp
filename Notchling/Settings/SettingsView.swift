import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var launch: LaunchAtLoginManager
    @ObservedObject var hud: HUDController
    @ObservedObject var panel: PanelState

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Beim Anmelden öffnen", isOn: launchBinding)
                Text(launch.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Beim Darüberfahren öffnen", isOn: $settings.hoverOpens)
                Text(panel.hasNotch
                    ? "Die Notch dieses Bildschirms wird abgedeckt."
                    : "Keine Notch erkannt. Notchling sitzt als Insel oben in der Mitte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Funktionen") {
                Toggle("Wiedergabe", isOn: $settings.nowPlayingEnabled)
                Text("Cover, Fortschritt, Play/Pause und Titelwechsel. Zuerst die Systemwiedergabe, sonst Musik und Spotify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Kalender", isOn: $settings.calendarEnabled)
                Toggle("Dateiablage", isOn: $settings.shelfEnabled)
                Text("Abgelegte Dateien bleiben erhalten und lassen sich per AirDrop oder Teilen verschicken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Akku", isOn: $settings.batteryEnabled)
                Toggle("Spiegel", isOn: $settings.mirrorEnabled)
                Text("Die Kamera startet erst, wenn du den Spiegel im Panel einschaltest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("HUD") {
                Toggle("Lautstärke- und Helligkeits-HUD", isOn: $settings.hudEnabled)
                Text(hud.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Bedienungshilfen anfragen") { hud.requestAccessibility() }
                    Button("Testanzeige") { hud.preview() }
                }
            }
            Section("Über") {
                LabeledContent("Version", value: version)
                Text("Eigenständige Neuimplementierung für die MacBook-Pro-Notch. Enthält keinen Code aus NotchNook oder boring.notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 580)
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { launch.isEnabled }, set: { launch.setEnabled($0) })
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
