import XCTest
@testable import ClipboardCore

final class HistoryTests: XCTestCase {
    func testLatestCopyDoesNotChangeWhenPastingAnOlderSelection() {
        var history = History()
        history.insert("primero", source: "Test")
        let older = history.clips[0]
        history.insert("último", source: "Test")
        history.select(older.id)
        XCTAssertEqual(history.selected?.text, "primero")
        XCTAssertEqual(history.latest?.text, "último")
        history.insert("nuevo", source: "Test")
        XCTAssertEqual(history.latest?.text, "nuevo")
    }
    func testBubblePreviewUsesAtMost50CharactersWithoutChangingOriginal() {
        let original = String(repeating: "👨‍👩‍👧‍👦", count: 60) + "\nresto"
        let clip = Clip(text: original, source: "Test")
        XCTAssertEqual(clip.compactPreview.count, 50)
        XCTAssertTrue(clip.compactPreview.hasSuffix("…"))
        XCTAssertEqual(clip.text, original)
        XCTAssertEqual(Clip(text: "  uno\n\tdos  ", source: "Test").compactPreview, "uno dos")
        XCTAssertEqual(Clip(text: String(repeating: "a", count: 50), source: "Test").compactPreview.count, 50)
    }
    func testDuplicateMovesToFrontWithoutLosingIdentity() {
        var history = History()
        history.insert("primero", source: "Editor")
        let id = history.clips[0].id
        history.insert("segundo", source: "Editor")
        history.insert("primero", source: "Browser")
        XCTAssertEqual(history.clips.count, 2)
        XCTAssertEqual(history.selected?.id, id)
        XCTAssertEqual(history.clips[0].text, "primero")
    }
    func testSelectionSurvivesUntilNextCopy() {
        var history = History()
        history.insert("A", source: "Test")
        let first = history.clips[0]
        history.insert("B", source: "Test")
        history.select(first.id)
        XCTAssertEqual(history.selected?.text, "A")
        history.insert("C", source: "Test")
        XCTAssertEqual(history.selected?.text, "C")
    }
    func testCapacityAndUTF8ByteLimit() {
        var history = History(capacity: 2, maxBytes: 4)
        XCTAssertFalse(history.insert("   \n", source: "Test"))
        XCTAssertFalse(history.insert("🍊a", source: "Test"))
        XCTAssertTrue(history.insert("🍊", source: "Test"))
        history.insert("B", source: "Test")
        history.insert("C", source: "Test")
        XCTAssertEqual(history.clips.map(\.text), ["C", "B"])
        history.clear()
        XCTAssertNil(history.selected)
        XCTAssertTrue(history.clips.isEmpty)
    }
    func testExactWhitespaceIsPreserved() {
        var history = History()
        history.insert("  línea uno\n\tlínea dos\n", source: "Test")
        XCTAssertEqual(history.selected?.text, "  línea uno\n\tlínea dos\n")
        XCTAssertEqual(history.selected?.preview, "línea uno línea dos")
    }
}
