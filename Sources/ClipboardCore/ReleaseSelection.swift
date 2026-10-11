/// A shortcut-opened picker may commit once both held modifiers are released.
public struct ReleaseSelection {
    private var armed = false
    public init() {}
    public mutating func arm() { armed = true }
    public mutating func cancel() { armed = false }
    public mutating func commit(optionHeld: Bool, shiftHeld: Bool) -> Bool {
        guard armed, !optionHeld, !shiftHeld else { return false }
        armed = false
        return true
    }
}
