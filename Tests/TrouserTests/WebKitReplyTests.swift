import Foundation
import Testing
@testable import Trouser

@MainActor
struct WebKitReplyTests {
    @Test func returnsTheAnswer() async throws {
        let value: Int = try await WebKitReply.value(within: .seconds(1)) { reply in
            reply(.success(7))
        }
        #expect(value == 7)
    }

    @Test func returnsAnAnswerThatComesLater() async throws {
        let value: Int = try await WebKitReply.value(within: .seconds(1)) { reply in
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(20))
                reply(.success(3))
            }
        }
        #expect(value == 3)
    }

    @Test func givesUpWhenThePageNeverAnswers() async {
        var kept: ((Result<Int, Error>) -> Void)?
        let start = ContinuousClock.now
        await #expect(throws: DriverError.self) {
            let _: Int = try await WebKitReply.value(within: .milliseconds(50)) { kept = $0 }
        }
        #expect(ContinuousClock.now - start < .seconds(1))
        kept?(.success(1))
        kept?(.success(2))
    }

    @Test func describesTheTimeout() {
        #expect(DriverError.unanswered(.seconds(10)).localizedDescription == "the page did not answer within 10 s")
    }
}
