import Foundation

struct EventLog: Sendable {
    let capacity: Int
    private var storage: [Event] = []
    private var start = 0
    private(set) var lastSequence = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var events: [Event] {
        Array(storage[start...] + storage[..<start])
    }

    var firstSequence: Int? {
        storage.isEmpty ? nil : storage[start].sequence
    }

    @discardableResult
    mutating func append(_ type: EventType, profile: String, tab: Int?, fields: [String: String], date: Date = Date()) -> Event {
        lastSequence += 1
        let event = Event(sequence: lastSequence, date: date, profile: profile, tab: tab, type: type, fields: fields)
        if storage.count < capacity {
            storage.append(event)
        } else {
            storage[start] = event
            start = (start + 1) % capacity
        }
        return event
    }

    func events(after sequence: Int) -> [Event] {
        guard let first = firstSequence, sequence < lastSequence else { return [] }
        let skipped = max(sequence - first + 1, 0)
        return (skipped..<storage.count).map { storage[(start + $0) % storage.count] }
    }
}
