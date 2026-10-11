import Foundation

/// Converts the Magic Mouse's continuous deltas into deliberate selection steps.
public struct ScrollSelection {
    private var accumulated: Double = 0
    private var lastEvent: TimeInterval = -.infinity
    private var lastStep: TimeInterval = -.infinity

    public init() {}
    public mutating func reset() { self = ScrollSelection() }

    public mutating func step(delta: Double, precise: Bool, momentum: Bool, time: TimeInterval) -> Int? {
        guard !momentum, delta.isFinite, delta != 0 else { return nil }
        if time - lastEvent > 0.22 || accumulated * delta < 0 { accumulated = 0 }
        lastEvent = time
        accumulated += delta
        guard abs(accumulated) >= (precise ? 14 : 1), time - lastStep >= 0.12 else { return nil }
        let direction = accumulated > 0 ? -1 : 1
        accumulated = 0; lastStep = time
        return direction
    }
}
