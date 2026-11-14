import Foundation

struct SettlePolicy: Equatable {
    let reactionWindow: Duration
    let quietPeriod: Duration
    let limit: Duration
    let countsEarlierActivity: Bool

    static let action = SettlePolicy(
        reactionWindow: .milliseconds(350),
        quietPeriod: .milliseconds(100),
        limit: .seconds(30),
        countsEarlierActivity: false
    )

    static let followUp = SettlePolicy(
        reactionWindow: .seconds(1),
        quietPeriod: .milliseconds(100),
        limit: .seconds(30),
        countsEarlierActivity: false
    )

    static func idle(within timeout: Duration) -> SettlePolicy {
        SettlePolicy(reactionWindow: .zero, quietPeriod: .milliseconds(300), limit: timeout, countsEarlierActivity: true)
    }

    static let keystrokeAllowance: Duration = .milliseconds(2)
    static let trafficLimit: Duration = .seconds(5)
    static let busyRecheck: Duration = .milliseconds(100)
    static let trafficPoll: Duration = .milliseconds(25)
    static let probeInterval: Duration = .milliseconds(50)
    static let followUpRounds = 2
}

enum SettleOutcome: Equatable {
    case unchanged, settled, limited
}

enum SettleStep: Equatable {
    case finish(SettleOutcome)
    case wait(Duration)
}

struct SettleObservation: Equatable {
    var now: ContinuousClock.Instant
    var busy = false
    var pageEvent: ContinuousClock.Instant?
    var traffic: ContinuousClock.Instant?
    var change: ContinuousClock.Instant?
}

struct Settling {
    let policy: SettlePolicy
    let start: ContinuousClock.Instant
    private let earliest: ContinuousClock.Instant
    private var lastBusy: ContinuousClock.Instant?
    private var firstChange: ContinuousClock.Instant?

    init(_ policy: SettlePolicy, start: ContinuousClock.Instant, typed: Int = 0) {
        self.policy = policy
        self.start = start
        earliest = start + SettlePolicy.keystrokeAllowance * typed
    }

    mutating func next(_ observation: SettleObservation) -> SettleStep {
        let now = observation.now
        let deadline = start + policy.limit
        guard now < deadline else { return .finish(.limited) }
        if observation.busy {
            lastBusy = now
            return .wait(min(SettlePolicy.busyRecheck, deadline - now))
        }
        if firstChange == nil, let change = observation.change, change > start {
            firstChange = change
        }
        let traffic = observation.traffic.map { min($0, start + SettlePolicy.trafficLimit) }
        let activity = [observation.pageEvent, traffic, lastBusy].compactMap { $0 }.filter { policy.countsEarlierActivity || $0 > start }
        let reaction = (activity + [firstChange].compactMap { $0 }).max()
        let ready = max(earliest, reaction.map { $0 + policy.quietPeriod } ?? start + policy.reactionWindow)
        guard now < ready else { return .finish(reaction == nil ? .unchanged : .settled) }
        return .wait(min(ready - now, SettlePolicy.trafficPoll, deadline - now))
    }
}

@MainActor
protocol SettleSignals {
    func observe() -> SettleObservation
    func pause(for duration: Duration) async
    func expect(_ model: PageModel)
}

@MainActor
final class PageSignals: SettleSignals {
    private let events: EventBus
    private let proxy: NetworkProxy
    private let busy: () -> Bool
    private let probe: (() async throws -> PageModel)?
    private var expected: PageModel?
    private var change: ContinuousClock.Instant?
    private var lastProbe: ContinuousClock.Instant?

    init(events: EventBus, proxy: NetworkProxy, busy: @escaping () -> Bool, probe: (() async throws -> PageModel)? = nil, expected: PageModel? = nil) {
        self.events = events
        self.proxy = proxy
        self.busy = busy
        self.probe = probe
        self.expected = expected
    }

    func observe() -> SettleObservation {
        SettleObservation(now: .now, busy: busy(), pageEvent: events.lastReaction, traffic: proxy.lastTraffic, change: change)
    }

    func pause(for duration: Duration) async {
        let now = ContinuousClock.now
        guard let probe, duration >= SettlePolicy.trafficPoll, !busy(), lastProbe.map({ now - $0 >= SettlePolicy.probeInterval }) ?? true else {
            await events.next(within: duration)
            return
        }
        lastProbe = now
        guard let model = try? await probe() else {
            await events.next(within: duration)
            return
        }
        if let expected, !ModelDiff(from: expected, to: model).isEmpty {
            change = now
        }
        expected = model
    }

    func expect(_ model: PageModel) {
        expected = model
    }
}

@MainActor
struct ActionSettler {
    let signals: any SettleSignals

    var now: ContinuousClock.Instant {
        signals.observe().now
    }

    func settle(_ policy: SettlePolicy, since start: ContinuousClock.Instant, typed: Int = 0) async -> SettleOutcome {
        var settling = Settling(policy, start: start, typed: typed)
        while true {
            switch settling.next(signals.observe()) {
            case .finish(let outcome):
                return outcome
            case .wait(let duration):
                guard !Task.isCancelled else { return .limited }
                await signals.pause(for: duration)
            }
        }
    }

    func confirmedModel(
        after outcome: SettleOutcome,
        changingFrom before: PageModel?,
        render: () async throws -> PageModel
    ) async throws -> PageModel {
        var renderStart = now
        var model = try await render()
        guard outcome == .settled, let before else { return model }
        for _ in 0..<SettlePolicy.followUpRounds where ModelDiff(from: before, to: model).isEmpty {
            signals.expect(model)
            guard await settle(.followUp, since: renderStart) == .settled else { break }
            renderStart = now
            model = try await render()
        }
        return model
    }
}
