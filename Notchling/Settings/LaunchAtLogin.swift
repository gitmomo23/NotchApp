import Combine
import Foundation
import ServiceManagement

final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var detail = "Startet nicht automatisch."

    init() {
        apply(status: SMAppService.mainApp.status, error: nil)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            apply(status: SMAppService.mainApp.status, error: nil)
        } catch {
            apply(status: SMAppService.mainApp.status, error: error)
        }
    }

    private func apply(status: SMAppService.Status, error: Error?) {
        isEnabled = status == .enabled || status == .requiresApproval
        if let error {
            detail = error.localizedDescription
            return
        }
        switch status {
        case .enabled:
            detail = "Notchling startet beim Anmelden."
        case .requiresApproval:
            detail = "Bitte unter „Allgemein“ → „Anmeldeobjekte & Erweiterungen“ bestätigen."
        case .notRegistered:
            detail = "Startet nicht automatisch."
        case .notFound:
            detail = "Eintrag nicht gefunden. Lege die App in den Ordner Programme und versuche es erneut."
        @unknown default:
            detail = "Anmeldestatus \(status.rawValue)."
        }
    }
}
