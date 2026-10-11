import AppKit

/// A click-through LED pulse beside the insertion point.
/// The Flash countdown lives in the menu bar, independent of this short pulse.
final class ActivityIndicator {
    enum Activity {
        case copy, paste, close
        var color: NSColor {
            switch self {
            case .copy: .systemBlue
            case .paste, .close: .systemGreen
            }
        }
    }

    private let panel: NSPanel
    private let dot: NSView
    private var hideTask: DispatchWorkItem?
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        dot = NSView(frame: NSRect(x: 8, y: 8, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.shadowRadius = 4; dot.layer?.shadowOpacity = 0.5; dot.layer?.shadowOffset = .zero
        content.addSubview(dot)
        panel.contentView = content
    }

    func flash(_ activity: Activity, target: NSRunningApplication?) {
        hideTask?.cancel(); generation += 1
        let token = generation
        let caret = PasteService.caretRect(for: target)
        let mouse = NSEvent.mouseLocation
        let point = caret.map { NSPoint(x: $0.maxX + 4, y: $0.midY - 12) }
            ?? NSPoint(x: mouse.x + 8, y: mouse.y - 12)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(caret?.origin ?? mouse) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(point.x, frame.minX), frame.maxX - 24), y: min(max(point.y, frame.minY), frame.maxY - 24)))
        dot.layer?.backgroundColor = activity.color.cgColor
        dot.layer?.shadowColor = activity.color.cgColor
        dot.layer?.transform = CATransform3DIdentity
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self, token == self.generation else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, token == self.generation else { return }
                self.panel.orderOut(nil)
            })
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: task)
    }
}
