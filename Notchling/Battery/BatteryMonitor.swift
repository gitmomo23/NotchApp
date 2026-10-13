import Combine
import Foundation
import IOKit.ps

struct BatterySnapshot {
    var available = false
    var percent = 0
    var charging = false
    var pluggedIn = false
    var minutesRemaining: Int?
    var minutesToFull: Int?

    static let unavailable = BatterySnapshot()

    var symbolName: String {
        if !available { return "battery.0percent" }
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var detail: String {
        if charging {
            if let minutesToFull, minutesToFull > 0 {
                return "lädt, voll in \(Self.duration(minutesToFull))"
            }
            return "lädt"
        }
        if let minutesRemaining, minutesRemaining > 0 {
            return "noch \(Self.duration(minutesRemaining))"
        }
        if pluggedIn { return "am Strom" }
        return "Batterie"
    }

    private static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) Min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) Std" }
        return "\(hours) Std \(rest) Min"
    }
}

final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.unavailable
    private var timer: Timer?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        snapshot = Self.read()
    }

    private static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .unavailable
        }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }
        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() else { continue }
            let info = raw as NSDictionary
            let type = info[kIOPSTypeKey] as? String
            if type != (kIOPSInternalBatteryType as String) { continue }
            if let present = info[kIOPSIsPresentKey] as? NSNumber, !present.boolValue { continue }
            let current = (info[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maxCapacity = (info[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let percent: Int
            if maxCapacity > 0 {
                percent = Int((current / maxCapacity * 100).rounded())
            } else {
                percent = Int(current.rounded())
            }
            let charging = (info[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
            let state = info[kIOPSPowerSourceStateKey] as? String
            let plugged = state == (kIOPSACPowerValue as String)
            return BatterySnapshot(
                available: true,
                percent: min(100, max(0, percent)),
                charging: charging,
                pluggedIn: plugged,
                minutesRemaining: minutes(info[kIOPSTimeToEmptyKey]),
                minutesToFull: minutes(info[kIOPSTimeToFullChargeKey])
            )
        }
        return .unavailable
    }

    private static func minutes(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let minutes = number.intValue
        guard minutes > 0, minutes < 24 * 60 else { return nil }
        return minutes
    }
}
