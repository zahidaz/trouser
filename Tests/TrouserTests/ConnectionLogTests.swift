import Foundation
import Testing
@testable import Trouser

struct ConnectionLogTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func recordsAndAggregatesPerHost() {
        var log = ConnectionLog()
        let a = log.open(host: "a.com", port: 443, kind: .tunnel, at: start)
        let b = log.open(host: "a.com", port: 443, kind: .tunnel, at: start.addingTimeInterval(1))
        let c = log.open(host: "b.com", port: 80, kind: .http, at: start.addingTimeInterval(2))
        log.transfer(a, up: 100, down: 1_000)
        log.transfer(b, up: 10, down: 20)
        log.close(a, .completed, at: start.addingTimeInterval(3))
        log.close(c, .blocked, at: start.addingTimeInterval(2))

        #expect(log.records.map(\.id) == [c, b, a])
        #expect(log.records.map(\.outcome) == [.blocked, .open, .completed])
        #expect(log.records.last?.duration(at: start) == 3)
        #expect(log.hosts == [
            HostSummary(host: "a.com", connections: 2, bytesUp: 110, bytesDown: 1_020, lastSeen: start.addingTimeInterval(3)),
            HostSummary(host: "b.com", connections: 1, blocked: 1, lastSeen: start.addingTimeInterval(2))
        ])
    }

    @Test func keepsOnlyTheMostRecentFinishedConnections() {
        var log = ConnectionLog(capacity: 2)
        for index in 0..<5 {
            let id = log.open(host: "h\(index).com", port: 443, kind: .tunnel, at: start.addingTimeInterval(Double(index)))
            log.close(id, .failed, error: "refused")
        }
        #expect(log.records.map(\.host) == ["h4.com", "h3.com"])
        #expect(log.hosts.count == 5)
        #expect(log.hosts.allSatisfy { $0.failed == 1 })
    }

    @Test func ignoresUnknownConnections() {
        var log = ConnectionLog()
        log.transfer(42, up: 1)
        log.close(42, .completed)
        #expect(log.records.isEmpty)
    }
}

struct NetworkActivityTests {
    @Test func opensAndTransfersMarkTraffic() throws {
        let proxy = try NetworkProxy(rules: HostRules(blocked: ["blocked.test"]))
        #expect(proxy.lastTraffic == nil)
        let request = try #require(try ProxyRequest.parse(Data("CONNECT blocked.test:443 HTTP/1.1\r\nHost: blocked.test\r\n\r\n".utf8)))
        let (id, permitted) = proxy.open(request)
        let opened = try #require(proxy.lastTraffic)
        #expect(!permitted)
        proxy.transfer(id, down: 10)
        #expect(try #require(proxy.lastTraffic) >= opened)
    }
}
