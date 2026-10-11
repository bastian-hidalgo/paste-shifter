/// Scrolling is consumed only for the lifetime of an open picker, including
/// momentum events that should not move the selection or the underlying app.
public struct ScrollCapture {
    public enum Result: Equatable {
        case passThrough
        case consumed(step: Int?)
    }
    private var active = false
    private var selection = ScrollSelection()
    public init() {}
    public mutating func begin() { selection.reset(); active = true }
    public mutating func end() { active = false; selection.reset() }
    public mutating func handle(delta: Double, precise: Bool, momentum: Bool, time: Double) -> Result {
        guard active else { return .passThrough }
        return .consumed(step: selection.step(delta: delta, precise: precise, momentum: momentum, time: time))
    }
}
