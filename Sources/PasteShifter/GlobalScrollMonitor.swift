#if !APP_STORE
import AppKit
#if canImport(ClipboardCore)
import ClipboardCore
#endif

/// Captures scrolling and complete left clicks while the picker is open.
/// A passive NSEvent observer cannot prevent the background app from scrolling.
final class GlobalScrollMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var capture = ScrollCapture()
    private var onStep: ((Int) -> Void)?
    private var onConfirm: ((CGPoint) -> Void)?
    private var shouldPassClick: ((CGPoint) -> Bool)?
    private var clickCapture = PickerClickCapture()
    private var generation = 0
    private(set) var isCapturing = false

    @discardableResult
    func start(onStep: @escaping (Int) -> Void, onConfirm: @escaping (CGPoint) -> Void,
               shouldPassClick: ((CGPoint) -> Bool)? = nil) -> Bool {
        stop()
        guard PasteService.trusted else { return false }
        self.onStep = onStep; self.onConfirm = onConfirm; self.shouldPassClick = shouldPassClick
        // Reuse a tap that is still swallowing the release of a cancelled click.
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            capture.begin(); clickCapture.begin(); isCapturing = true
            return true
        }
        tearDown()
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<GlobalScrollMonitor>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
        }, userInfo: context) else {
            self.onStep = nil; self.onConfirm = nil
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); self.onStep = nil; self.onConfirm = nil
            return false
        }
        self.tap = tap; self.source = source
        capture.begin(); clickCapture.begin(); isCapturing = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            // Respect a system/user cancellation rather than re-enabling it.
            stop()
            return Unmanaged.passUnretained(event)
        }
        let clickKind: PickerClickCapture.Kind?
        switch type {
        case .leftMouseDown: clickKind = .down
        case .leftMouseDragged: clickKind = .drag
        case .leftMouseUp: clickKind = .up
        default: clickKind = nil
        }
        if let clickKind {
            if case .down = clickKind, shouldPassClick?(NSEvent.mouseLocation) == true {
                return Unmanaged.passUnretained(event)
            }
            switch clickCapture.handle(clickKind) {
            case .passThrough: return Unmanaged.passUnretained(event)
            case .consumed(let confirm):
                if confirm {
                    // Complete swallowing the mouse-up before pasting or retiring the tap.
                    let token = generation
                    // CGEvent.location uses Quartz display coordinates; NSPanel.frame
                    // and NSEvent.mouseLocation use AppKit's bottom-left coordinates.
                    let appKitPoint = NSEvent.mouseLocation
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isCapturing, token == self.generation else { return }
                        self.onConfirm?(appKitPoint)
                    }
                } else if !isCapturing, !clickCapture.isTracking {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.isCapturing, !self.clickCapture.isTracking else { return }
                        self.tearDown()
                    }
                }
                return nil
            }
        }
        guard type == .scrollWheel, let native = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        let delta = native.scrollingDeltaY == 0 ? native.scrollingDeltaX : native.scrollingDeltaY
        switch capture.handle(delta: Double(delta), precise: native.hasPreciseScrollingDeltas, momentum: !native.momentumPhase.isEmpty, time: native.timestamp) {
        case .passThrough: return Unmanaged.passUnretained(event)
        case .consumed(let step):
            if let step { onStep?(step) }
            return nil
        }
    }

    func stop() {
        generation += 1
        capture.end(); clickCapture.end(); isCapturing = false
        onStep = nil; onConfirm = nil; shouldPassClick = nil
        if !clickCapture.isTracking { tearDown() }
    }

    private func tearDown() {
        clickCapture = PickerClickCapture()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }
    deinit { tearDown() }
}
#else
import Foundation

/// The Mac App Store build never listens to or filters system-wide input.
final class GlobalScrollMonitor {
    private(set) var isCapturing = false

    @discardableResult
    func start(onStep: @escaping (Int) -> Void, onConfirm: @escaping (CGPoint) -> Void,
               shouldPassClick: ((CGPoint) -> Bool)? = nil) -> Bool {
        false
    }

    func stop() { isCapturing = false }
}
#endif
