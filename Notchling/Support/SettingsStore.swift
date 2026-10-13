import Combine
import Foundation

extension Notification.Name {
    static let notchlingSettingsChanged = Notification.Name("nl.settings.changed")
}

final class SettingsStore: ObservableObject {
    @Published var nowPlayingEnabled: Bool { didSet { persist(nowPlayingEnabled, key: Keys.nowPlaying, old: oldValue) } }
    @Published var calendarEnabled: Bool { didSet { persist(calendarEnabled, key: Keys.calendar, old: oldValue) } }
    @Published var shelfEnabled: Bool { didSet { persist(shelfEnabled, key: Keys.shelf, old: oldValue) } }
    @Published var batteryEnabled: Bool { didSet { persist(batteryEnabled, key: Keys.battery, old: oldValue) } }
    @Published var hudEnabled: Bool { didSet { persist(hudEnabled, key: Keys.hud, old: oldValue) } }
    @Published var mirrorEnabled: Bool { didSet { persist(mirrorEnabled, key: Keys.mirror, old: oldValue) } }
    @Published var hoverOpens: Bool { didSet { persist(hoverOpens, key: Keys.hover, old: oldValue) } }

    init() {
        let defaults = UserDefaults.standard
        nowPlayingEnabled = Self.bool(Keys.nowPlaying, default: true, defaults: defaults)
        calendarEnabled = Self.bool(Keys.calendar, default: true, defaults: defaults)
        shelfEnabled = Self.bool(Keys.shelf, default: true, defaults: defaults)
        batteryEnabled = Self.bool(Keys.battery, default: true, defaults: defaults)
        hudEnabled = Self.bool(Keys.hud, default: false, defaults: defaults)
        mirrorEnabled = Self.bool(Keys.mirror, default: true, defaults: defaults)
        hoverOpens = Self.bool(Keys.hover, default: true, defaults: defaults)
    }

    private func persist(_ value: Bool, key: String, old: Bool) {
        guard value != old else { return }
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .notchlingSettingsChanged, object: self)
    }

    private static func bool(_ key: String, default defaultValue: Bool, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private enum Keys {
        static let nowPlaying = "nl.feature.nowPlaying"
        static let calendar = "nl.feature.calendar"
        static let shelf = "nl.feature.shelf"
        static let battery = "nl.feature.battery"
        static let hud = "nl.feature.hud"
        static let mirror = "nl.feature.mirror"
        static let hover = "nl.behavior.hoverOpens"
    }
}
