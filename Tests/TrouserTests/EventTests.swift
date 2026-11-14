import Foundation
import Testing
@testable import Trouser

struct EventLogTests {
    @Test func numbersEventsInOrder() {
        var log = EventLog(capacity: 10)
        let first = log.append(.navigationStarted, profile: "p", tab: 1, fields: [:])
        let second = log.append(.navigationFinished, profile: "p", tab: 1, fields: ["duration": "5ms"])
        #expect(first.sequence == 1)
        #expect(second.sequence == 2)
        #expect(log.lastSequence == 2)
        #expect(log.events.map(\.type) == [.navigationStarted, .navigationFinished])
    }

    @Test func keepsOnlyTheNewestEvents() {
        var log = EventLog(capacity: 3)
        for _ in 0..<7 {
            log.append(.pageTitle, profile: "p", tab: nil, fields: [:])
        }
        #expect(log.events.map(\.sequence) == [5, 6, 7])
        #expect(log.firstSequence == 5)
        #expect(log.lastSequence == 7)
    }

    @Test func replaysEventsAfterASequence() {
        var log = EventLog(capacity: 4)
        for _ in 0..<6 {
            log.append(.pageURL, profile: "p", tab: nil, fields: [:])
        }
        #expect(log.events(after: 4).map(\.sequence) == [5, 6])
        #expect(log.events(after: 0).map(\.sequence) == [3, 4, 5, 6])
        #expect(log.events(after: 6).isEmpty)
        #expect(EventLog(capacity: 2).events(after: 0).isEmpty)
    }

    @Test func matchesTypesByPrefix() {
        #expect(EventType.navigationFinished.matches("navigation"))
        #expect(EventType.navigationFinished.matches("navigation.finished"))
        #expect(!EventType.navigationFinished.matches("navigation.fin"))
        #expect(EventType.tabOpened.matches("ui.tab"))
        #expect(EventType.isKnown("cookies"))
        #expect(!EventType.isKnown("network"))
        #expect(EventType.categories == ["navigation", "page", "form", "net", "ui", "download", "cookies", "automation"])
    }

    @Test func summarizesNotableEventsForActionResults() {
        func event(_ type: EventType, _ fields: [String: String]) -> Event {
            Event(sequence: 1, date: Date(), profile: "p", tab: 1, type: type, fields: fields)
        }
        #expect(event(.navigationFailed, ["error": "Could not connect", "code": "-1004"]).note == "navigation failed: Could not connect")
        #expect(event(.navigationFailed, ["error": "cancelled", "code": "-999"]).note == nil)
        #expect(event(.navigationFailed, ["error": "Frame load interrupted", "code": "102"]).note == nil)
        #expect(event(.navigationResponse, ["frame": "main", "status": "404"]).note == "HTTP 404")
        #expect(event(.navigationResponse, ["frame": "sub", "status": "500"]).note == nil)
        #expect(event(.navigationResponse, ["frame": "main", "status": "200"]).note == nil)
        #expect(event(.downloadStarted, ["file": "/d/a.zip"]).note == "download started: /d/a.zip")
        #expect(event(.pageTitle, ["title": "x"]).note == nil)
    }

    @Test func rendersCompactLines() {
        let event = Event(
            sequence: 3,
            date: Date(),
            profile: "work",
            tab: 2,
            type: .pageTitle,
            fields: ["title": "Hello \"there\"", "a": "1"]
        )
        #expect(event.line.hasPrefix("#3 "))
        #expect(event.line.hasSuffix("work[2] page.title a=1 title=\"Hello \\\"there\\\"\""))
        let decoded = try? JSONDecoder.iso8601.decode(Event.self, from: Data(event.json.utf8))
        #expect(decoded?.fields == event.fields)
        #expect(abs((decoded?.date.timeIntervalSince(event.date) ?? 1)) < 0.001)
        #expect(decoded?.type == .pageTitle)
    }
}

@MainActor
struct EventBusTests {
    @Test func wakesSubscribersOnEmit() async {
        let bus = EventBus(profile: "p")
        async let woke: Void = bus.next(within: .seconds(5))
        await Task.yield()
        bus.emit(.cookiesChanged, ["count": "3"])
        await woke
        #expect(bus.lastSequence == 1)
        #expect(bus.events(after: 0).first?.fields == ["count": "3"])
        #expect(bus.lastReaction == nil)
        bus.emit(.pageURL, ["url": "https://a.dev/next"])
        #expect(bus.lastReaction != nil)
    }

    @Test func timesOutWithoutEvents() async {
        let bus = EventBus(profile: "p")
        let start = ContinuousClock.now
        await bus.next(within: .milliseconds(50))
        #expect(ContinuousClock.now - start >= .milliseconds(50))
        #expect(bus.lastSequence == 0)
    }

    @Test func wakesOnCancellation() async {
        let bus = EventBus(profile: "p")
        let task = Task { await bus.next(within: .seconds(30)) }
        await Task.yield()
        let start = ContinuousClock.now
        task.cancel()
        await task.value
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func supervisorEmitsAutomationEvents() async {
        let bus = EventBus(profile: "p")
        let policy = Policy(defaults: UserDefaults(suiteName: "trouser.tests.\(UUID().uuidString)")!)
        policy.setMode(.block, for: .scroll)
        let rules = RuleStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("trouser-policy-\(UUID().uuidString).json"))
        let supervisor = Supervisor(policy: policy, rules: rules, events: bus)
        if case .granted(let id) = await supervisor.authorize(.view, "read page") {
            supervisor.finish(id, .failed("boom"))
        }
        _ = await supervisor.authorize(.scroll, "scroll")
        #expect(bus.log.events.map(\.type) == [
            .actionRequested, .actionGranted, .actionFailed, .actionRequested, .actionBlocked
        ])
        #expect(bus.log.events[2].fields["error"] == "boom")
    }

    @Test func watcherStopsAtCountAndReplaysSince() async {
        let bus = EventBus(profile: "p")
        bus.emit(.pageTitle, ["title": "a"])
        bus.emit(.pageURL, ["url": "https://a.dev"])
        let lines = Lines()
        let output = Output { lines.append($0) }
        let response = await EventWatcher(events: bus, options: WatchOptions(types: ["page.url"], count: 1, since: 0)).run(output: output)
        #expect(response.ok)
        #expect(lines.values.count == 1)
        #expect(lines.values.first?.contains("page.url url=https://a.dev") == true)
    }

    @Test func watcherStopsAtUntil() async {
        let bus = EventBus(profile: "p")
        let lines = Lines()
        let output = Output { lines.append($0) }
        let watcher = Task { await EventWatcher(events: bus, options: WatchOptions(json: true, types: ["cookies"], until: "navigation.finished", since: 0)).run(output: output) }
        await Task.yield()
        bus.emit(.cookiesChanged, ["count": "1"])
        bus.emit(.pageTitle, ["title": "skipped"])
        bus.emit(.navigationFinished, ["url": "https://a.dev"])
        #expect(await watcher.value.ok)
        #expect(lines.values.count == 2)
        #expect(lines.values.last?.contains("\"navigation.finished\"") == true)
    }
}

final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var values: [String] {
        lock.withLock { stored }
    }

    func append(_ line: String) {
        lock.withLock { stored.append(line) }
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(decoder.singleValueContainer().decode(String.self))
        }
        return decoder
    }
}

struct NavigationFailureTests {
    private func event(_ sequence: Int, _ type: EventType, code: Int? = nil) -> Event {
        let fields = code.map { ["code": "\($0)", "error": "lost"] } ?? [:]
        return Event(sequence: sequence, date: Date(), profile: "p", tab: 1, type: type, fields: fields)
    }

    @Test func aFailureCountsUntilAPageCommits() {
        let lost = event(2, .navigationFailed, code: NSURLErrorNetworkConnectionLost)
        #expect([event(1, .navigationStarted), lost].navigationFailure == lost)
        #expect(lost.isConnectionLoss)
        #expect([lost, event(3, .navigationStarted), event(4, .navigationCommitted)].navigationFailure == nil)
    }

    @Test func cancelledNavigationsAreNotFailures() {
        let cancelled = event(1, .navigationFailed, code: NSURLErrorCancelled)
        #expect([cancelled].navigationFailure == nil)
        #expect(!cancelled.isConnectionLoss)
    }
}
