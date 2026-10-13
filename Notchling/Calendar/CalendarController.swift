import AppKit
import Combine
import EventKit
import Foundation

struct CalendarItem: Identifiable {
    let id: String
    let title: String
    let when: String
}

enum CalendarAccess {
    case unknown
    case needsPrompt
    case granted
    case denied
}

final class CalendarController: ObservableObject {
    @Published private(set) var items: [CalendarItem] = []
    @Published private(set) var access: CalendarAccess = .unknown
    @Published private(set) var message: String?
    @Published private(set) var requesting = false

    private let settings: SettingsStore
    private var store = EKEventStore()
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        refreshStatus()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshIfAuthorized()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(
            forName: .notchlingSettingsChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func refreshIfAuthorized() {
        guard settings.calendarEnabled else {
            items = []
            return
        }
        refreshStatus()
    }

    func requestAccess() {
        guard !requesting else { return }
        requesting = true
        message = nil
        ForegroundGate.shared.begin()
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else {
                    ForegroundGate.shared.end()
                    return
                }
                self.requesting = false
                ForegroundGate.shared.end()
                if let error, !granted {
                    self.message = error.localizedDescription
                }
                if granted {
                    self.store = EKEventStore()
                }
                self.refreshStatus()
            }
        }
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshStatus() {
        guard settings.calendarEnabled else {
            items = []
            access = .unknown
            return
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            access = .granted
            loadEvents()
        } else if status == .notDetermined {
            access = .needsPrompt
            items = []
        } else {
            access = .denied
            items = []
        }
    }

    private func loadEvents() {
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 14, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
        items = events.map { event in
            let trimmed = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let identifier = event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(trimmed)"
            return CalendarItem(
                id: identifier,
                title: trimmed.isEmpty ? "Ohne Titel" : trimmed,
                when: Self.when(for: event)
            )
        }
    }

    private static func when(for event: EKEvent) -> String {
        if event.isAllDay {
            if Calendar.current.isDateInToday(event.startDate) { return "heute, ganztägig" }
            if Calendar.current.isDateInTomorrow(event.startDate) { return "morgen, ganztägig" }
            let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(day), ganztägig"
        }
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(event.startDate) { return "heute \(time)" }
        if Calendar.current.isDateInTomorrow(event.startDate) { return "morgen \(time)" }
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) \(time)"
    }
}
