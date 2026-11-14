import Foundation
import Testing
@testable import Trouser

@MainActor
struct ReactionTests {
    @Test func returnsOnceThePageReacts() async throws {
        var reads = 0
        let start = ContinuousClock.now
        let value = try await Reaction.read({ reads += 1; return reads }, within: .seconds(5), every: .milliseconds(5)) { $0 >= 2 }
        #expect(value == 2)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func stopsAtTheLimitWithoutAReaction() async throws {
        let start = ContinuousClock.now
        let value = try await Reaction.read({ 0 }, within: .milliseconds(60), every: .milliseconds(10)) { $0 > 0 }
        let elapsed = ContinuousClock.now - start
        #expect(value == 0)
        #expect(elapsed >= .milliseconds(60))
        #expect(elapsed < .milliseconds(500))
    }

    @Test func waitsBeforeTheFirstRead() async throws {
        let start = ContinuousClock.now
        var readAt: ContinuousClock.Instant?
        _ = try await Reaction.read({ readAt = .now }, within: .seconds(1), every: .milliseconds(20)) { true }
        #expect(try #require(readAt) - start >= .milliseconds(20))
    }
}
