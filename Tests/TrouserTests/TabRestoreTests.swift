import Foundation
import Testing
@testable import Trouser

@MainActor
struct TabRestoreTests {
    private let a = SavedTab(url: URL(string: "https://a.dev")!, title: "A", state: Data([1]))
    private let b = SavedTab(url: URL(string: "https://b.dev")!, title: "B", state: nil)

    @Test func closingOneTabKeepsTheRest() {
        var book = TabRestoreBook()
        let started = book.willClose([a, b])
        let saved = book.settle(remaining: [b])
        #expect(started)
        #expect(saved == [b])
    }

    @Test func closingEveryTabKeepsAllOfThem() {
        var book = TabRestoreBook()
        let first = book.willClose([a, b])
        let second = book.willClose([b])
        let saved = book.settle(remaining: [])
        let next = book.willClose([a])
        #expect(first)
        #expect(!second)
        #expect(saved == [a, b])
        #expect(next)
    }

    @Test func storeRoundTripsTabs() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-tabs-\(UUID().uuidString).json")
        let store = TabRestoreStore(fileURL: file)
        #expect(store.load().isEmpty)
        store.save([a, b])
        #expect(store.load() == [a, b])
        try? FileManager.default.removeItem(at: file)
    }
}
