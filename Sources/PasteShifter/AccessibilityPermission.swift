import AppKit
import Combine

/// One source of truth for the status shown in Settings and the paste monitor.
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var granted = PasteService.trusted
    @Published private(set) var requested = false
    var onOpenPrivacy: (() -> Void)?

    func refresh() {
        let current = PasteService.trusted
        if granted != current { granted = current }
    }

    func request() {
        refresh()
        guard !granted else { return }
        requested = true
        onOpenPrivacy?()
        // The OS dialog has its own Open Settings button. Do not open a second
        // privacy window at the same time as this asynchronous dialog.
        PasteService.requestPermission()
    }

    func openSettings() {
        requested = true
        onOpenPrivacy?()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
