import Combine
import CoreGraphics
import Foundation

final class AppModel {
    let actions = PanelActions()
    let settings = SettingsStore()
    let panel = PanelState()
    let nowPlaying: NowPlayingController
    let calendar: CalendarController
    let shelf = FileShelfStore()
    let battery = BatteryMonitor()
    let hud: HUDController
    let mirror: MirrorController
    let launch = LaunchAtLoginManager()

    init() {
        nowPlaying = NowPlayingController(settings: settings)
        calendar = CalendarController(settings: settings)
        hud = HUDController(settings: settings)
        mirror = MirrorController(settings: settings)
    }
}

final class PanelState: ObservableObject {
    @Published var expansion: CGFloat = 0
    @Published var pinned = false
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false
}
