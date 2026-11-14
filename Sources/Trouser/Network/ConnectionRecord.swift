import Foundation

struct ConnectionRecord: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case open, completed, blocked, failed
    }

    let id: Int
    let host: String
    let port: UInt16
    let kind: ProxyRequest.Kind
    let start: Date
    var end: Date?
    var bytesUp = 0
    var bytesDown = 0
    var outcome = Outcome.open
    var error: String?

    func duration(at now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}

struct HostSummary: Codable, Equatable, Identifiable, Sendable {
    let host: String
    var connections = 0
    var blocked = 0
    var failed = 0
    var bytesUp = 0
    var bytesDown = 0
    var lastSeen: Date

    var id: String { host }
}
