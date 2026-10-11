import Foundation

public struct Clip: Identifiable, Equatable, Codable {
    public let id: UUID
    public let text: String
    public let source: String
    public let date: Date
    public var preview: String { text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    public var compactPreview: String {
        var result = ""
        var previousWasSpace = true
        for character in text {
            if character.isWhitespace {
                guard !previousWasSpace else { continue }
                result.append(" "); previousWasSpace = true
            } else {
                result.append(character); previousWasSpace = false
            }
            if result.count > 50 { return String(result.prefix(49)).trimmingCharacters(in: .whitespaces) + "…" }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
    public init(text: String, source: String, date: Date = Date()) {
        self.id = UUID(); self.text = text; self.source = source; self.date = date
    }
}

public struct History: Codable {
    public private(set) var clips: [Clip] = []
    public private(set) var selectedID: UUID?
    public let capacity: Int
    public let maxBytes: Int
    public var selected: Clip? { clips.first { $0.id == selectedID } ?? clips.first }
    /// Most recently copied, independent of what was picked for a previous paste.
    public var latest: Clip? { clips.first }

    public init(capacity: Int = 60, maxBytes: Int = 256_000) {
        self.capacity = max(1, capacity); self.maxBytes = max(1, maxBytes)
    }

    @discardableResult public mutating func insert(_ text: String, source: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= maxBytes else { return false }
        // A copy makes that text the default; picking an older clip can override it.
        if let index = clips.firstIndex(where: { $0.text == text }) {
            let clip = clips.remove(at: index)
            clips.insert(clip, at: 0); selectedID = clip.id
        } else {
            let clip = Clip(text: text, source: source)
            clips.insert(clip, at: 0); selectedID = clip.id
            if clips.count > capacity { clips.removeLast(clips.count - capacity) }
        }
        return true
    }

    public mutating func select(_ id: UUID) {
        if clips.contains(where: { $0.id == id }) { selectedID = id }
    }
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        clips.remove(at: index)
        if selectedID == id { selectedID = clips.first?.id }
        return true
    }
    public mutating func clear() { clips.removeAll(); selectedID = nil }
}
