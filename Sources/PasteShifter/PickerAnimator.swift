import AppKit
import SwiftUI

final class PickerMotion: ObservableObject {
    @Published var scale: CGFloat = 0.96
    @Published var opacity: Double = 0
}

/// A generation token prevents an old fade-out from hiding a newly opened picker.
final class PickerAnimator {
    let motion = PickerMotion()
    private var generation = 0
    private var hideTask: DispatchWorkItem?

    func show(_ panel: NSPanel) {
        hideTask?.cancel(); generation += 1
        let token = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            motion.scale = reduceMotion ? 1 : 0.96
            motion.opacity = 0
        }
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            withAnimation(.timingCurve(0.16, 0.8, 0.25, 1, duration: 0.18)) {
                self.motion.scale = 1; self.motion.opacity = 1
            }
        }
    }

    func hide(_ panel: NSPanel) {
        hideTask?.cancel(); generation += 1
        let token = generation
        panel.ignoresMouseEvents = true
        // Release the nonactivating panel's keyboard grab before sending ⌘V.
        // Order it back without making it key, solely to finish the visual exit.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.10)) {
            motion.scale = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, token == self.generation else { return }
            withAnimation(.easeIn(duration: 0.14)) { self.motion.opacity = 0 }
        }
        let task = DispatchWorkItem { [weak self, weak panel] in
            guard let self, token == self.generation else { return }
            panel?.orderOut(nil)
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }
}
