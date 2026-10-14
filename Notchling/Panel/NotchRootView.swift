import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var panel: PanelState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var calendar: CalendarController
    @ObservedObject var shelf: FileShelfStore
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var mirror: MirrorController
    let actions: PanelActions

    private var radius: CGFloat { 14 + (22 - 14) * panel.expansion }
    private var collapsedOpacity: Double {
        let progress = Double(panel.expansion)
        return min(1, max(0, (0.42 - progress) / 0.28))
    }
    private var expandedOpacity: Double {
        let progress = Double(panel.expansion)
        return min(1, max(0, (progress - 0.48) / 0.32))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.94))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            collapsedLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(collapsedOpacity)
                .allowsHitTesting(panel.expansion < 0.4)

            expandedLayer
                .padding(.top, panel.notchHeight + 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .opacity(expandedOpacity)
                .allowsHitTesting(panel.expansion > 0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LayoutProbe(expansion: panel.expansion))
    }

    private var collapsedLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: actions.openPinned) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.45, green: 0.78, blue: 1))
                        .frame(width: 6, height: 6)
                    Text(collapsedTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if settings.batteryEnabled, battery.snapshot.available {
                        Text("\(battery.snapshot.percent)%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: max(20, panel.chin - 4))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .accessibilityLabel("Panel öffnen")
        }
    }

    private var collapsedTitle: String {
        if settings.nowPlayingEnabled, let title = nowPlaying.snapshot?.title, !title.isEmpty {
            return title
        }
        return "Notchling"
    }

    private var expandedLayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if hasSections {
                HStack(alignment: .top, spacing: 14) {
                    if settings.nowPlayingEnabled {
                        NowPlayingPane(player: nowPlaying)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if settings.calendarEnabled {
                        if settings.nowPlayingEnabled { divider }
                        CalendarPane(calendar: calendar)
                            .frame(width: 188, alignment: .leading)
                    }
                    if showsUtility {
                        if settings.nowPlayingEnabled || settings.calendarEnabled { divider }
                        utilityColumn
                            .frame(width: 210, alignment: .leading)
                    }
                }
            } else {
                Text("Alle Funktionen sind in den Einstellungen ausgeschaltet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var hasSections: Bool {
        settings.nowPlayingEnabled || settings.calendarEnabled || showsUtility
    }

    private var showsUtility: Bool {
        settings.shelfEnabled || settings.batteryEnabled || settings.mirrorEnabled
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(panel.pinned ? "Angepinnt" : "Notchling")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            iconButton("gearshape", "Einstellungen", actions.showSettings)
            iconButton(panel.pinned ? "pin.fill" : "pin", panel.pinned ? "Loslösen" : "Anheften", actions.togglePin)
            iconButton("chevron.up", "Schließen", actions.collapse)
        }
    }

    private var utilityColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.batteryEnabled {
                BatteryPane(battery: battery)
            }
            if settings.shelfEnabled {
                ShelfPane(shelf: shelf, actions: actions)
            }
            if settings.mirrorEnabled {
                MirrorPane(mirror: mirror)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.82))
        .accessibilityLabel(label)
    }
}

private struct NowPlayingPane: View {
    @ObservedObject var player: NowPlayingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Wiedergabe")
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        if let snapshot = player.snapshot {
            HStack(alignment: .top, spacing: 10) {
                artwork(snapshot.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle(snapshot))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(snapshot.source)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 1))
                }
            }
            controls(snapshot)
            progress(snapshot, at: date)
        } else {
            Text(player.statusMessage ?? "Nichts wird wiedergegeben")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 72)
            controls(nil)
        }
    }

    private func artwork(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func controls(_ snapshot: NowPlayingSnapshot?) -> some View {
        HStack(spacing: 16) {
            transport("backward.fill", "Vorheriger Titel", player.previous)
            transport(snapshot?.isPlaying == true ? "pause.fill" : "play.fill", "Wiedergabe umschalten", player.toggle)
            transport("forward.fill", "Nächster Titel", player.next)
        }
        .frame(maxWidth: .infinity)
    }

    private func transport(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func progress(_ snapshot: NowPlayingSnapshot, at date: Date) -> some View {
        if let fraction = snapshot.fraction(at: date) {
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: max(2, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(clock(snapshot.elapsed(at: date)))
                    Spacer()
                    Text(clock(snapshot.duration))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func subtitle(_ snapshot: NowPlayingSnapshot) -> String {
        if !snapshot.artist.isEmpty { return snapshot.artist }
        if !snapshot.album.isEmpty { return snapshot.album }
        return "Unbekannter Interpret"
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct CalendarPane: View {
    @ObservedObject var calendar: CalendarController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Termine")
            switch calendar.access {
            case .granted:
                if calendar.items.isEmpty {
                    Text("Keine anstehenden Termine")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                } else {
                    ForEach(calendar.items) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.when)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }
            case .needsPrompt, .unknown:
                Text("Kalenderzugriff erlauben, um die nächsten Termine zu sehen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
                Button(calendar.requesting ? "Bitte warten…" : "Zugriff erlauben", action: calendar.requestAccess)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(calendar.requesting)
            case .denied:
                Text(calendar.message ?? "Kein Kalenderzugriff.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
                Button("Einstellungen öffnen", action: calendar.openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
    }
}

private struct BatteryPane: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: battery.snapshot.symbolName)
                .font(.system(size: 16))
            if battery.snapshot.available {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(battery.snapshot.percent) %")
                        .font(.system(size: 12, weight: .semibold))
                    Text(battery.snapshot.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            } else {
                Text("Kein Akku")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

private struct ShelfPane: View {
    @ObservedObject var shelf: FileShelfStore
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Ablage")
            Group {
                if shelf.items.isEmpty {
                    Text(shelf.dropTargeted ? "Loslassen zum Ablegen" : "Dateien hierher ziehen")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items) { item in
                                chip(item)
                            }
                        }
                    }
                    .frame(height: 70)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color.white.opacity(shelf.dropTargeted ? 0.85 : 0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .onDrop(of: [.fileURL], isTargeted: targeted) { providers in
            shelf.handleDrop(providers)
        }
    }

    private var targeted: Binding<Bool> {
        Binding(get: { shelf.dropTargeted }, set: { shelf.dropTargeted = $0 })
    }

    private func chip(_ item: ShelfItem) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 28, height: 28)
            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 64)
        }
        .opacity(item.missing ? 0.4 : 1)
        .foregroundStyle(.white)
        .help(item.missing ? "Datei nicht gefunden" : item.name)
        .onDrag {
            guard let url = item.url else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            if let url = item.url {
                Button("AirDrop") { actions.airDrop([url]) }
                Button("Teilen…") { actions.share([url]) }
            }
            Button("Entfernen") { shelf.remove(item) }
        }
    }
}

private struct MirrorPane: View {
    @ObservedObject var mirror: MirrorController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("Spiegel")
                Spacer()
                Button(mirror.wantsPreview ? "Aus" : "Ein", action: mirror.toggle)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
            }
            if mirror.wantsPreview {
                CameraPreview(session: mirror.session)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            if let message = mirror.message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                if message.contains("verweigert") {
                    Button("Einstellungen öffnen", action: mirror.openSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
}

private struct LayoutProbe: View {
    var expansion: CGFloat
    @State private var last = CGSize(width: -1, height: -1)

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { note(proxy.size, event: "appear") }
                .onChange(of: proxy.size) { _, size in
                    note(size, event: "change")
                }
        }
    }

    private func note(_ size: CGSize, event: String) {
        let jump = abs(size.width - last.width) >= 24 || abs(size.height - last.height) >= 16
        guard last.width < 0 || jump else { return }
        last = size
        let empty = size.width < 2 || size.height < 2
        AppLog.panel.notice(
            "SwiftUI \(event, privacy: .public) size=\(String(format: "%.1fx%.1f", size.width, size.height), privacy: .public) expansion=\(String(format: "%.3f", expansion), privacy: .public) empty=\(empty, privacy: .public)"
        )
        if empty && expansion > 0.5 {
            AppLog.panel.error("SwiftUI content size is empty while the panel is expanded")
        }
    }
}
