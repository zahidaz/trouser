import Foundation
import Testing
@testable import Trouser

struct SettlingTests {
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    private func observe(_ now: Int, busy: Bool = false, event: Int? = nil, traffic: Int? = nil, change: Int? = nil) -> SettleObservation {
        SettleObservation(now: at(now), busy: busy, pageEvent: event.map(at), traffic: traffic.map(at), change: change.map(at))
    }

    @Test func returnsUnchangedAfterTheReactionWindowWithoutSignals() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(0)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(340)) == .wait(.milliseconds(10)))
        #expect(settling.next(observe(350)) == .finish(.unchanged))
    }

    @Test func ignoresActivityFromBeforeTheAction() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(360, event: -10, traffic: -5)) == .finish(.unchanged))
    }

    @Test func waitsForQuietAfterAPageEvent() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(250, event: 200)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(299, event: 200)) == .wait(.milliseconds(1)))
        #expect(settling.next(observe(300, event: 200)) == .finish(.settled))
    }

    @Test func networkTrafficKeepsThePageUnsettled() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(750, event: 100, traffic: 700)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(800, event: 100, traffic: 700)) == .finish(.settled))
    }

    @Test func trafficStopsCountingAfterTheTrafficLimit() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(5_050, traffic: 5_040)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(5_100, traffic: 5_090)) == .finish(.settled))
    }

    @Test func busyPagesAreReactionsThatMustEndBeforeQuiet() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(50, busy: true)) == .wait(SettlePolicy.busyRecheck))
        #expect(settling.next(observe(1_000, busy: true)) == .wait(SettlePolicy.busyRecheck))
        #expect(settling.next(observe(1_050)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(1_100)) == .finish(.settled))
    }

    @Test func typingExtendsTheEarliestReturn() {
        var settling = Settling(.action, start: start, typed: 500)
        #expect(settling.next(observe(400)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(1_000)) == .finish(.unchanged))
    }

    @Test func aChangedModelIsAReactionThatEndsTheWindowEarly() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(60, change: 50)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(150, change: 50)) == .finish(.settled))
    }

    @Test func onlyTheFirstModelChangeCountsSoAnimatedPagesStillSettle() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(60, change: 50)) == .wait(SettlePolicy.trafficPoll))
        #expect(settling.next(observe(150, change: 140)) == .finish(.settled))
    }

    @Test func modelChangesFromBeforeTheInputAreIgnored() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(350, change: -20)) == .finish(.unchanged))
    }

    @Test func stopsAtTheLimit() {
        var settling = Settling(.action, start: start)
        #expect(settling.next(observe(29_990, busy: true)) == .wait(.milliseconds(10)))
        #expect(settling.next(observe(30_000, busy: true)) == .finish(.limited))
    }

    @Test func idleCountsEarlierActivityAndNeedsNoReaction() {
        var quiet = Settling(.idle(within: .seconds(5)), start: start)
        #expect(quiet.next(observe(0)) == .finish(.unchanged))
        var recent = Settling(.idle(within: .seconds(5)), start: start)
        #expect(recent.next(observe(0, event: -100)) == .wait(SettlePolicy.trafficPoll))
        #expect(recent.next(observe(200, event: -100)) == .finish(.settled))
    }
}

@MainActor
final class FakeSignals: SettleSignals {
    private let start = ContinuousClock.now
    private(set) var elapsed: Duration = .zero
    var pageEvents: [Duration] = []
    var traffic: [Duration] = []
    var changes: [Duration] = []

    var now: ContinuousClock.Instant {
        start + elapsed
    }

    func observe() -> SettleObservation {
        SettleObservation(
            now: now,
            pageEvent: pageEvents.filter { $0 <= elapsed }.max().map { start + $0 },
            traffic: traffic.filter { $0 <= elapsed }.max().map { start + $0 },
            change: changes.filter { $0 <= elapsed }.max().map { start + $0 }
        )
    }

    func expect(_ model: PageModel) {}

    func pause(for duration: Duration) async {
        let wake = pageEvents.filter { $0 > elapsed }.min().map { min($0, elapsed + duration) } ?? elapsed + duration
        elapsed = wake
    }
}

@MainActor
struct ActionSettlerTests {
    @Test func doNothingClicksReturnAfterTheReactionWindow() async {
        let signals = FakeSignals()
        let outcome = await ActionSettler(signals: signals).settle(.action, since: signals.now)
        #expect(outcome == .unchanged)
        #expect(signals.elapsed == SettlePolicy.action.reactionWindow)
    }

    @Test func aVisibleChangeEndsTheWaitAfterTheQuietPeriod() async {
        let signals = FakeSignals()
        signals.changes = [.milliseconds(50)]
        let outcome = await ActionSettler(signals: signals).settle(.action, since: signals.now)
        #expect(outcome == .settled)
        #expect(signals.elapsed >= .milliseconds(150))
        #expect(signals.elapsed < SettlePolicy.action.reactionWindow)
    }

    @Test func delayedURLChangeAfterAFetchIsWaitedFor() async {
        let signals = FakeSignals()
        signals.traffic = [.milliseconds(10), .milliseconds(40)]
        signals.pageEvents = [.milliseconds(830)]
        let settler = ActionSettler(signals: signals)
        let before = Fixture.model([Fixture.element(.button, "Load report")], title: "Home")
        let after = Fixture.model([Fixture.element(.button, "Load report"), Fixture.element(.heading, "Report ready", y: 200)], title: "Report")
        let outcome = await settler.settle(.action, since: signals.now)
        #expect(outcome == .settled)
        #expect(signals.elapsed < .milliseconds(830))
        let model = try? await settler.confirmedModel(after: outcome, changingFrom: before) {
            signals.elapsed >= .milliseconds(830) ? after : before
        }
        #expect(model == after)
        #expect(signals.elapsed >= .milliseconds(930))
    }

    @Test func followUpGivesUpWhenNothingElseHappens() async {
        let signals = FakeSignals()
        signals.traffic = [.milliseconds(10)]
        let settler = ActionSettler(signals: signals)
        let before = Fixture.model([Fixture.element(.button, "Do nothing")])
        let outcome = await settler.settle(.action, since: signals.now)
        let model = try? await settler.confirmedModel(after: outcome, changingFrom: before) { before }
        #expect(model == before)
        #expect(signals.elapsed == .milliseconds(110) + SettlePolicy.followUp.reactionWindow)
    }

    @Test func unchangedOutcomesRenderOnce() async {
        let signals = FakeSignals()
        var renders = 0
        let before = Fixture.model([Fixture.element(.button, "Do nothing")])
        _ = try? await ActionSettler(signals: signals).confirmedModel(after: .unchanged, changingFrom: before) {
            renders += 1
            return before
        }
        #expect(renders == 1)
    }
}

struct EventReactionTests {
    @Test func automationCookiesAndDownloadProgressAreNotPageReactions() {
        #expect(!EventType.actionDone.isPageReaction)
        #expect(!EventType.actionGranted.isPageReaction)
        #expect(!EventType.cookiesChanged.isPageReaction)
        #expect(!EventType.downloadProgress.isPageReaction)
        #expect(EventType.pageURL.isPageReaction)
        #expect(EventType.pageTitle.isPageReaction)
        #expect(EventType.navigationStarted.isPageReaction)
        #expect(EventType.dialogShown.isPageReaction)
    }
}

@MainActor
struct ModelWarmerTests {
    @Test func backsOffWhileThePageStaysTheSame() {
        #expect(ModelWarmer.interval(after: .seconds(1), unchanged: true) == .seconds(2))
        #expect(ModelWarmer.interval(after: .seconds(8), unchanged: true) == ModelWarmer.longestInterval)
        #expect(ModelWarmer.interval(after: .seconds(8), unchanged: false) == ModelWarmer.shortestInterval)
    }
}
