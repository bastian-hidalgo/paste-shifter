import AppKit
import ServiceManagement
import SwiftUI

/// macOS owns the preference; re-read it when returning from System Settings.
final class LoginItemSettings: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var errorMessage: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        errorMessage = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
