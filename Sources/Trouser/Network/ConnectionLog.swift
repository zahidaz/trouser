import Foundation

struct ConnectionLog: Sendable {
    let capacity: Int
    private var finished: [ConnectionRecord] = []
    private var active: [Int: ConnectionRecord] = [:]
    private var summaries: [String: HostSummary] = [:]
    private var nextID = 1

    init(capacity: Int = 500) {
        self.capacity = capacity
    }

    var records: [ConnectionRecord] {
        (active.values + finished).sorted { ($0.start, $0.id) > ($1.start, $1.id) }
    }

    var hosts: [HostSummary] {
        var summaries = summaries
        for record in active.values {
            summaries[record.host]?.bytesUp += record.bytesUp
            summaries[record.host]?.bytesDown += record.bytesDown
        }
        return summaries.values.sorted { lhs, rhs in
            let left = lhs.bytesUp + lhs.bytesDown
            let right = rhs.bytesUp + rhs.bytesDown
            return left != right ? left > right : lhs.host < rhs.host
        }
    }

    mutating func open(host: String, port: UInt16, kind: ProxyRequest.Kind, at date: Date = Date()) -> Int {
        let id = nextID
        nextID += 1
        active[id] = ConnectionRecord(id: id, host: host, port: port, kind: kind, start: date)
        summaries[host, default: HostSummary(host: host, lastSeen: date)].connections += 1
        summaries[host]?.lastSeen = date
        return id
    }

    mutating func transfer(_ id: Int, up: Int = 0, down: Int = 0) {
        active[id]?.bytesUp += up
        active[id]?.bytesDown += down
    }

    mutating func close(_ id: Int, _ outcome: ConnectionRecord.Outcome, error: String? = nil, at date: Date = Date()) {
        guard var record = active.removeValue(forKey: id) else { return }
        record.end = date
        record.outcome = outcome
        record.error = error
        finished.append(record)
        if finished.count > capacity {
            finished.removeFirst(finished.count - capacity)
        }
        guard var summary = summaries[record.host] else { return }
        summary.bytesUp += record.bytesUp
        summary.bytesDown += record.bytesDown
        summary.blocked += outcome == .blocked ? 1 : 0
        summary.failed += outcome == .failed ? 1 : 0
        summary.lastSeen = max(summary.lastSeen, date)
        summaries[record.host] = summary
    }
}
