import Foundation
import Testing
@testable import Trouser

@MainActor
struct HistoryStoreTests {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
    let first = URL(string: "https://example.com/a")!
    let second = URL(string: "https://example.org/b")!

    @Test func removesOneVisitAndPersists() async {
        let store = HistoryStore(fileURL: file)
        store.record(first, title: "A")
        store.record(second, title: "B")
        store.remove(first)
        await store.flush()
        #expect(store.visits.map(\.url) == [second])
        #expect(HistoryStore(fileURL: file).visits.map(\.url) == [second])
    }

    @Test func clearsAllAndPersists() async {
        let store = HistoryStore(fileURL: file)
        store.record(first, title: "A")
        store.removeAll()
        await store.flush()
        #expect(store.visits.isEmpty)
        #expect(HistoryStore(fileURL: file).visits.isEmpty)
    }

    @Test func burstOfRecordsEndsWithTheLatestState() async {
        let store = HistoryStore(fileURL: file)
        for index in 0..<50 {
            store.record(URL(string: "https://example.com/\(index)")!, title: "\(index)")
        }
        await store.flush()
        #expect(HistoryStore(fileURL: file).visits == store.visits)
    }
}
