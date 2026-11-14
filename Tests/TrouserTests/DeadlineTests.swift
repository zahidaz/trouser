import Testing
@testable import Trouser

@MainActor
struct DeadlineTests {
    @Test func returnsWhenTheOperationNeverFinishes() async {
        let start = ContinuousClock.now
        await awaitingAtMost(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func returnsAsSoonAsTheOperationFinishes() async {
        var ran = false
        let start = ContinuousClock.now
        await awaitingAtMost(.seconds(30)) { ran = true }
        #expect(ran)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
