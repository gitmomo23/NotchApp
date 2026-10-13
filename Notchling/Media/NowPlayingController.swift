import AppKit
import Combine
import Foundation

struct NowPlayingSnapshot {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var rate: Double
    var artwork: NSImage?
    var source: String
    var updatedAt: Date

    var isPlaying: Bool { rate > 0.05 }

    func elapsed(at date: Date) -> TimeInterval {
        let extra = rate > 0 ? date.timeIntervalSince(updatedAt) * rate : 0
        let value = max(0, elapsed + extra)
        if duration > 0.5 { return min(duration, value) }
        return value
    }

    func fraction(at date: Date) -> Double? {
        guard duration > 0.5 else { return nil }
        return min(1, max(0, elapsed(at: date) / duration))
    }
}

final class NowPlayingController: ObservableObject {
    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var statusMessage: String?

    private let settings: SettingsStore
    private var timer: Timer?
    private var generation = 0
    private var scriptInFlight = false
    private var scriptBlockedUntil = Date.distantPast

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        NLMediaBridge.startObserving { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func toggle() { send(.toggle) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    func refresh() {
        guard settings.nowPlayingEnabled else {
            snapshot = nil
            statusMessage = nil
            return
        }
        generation += 1
        let token = generation
        guard NLMediaBridge.isAvailable() else {
            if shouldQueryScriptPlayer() {
                refreshViaScript(token: token)
            } else {
                snapshot = nil
            }
            return
        }
        NLMediaBridge.fetchNowPlaying { [weak self] info in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                if let info, let parsed = self.parseSystem(info) {
                    self.snapshot = parsed
                    self.statusMessage = nil
                } else if self.shouldQueryScriptPlayer() {
                    self.refreshViaScript(token: token)
                } else {
                    self.snapshot = nil
                }
            }
        }
    }

    private func send(_ command: NLMediaCommand) {
        if NLMediaBridge.isAvailable(), NLMediaBridge.send(command) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refresh()
            }
            return
        }
        guard let bundleID = scriptTarget() else {
            statusMessage = "Kein Player gefunden."
            return
        }
        let verb: String
        switch command {
        case .toggle:
            verb = "playpause"
        case .next:
            verb = "next track"
        case .previous:
            verb = "previous track"
        @unknown default:
            verb = "playpause"
        }
        let source = "tell application id \"\(bundleID)\" to \(verb)"
        AppleScriptClient.run(source) { [weak self] _, error in
            if error != nil {
                self?.statusMessage = "Musik oder Spotify hat die Steuerung abgelehnt."
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.refresh()
            }
        }
    }

    private func refreshViaScript(token: Int) {
        guard !scriptInFlight, Date() >= scriptBlockedUntil else { return }
        scriptInFlight = true
        AppleScriptClient.run(MusicScript.fetch) { [weak self] text, error in
            guard let self else { return }
            self.scriptInFlight = false
            guard token == self.generation else { return }
            if let error {
                let code = Self.errorCode(error)
                if code == -1743 {
                    self.scriptBlockedUntil = Date().addingTimeInterval(45)
                    self.statusMessage = "Erlaube Notchling die Steuerung von Musik oder Spotify."
                } else {
                    self.scriptBlockedUntil = Date().addingTimeInterval(8)
                }
                return
            }
            if let text, let parsed = self.parseScript(text) {
                self.snapshot = parsed
                self.statusMessage = nil
            } else {
                self.snapshot = nil
            }
            self.scriptBlockedUntil = Date().addingTimeInterval(5)
        }
    }

    private func shouldQueryScriptPlayer() -> Bool {
        let bundles: Set<String> = ["com.apple.Music", "com.spotify.client"]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return bundles.contains(bundleID)
        }
    }

    private func parseSystem(_ info: [String: Any]) -> NowPlayingSnapshot? {
        let title = (info["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let artist = info["artist"] as? String ?? ""
        let album = info["album"] as? String ?? ""
        let duration = Self.doubleValue(info["duration"])
        let elapsed = Self.doubleValue(info["elapsed"])
        let rate = Self.doubleValue(info["rate"])
        let source = displaySource(info["source"] as? String ?? "System")
        var artwork: NSImage?
        if let data = info["artwork"] as? Data {
            artwork = NSImage(data: data)
        }
        return NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed,
            rate: rate,
            artwork: artwork,
            source: source,
            updatedAt: Date()
        )
    }

    private func parseScript(_ text: String) -> NowPlayingSnapshot? {
        let parts = text.components(separatedBy: "\t")
        guard parts.count >= 6 else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let duration = (Double(parts[3]) ?? 0) / 1000
        let elapsed = (Double(parts[4]) ?? 0) / 1000
        let playing = parts[5].trimmingCharacters(in: .whitespacesAndNewlines) == "playing"
        return NowPlayingSnapshot(
            title: title,
            artist: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
            album: "",
            duration: duration,
            elapsed: elapsed,
            rate: playing ? 1 : 0,
            artwork: nil,
            source: displaySource(parts[0]),
            updatedAt: Date()
        )
    }

    private func scriptTarget() -> String? {
        let source = snapshot?.source.lowercased() ?? ""
        if source.contains("spotify") { return "com.spotify.client" }
        if source.contains("music") || source.contains("musik") { return "com.apple.Music" }
        let apps = NSWorkspace.shared.runningApplications
        let spotify = apps.contains { $0.bundleIdentifier == "com.spotify.client" }
        let music = apps.contains { $0.bundleIdentifier == "com.apple.Music" }
        if music { return "com.apple.Music" }
        if spotify { return "com.spotify.client" }
        return nil
    }

    private func displaySource(_ raw: String) -> String {
        switch raw.lowercased() {
        case "music", "musik": return "Musik"
        case "spotify": return "Spotify"
        case "system": return "Wiedergabe"
        default: return raw
        }
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Int { return Double(number) }
        return 0
    }

    private static func errorCode(_ error: NSDictionary) -> Int {
        if let number = error[NSAppleScript.errorNumber] as? Int { return number }
        if let number = error[NSAppleScript.errorNumber] as? NSNumber { return number.intValue }
        if let number = error["NSAppleScriptErrorNumber"] as? NSNumber { return number.intValue }
        return 0
    }
}

private enum AppleScriptClient {
    static func run(_ source: String, completion: @escaping (String?, NSDictionary?) -> Void) {
        DispatchQueue.main.async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            completion(result?.stringValue, error)
        }
    }
}

private enum MusicScript {
    static let fetch = """
    on clean(value)
        set s to ""
        try
            set s to value as string
        on error
            return ""
        end try
        set AppleScript's text item delimiters to {tab, linefeed, return}
        set parts to text items of s
        set AppleScript's text item delimiters to " "
        set s to parts as text
        set AppleScript's text item delimiters to ""
        return s
    end clean

    on emit(sourceName, trackName, trackArtist, durationMilli, positionMilli, stateName)
        return sourceName & tab & trackName & tab & trackArtist & tab & (durationMilli as integer) & tab & (positionMilli as integer) & tab & stateName
    end emit

    try
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                if player state is playing then
                    return my emit("spotify", my clean(name of current track), my clean(artist of current track), duration of current track, round (player position * 1000), "playing")
                end if
            end tell
        end if
    end try

    try
        if application id "com.apple.Music" is running then
            tell application id "com.apple.Music"
                if player state is playing or player state is paused then
                    set stateName to "paused"
                    if player state is playing then set stateName to "playing"
                    return my emit("music", my clean(name of current track), my clean(artist of current track), round ((duration of current track) * 1000), round (player position * 1000), stateName)
                end if
            end tell
        end if
    end try

    try
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                if player state is paused then
                    return my emit("spotify", my clean(name of current track), my clean(artist of current track), duration of current track, round (player position * 1000), "paused")
                end if
            end tell
        end if
    end try

    return ""
    """
}
