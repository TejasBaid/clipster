import Foundation
import Testing
@testable import ClipsterCore

@MainActor
@Suite struct ClipStoreTests {
    @Test func recopyMovesToTopWithoutDuplicating() {
        let store = ClipStore(fileURL: nil)
        store.add("a"); store.add("b"); store.add("a")
        #expect(store.history.map(\.text) == ["a", "b"])
    }

    @Test func ignoresBlankText() {
        let store = ClipStore(fileURL: nil)
        store.add("  \n ")
        #expect(store.history.isEmpty)
    }

    @Test func historyIsCapped() {
        let store = ClipStore(fileURL: nil, historyLimit: 3)
        for i in 0..<5 { store.add("\(i)") }
        #expect(store.history.map(\.text) == ["4", "3", "2"])
    }

    @Test func slotsAreOneBasedAndSurviveHistoryDeletion() {
        let store = ClipStore(fileURL: nil)
        store.add("keep me")
        store.assign(store.history[0], toSlot: 9)
        store.clearHistory()
        #expect(store.slot(9)?.text == "keep me")
        #expect(store.slot(0) == nil && store.slot(10) == nil)
    }

    @Test func previewCollapsesWhitespace() {
        #expect(Clip(text: "  hello\n\n  world\t!").preview == "hello world !")
    }

    @Test func persistsAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clipster-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ClipStore(fileURL: url)
        store.add("one"); store.add("two")
        store.assign(store.history[1], toSlot: 2)
        store.saveNow()

        let reloaded = ClipStore(fileURL: url)
        #expect(reloaded.history.map(\.text) == ["two", "one"])
        #expect(reloaded.slot(2)?.text == "one")
    }
}
