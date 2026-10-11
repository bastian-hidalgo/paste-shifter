import AppKit
import ApplicationServices

enum PasteService {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func paste(into target: NSRunningApplication, completion: @escaping (Bool) -> Void) {
        guard trusted, !target.isTerminated else { completion(false); return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        attempt(target: target, remaining: 8, completion: completion)
    }

    static func copy(from target: NSRunningApplication, completion: @escaping (Bool) -> Void) {
        guard trusted, !target.isTerminated, let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            completion(false); return
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.processIdentifier); up.postToPid(target.processIdentifier)
        completion(true)
    }

    private static func attempt(target: NSRunningApplication, remaining: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if remaining > 0 { attempt(target: target, remaining: remaining - 1, completion: completion) }
                else { completion(false) }
                return
            }
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                completion(false); return
            }
            // Explicit flags avoid carrying Option/Shift from the triggering shortcut.
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            completion(true)
        }
    }

    static func caretRect(for target: NSRunningApplication?) -> CGRect? {
        guard trusted, let target else { return nil }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var range: CFTypeRef?
        var bounds: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height > 0,
              let mainScreen = NSScreen.screens.first else { return nil }
        // Accessibility coordinates originate at the main display's upper left.
        rect.origin.y = mainScreen.frame.maxY - rect.maxY
        return rect
    }
}
