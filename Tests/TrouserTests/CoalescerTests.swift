import Testing
@testable import Trouser

@MainActor
struct CoalescerTests {
    private final class Counter {
        var runs = 0
    }

    private func settle(_ counter: Counter, reaching runs: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while counter.runs < runs, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func runsOnceForABurst() async throws {
        let counter = Counter()
        let coalescer = Coalescer(delay: .milliseconds(30)) { counter.runs += 1 }
        for _ in 0..<20 {
            coalescer.schedule()
        }
        #expect(counter.runs == 0)
        try await settle(counter, reaching: 1)
        #expect(counter.runs == 1)
    }

    @Test func runsAgainForAChangeAfterTheRun() async throws {
        let counter = Counter()
        let coalescer = Coalescer(delay: .milliseconds(30)) { counter.runs += 1 }
        coalescer.schedule()
        try await settle(counter, reaching: 1)
        coalescer.schedule()
        coalescer.schedule()
        try await settle(counter, reaching: 2)
        #expect(counter.runs == 2)
    }

    @Test func waitsForTheDelayBeforeRunning() async throws {
        let counter = Counter()
        let coalescer = Coalescer(delay: .milliseconds(300)) { counter.runs += 1 }
        coalescer.schedule()
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.runs == 0)
        try await settle(counter, reaching: 1)
        #expect(counter.runs == 1)
    }
}
