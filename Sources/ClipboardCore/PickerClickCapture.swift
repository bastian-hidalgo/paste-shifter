/// Swallows a complete confirming click, including its release if Esc or a
/// shortcut closes the picker while the mouse button is still held down.
public struct PickerClickCapture {
    public enum Kind { case down, drag, up }
    public enum Result: Equatable { case passThrough, consumed(confirm: Bool) }
    private var active = false
    private var confirmOnRelease = false
    public private(set) var isTracking = false
    public init() {}
    public mutating func begin() { active = true }
    public mutating func end() { active = false; confirmOnRelease = false }
    public mutating func handle(_ kind: Kind) -> Result {
        switch kind {
        case .down:
            guard active || isTracking else { return .passThrough }
            if !isTracking { isTracking = true; confirmOnRelease = active }
            return .consumed(confirm: false)
        case .drag:
            return isTracking ? .consumed(confirm: false) : .passThrough
        case .up:
            guard isTracking else { return .passThrough }
            let confirm = active && confirmOnRelease
            isTracking = false; confirmOnRelease = false
            return .consumed(confirm: confirm)
        }
    }
}
